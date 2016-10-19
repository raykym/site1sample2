package Site1::Controller::Filestore;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop::ForkCall;

use DateTime;
use Data::Dumper;
use Encode;
use MIME::Base64::URLSafe; # uid,oidをページで受け渡すにはエンコードが必要

use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1';
use Sessionid; #oidをuidと同じ仕組みで提供するため

# 初期値は16MB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 100 * 1024 * 1024; # 100MBとする

sub upload {
  my $self = shift;

     $self->app->log->debug("DEBUG: MOJO_MAX_MESSAGE_SIZE:  $ENV{MOJO_MAX_MESSAGE_SIZE}");

  # list表示のための検索(直近５個のみ表示用)
  my $config = $self->app->plugin('Config');
  my $sth_uploadlist = $self->app->dbconn->dbh->prepare($config->{sql_uploadlist});
  my $uid = $self->stash('uid');
  my $res;
    if (defined $uid ) {
         $self->app->log->debug('get user upload file list.');
         $sth_uploadlist->execute($uid);
        if ( $sth_uploadlist->rows == 0 ) {
           my $dum = { dummy => {filename => '未登録'}};
                  $self->stash(filelist => $dum );
           return $self->render(msg => '');
           }
      my $opt = 'filename'; #個別用のカラムを指定する
         $res = $sth_uploadlist->fetchall_hashref($opt);
    #  my @aaa = Dumper $res;
    #     $self->app->log->debug("DEBUG: @aaa  ");
       }

         $self->stash(filelist => $res );
         $self->render(msg => '一応、何でもuploadは可能だけど、chromeでサポートしていないフォーマットでは表示できないケースもあります。');

    # クリアした方がメモリーリークしないと思って書いたもの。。。
    undef $res;
    undef $sth_uploadlist;
}

sub uploadact {
    my $self = shift;

    my $config = $self->app->plugin('Config');
    my $sth_uploadfile = $self->app->dbconn->dbh->prepare($config->{sql_uploadfile});

    my $fileobj = $self->req->upload('filename');
    return $self->redirect_to('/menu/upload') unless (defined $fileobj);
    return $self->redirect_to('/menu/upload') if ($fileobj->size == 0 );

    # 16MBを超えるとエラーを表示する エラーはBAD GATEWAYになる
    # ここではアップロード後に100MB以上でエラーとする。ちょっと無意味な判定
    if ($fileobj->size > 100*1024*1024 ) { 
            return $self->render(template => 'filestore/upload', msg => 'File size ERROR!!!!');
       }

   # jQueryを使っているとそのままではuploadされない。。。data-ajax="false"が必要
   #MOJO_MAX_MESSAGE_SIZEはデフォルト16MB ->100MBに変更中
   #Mojo::Uploadのオブジェクト
    my $filename = $fileobj->filename;
    my $data = $fileobj->asset->slurp; 
    my $mimetype = $fileobj->headers->content_type;
   
    my $uid = $self->stash('uid');
    # uidを再度uid処理でoidとして利用する
    my $oid = Sessionid->new($uid)->uid;
    my $checkdate = DateTime->now();

           $sth_uploadfile->execute($oid,$filename,$data,$uid,$mimetype,$checkdate);
           $self->app->log->debug("DEBUG: write $oid");
           #コメントカラムはこの時は除外
            my $dum = { dummy => {filename => '確認中・・・'}};
            $self->stash(filelist => $dum); # 登録直後の再読み込み対応
            $self->render(template => 'filestore/upload', msg => 'file uploaded');

    undef $sth_uploadfile;
    undef $data;
    undef $fileobj;

}

sub listview {
    my $self = shift;
    # リスト表示のための共通処理

       $self->app->log->debug('Notice: list process passed!!!!');

    my $pcount = 5; # 1ページの表示個数

    # ページコントロール初期設定 1ページ=5 携帯ならこんなものと考えた
    my $page = $self->param('page');
    if (! defined $page ) {
            $page = '1';  #初期値は表示から1とした（検索は0からだけど)
        }

    # uidでリストを取得、ページ処理はアプリ内で、DBは一覧を送るのみ
    my $config = $self->app->plugin('Config');
    my $sth_getuploadlist = $self->app->dbconn->dbh->prepare($config->{sql_getuploadlist});
    my $uid = $self->stash('uid');

       $sth_getuploadlist->execute($uid);
    my $count = $sth_getuploadlist->rows; # 登録数
     if (! defined($count)) { 
       #未登録の場合 
       # ダミーデータを渡す
    my @slice;
       $self->stash('filelist' => \@slice);
       $self->stash('page' => $page);

       #処理はlistview_pで行う。 
       return 1; #underの為、

    } else {

    # ページの最大値
    my $sur = $count % $pcount;
    my $pmax = int( $count / $pcount);
    if ($sur ne 0 ) { $pmax++ }; #余りがあれば+1

    if ($page eq 0) { $page = $pmax }; #zeroなら最大値に
    if ($page gt $pmax) { $page = 1 }; #最大値を超えたら1にする。

    my @res;
    my $filelist = $sth_getuploadlist->fetchall_arrayref(@res);

    my $filter = $self->param('f');
       if ( $filter eq '' ) { $filter = 0 }

       # $filterが０か無設定ならこのままスルー
       # f=1で画像を選択する
       if ( $filter == 1 ) {
          @$filelist = grep { if ( $_->[2] =~ /jpeg|jpg|png|gif/ ) { $_ }} @$filelist;
       }

    my $start = int(($page -1) * $pcount);
    my @slice = splice(@$filelist,$start,$pcount); #開始位置から5個
       # @slice = ([ oid, filename, mime, dellock ]..... )
       # oidをurlsafeエンコード

       @slice = map { $_->[0] = urlsafe_b64encode($_->[0]); $_ } @slice;
# 以下はmapの置き換えコード
#        foreach my $i (@slice){
#                $i->[0] = urlsafe_b64encode($i->[0]);
#        }

# dellock = 1の時はdisabled=""をセットする 0はヌルにする リストは5個だから速度は気にならない。
       @slice = map {  $_->[3] = 'disabled=""' if ( $_->[3] eq 1 ); $_ } @slice;
       @slice = map {  $_->[3] = "" if ( $_->[3] eq 0 ); $_ } @slice;

    $self->stash('filelist' => \@slice);
    $self->stash('page' => $page);

    undef $filelist;
    undef $start;
    undef $sth_getuploadlist;

   } # $countのelse

   return 1;  #under動作の為
}

sub listview_p {
    my $self = shift;
    # listvew表示用

    $self->render(template => 'filestore/listview', msg => '');
}

sub imgload {
    my $self = shift;
   # 認証経由のアクセス
   # Filestoreで登録したファイルを表示で利用するためのパス

    # usercheckでemail,username,uidは送られる
    my $uid = $self->stash('uid');

    use Mojolicious::Types;
    my $types = Mojolicious::Types->new;

    my $config = $self->app->plugin('Config');
    my $sth_getimag = $self->app->dbconn->dbh->prepare($config->{sql_getimag});
    my $oid_url = $self->param('oid');
    my $oid = urlsafe_b64decode($oid_url);
       $self->app->log->debug("DEBUG: $oid");

       $sth_getimag->execute($oid,$uid);
    my $res = $sth_getimag->fetchrow_hashref();

       #結果が取れない場合エラーを表示
       return $self->render(text => 'error') if (! defined $res);

    my $extention = $types->detect($res->{mime});

    $self->render(data => $res->{data},format => $extention);
}

sub imgcomm {
    my $self = shift;
   # Filestoreで登録したファイルを表示で利用するためのパス
   # chatroomでアイコン表示するためにoidのみで表示するパス
   # walkworld向けにresize機能を用意した。処理が多くなると重くなるのは必定

    use GD;

    use Mojolicious::Types;
    my $types = Mojolicious::Types->new;

    my $config = $self->app->plugin('Config');
    my $sth_getimagcomm = $self->app->dbconn->dbh->prepare($config->{sql_getimagcomm});
    my $oid_url = $self->param('oid');
    my $oid = urlsafe_b64decode($oid_url);
       $self->app->log->debug("DEBUG: $oid");
    my $resize = $self->param('resize');
   #    $self->app->log->debug("DEBUG: $resize");

       $sth_getimagcomm->execute($oid);
    my $res = $sth_getimagcomm->fetchrow_hashref();

       #結果が取れない場合エラーを表示
       return $self->render(text => 'error') if (! defined $res);

       # Resise用処理  &resize=1等、数字は何でも良いけれど
    my $newImage = 0;
       if (defined $resize) {
           my $bimage = GD::Image->newFromJpegData($res->{data});
           my @bound = $bimage->getBounds();

           my $wx = 50 / $bound[0];
           my $hx = 50 / $bound[1];

           my $w = int($bound[0] * $wx); 
           my $h = int($bound[1] * $hx);
           $newImage = new GD::Image($w, $h); 
           $newImage->copyResized($bimage, 0, 0, 0, 0, $w, $h, $bound[0], $bound[1]); 
       }

    my $extention = $types->detect($res->{mime});
    if ( $newImage == 0){
    $self->render(data => $res->{data},format => $extention);
       $self->app->log->debug("DEBUG: base image");
      } else {
    $self->render(data => $newImage->jpeg,format => $extention);
       $self->app->log->debug("DEBUG: resize image");
      }
}

sub fileview {
    my $self = shift;

    my $config = $self->app->plugin('Config');
    my $sth_getfile = $self->app->dbconn->dbh->prepare($config->{sql_getfile});
    my $oid_url = $self->param('oid');
    my $oid = urlsafe_b64decode($oid_url);
       $sth_getfile->execute($oid);
    # data以外を取得
    my $res = $sth_getfile->fetchrow_hashref;
    my $mime = $res->{mime};

       $self->stash('oid' => $oid_url );
       $self->stash('filename' => $res->{filename});
       $self->stash('mime' => $res->{mime});
       $self->stash('datetime' => $res->{datetime});
       $self->stash('comment' => $res->{comment});

    # 画像
    if ($mime =~ /jpg|jpeg|png|gif/ ){
        return $self->render(template => 'filestore/imgview',msg => '');
        }
    # 動画、音楽
    if ($mime =~ /mpeg|3gp|mp4|mpg|realtext|mp3/ ){
        return $self->render(template => 'filestore/videview',msg => '');
        }
    
    $self->render(msg => '');
}

sub fileviewact {
    my $self = shift;
    # 画像のコメントつけるための処理

    my $config = $self->app->plugin('Config');
    my $sth_writecomment = $self->app->dbconn->dbh->prepare($config->{sql_writecomment});

    my $oid_url = $self->param('oid');
    my $oid = urlsafe_b64decode($oid_url);
    my $comment = $self->param('comment');

    $sth_writecomment->execute($comment,$oid);
    $self->app->log->debug('DEBUG: write comment!');

    #再描画の為に再度DBから情報取得してimgviewテンプレートへ戻る
    my $sth_getfile = $self->app->dbconn->dbh->prepare($config->{sql_getfile});
       $sth_getfile->execute($oid);
    # data以外を取得
    my $res = $sth_getfile->fetchrow_hashref;

       $self->stash('oid' => $oid_url );
       $self->stash('filename' => $res->{filename});
       $self->stash('mime' => $res->{mime});
       $self->stash('datetime' => $res->{datetime});
       $self->stash('comment' => $res->{comment});

    $self->render(template => 'filestore/imgview',msg => '');
}

sub delfileview {
    my $self = shift;
    #listfileを受けての表示
    $self->render(msg => '削除は一度に1つづつです！！！');
}

sub delfileviewact {
    my $self = shift;
    #oidが来たら消すだけ。。。。
    # checkboxはdelfileを指定、内容はoid 複数の可能性があるので＠
    my @oid_url = $self->param('delfile');
       $self->app->log->debug("DEBUG delfile: @oid_url");
    my @oid = map { $_ = urlsafe_b64decode($_); $_ } @oid_url;
       $self->app->log->debug("DEBUG oid: @oid");
    my $config = $self->app->plugin('Config');
    my $sth_deleteuploadfile = $self->app->dbconn->dbh->prepare($config->{sql_deleteuploadfile});

       foreach my $oid (@oid){
           $sth_deleteuploadfile->execute($oid);
           $self->app->log->debug("Notice: $oid File delete!!!");
       }

    $self->redirect_to('/menu/delfileview');
}

sub seticon {
    my $self = shift;

    $self->render(msg => '');
}

sub seticonact {
    my $self = shift;
    # アイコン登録画像の変更、及び削除ロックの切り替え（アイコンは削除処理ではスルーされる。)

    my $config = $self->app->plugin('Config');
    my $sth_outdellock = $self->app->dbconn->dbh->prepare($config->{sql_outdellock});
    my $sth_seticon = $self->app->dbconn->dbh->prepare($config->{sql_seticon});
    my $sth_setdellock = $self->app->dbconn->dbh->prepare($config->{sql_setdellock});
    my $icon_old = $self->stash('icon');
       $icon_old = urlsafe_b64decode($icon_old);

    my $email = $self->stash('email');
       $sth_outdellock->execute($icon_old); # dellockの解除
       $self->app->log->debug("DEBUG: outdellock: $icon_old");

    my $icon_new = $self->param('oid');
       $icon_new = urlsafe_b64decode($icon_new);

       $sth_seticon->execute($icon_new,$email);
       $sth_setdellock->execute($icon_new);
       $self->app->log->debug("DEBUG: iconset $icon_new : $email and dellock");

   $self->redirect_to('/menu/settings');
   # $self->render( template => 'login/menusettings', msg => '' );
}

1;
