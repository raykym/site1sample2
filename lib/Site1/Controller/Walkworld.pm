package Site1::Controller::Walkworld;
use Mojo::Base 'Mojolicious::Controller';

use utf8;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use Encode;
use DateTime;
use Data::Dumper;
use Mojo::IOLoop::Delay;
use Clone qw(clone);
use Math::Trig qw(great_circle_distance rad2deg deg2rad pi);


# 独自パスを指定して自前モジュールを利用
use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1';
use Inputchk;
use Sessionid;

# This action will render a template
sub view {
  my $self = shift;

  $self->render(msg_w => '');
}

my $clients = {};

# google pubsub TEST
sub echo2 {
  my $self = shift;
     $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
  my $id = sprintf "%s", $self->tx->connection;
     $clients->{$id} = $self->tx;

   my $userid = $self->stash('uid');

      $self->on(message => sub {
           my ($self,$msg) = @_;

           my $jsonobj = from_json($msg);

         });  # on message

      $self->on(finish => sub {
           my ($self,$msg) = @_;

              $self->app->log->debug("DEBUG: On finish!!");
         }); # on finish

  my $stream = Mojo::IOLoop->stream($self->tx->connection);
        $stream->timeout(0);  # no timeout!
        $self->inactivity_timeout(1000);

} # echo2



# Cloud Pubsub receve 
sub rcvpush {
    my $self = shift;

    my $messages = $self->req->json;

    my $wwdb = $self->app->mongoclient->get_database('WalkWorld');
    my $cloudpubsub = $wwdb->get_collection('cloudpubsub');
    my $wwlogdb = $self->app->mongoclient->get_database('WalkWorldLOG');
    my $cloudpubsublog = $wwlogdb->get_collection('cloudpubsublog');

    my $jsonobj = { %$messages,ttl => DateTime->now() };  
    my $debgjsonobj = to_json($jsonobj);
       $self->app->log->debug("DEBUG: $debgjsonobj");

       $cloudpubsub->insert($jsonobj);
       $cloudpubsublog->insert($jsonobj);

       # 204 is Ack 
       $self->render( text => '', status => '204');
}

my $stream_io = {};

my $debugCount = 6;

# WalkWorld websocket endpoint
sub echo {
    my $self = shift;

       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx->connection;
       $clients->{$id} = $self->tx;

    my $userid = $self->stash('uid');

    my $wwdb = $self->app->mongoclient->get_database('WalkWorld');
    my $timelinecoll = $wwdb->get_collection('MemberTimeLine');

    my $wwlogdb = $self->app->mongoclient->get_database('WalkWorldLOG');
    my $timelinelog = $wwlogdb->get_collection('MemberTimeLinelog');

  # WalkChat用
    my $holldb = $self->app->mongoclient->get_database('holl_tl');
    my $walkchatcoll = $holldb->get_collection('walkchat');
    my $walkchatdrpmsg = $holldb->get_collection('walkchat_dropmsg');

    my $username = $self->stash('username');
    my $icon = $self->stash('icon'); #encodeされたままのはず。
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

    my $chatname = "WALKCHAT";
    my @chatArray = ( $chatname );

    my $delay_once = 'true';

    my $userobj;  #接続しているuserの位置情報

    #NPCへのチャットはバイパスする mognodb負荷軽減
      if ( ! ( $username =~ /npcuser/ ) || ( $username =~ /searchnpc/ )) {  

    # GPS情報が来るまでdelayする
     Mojo::IOLoop::Delay->new->steps(
          sub {
              my $delay = shift;
                 # とりあえず、GPSが20秒で来るはずなのでdelayを行う(chromebookでは失敗するケースがある、、、)  
                 Mojo::IOLoop->timer( 20 => $delay->begin );
                 $self->app->log->debug("DEBUG: $username delay ON");
              },
          sub {
              my ($delay, @args) = @_;

                  # mongo3.2用 チャットの文を3000ｍ以内に限る
                    my $walkchat_cursole = $walkchatcoll->query({ geometry => {
                                                        '$nearSphere' => {
                                                        '$geometry' => {
                                                         type => "point",
                                                             "coordinates" => [ $userobj->{loc}->{lng} , $userobj->{loc}->{lat} ]},
                                                        '$minDistance' => 0,
                                                        '$maxDistance' => 3000
                                      }},
                                  })->sort({_id => -1});
          

        my @allcursole = $walkchat_cursole->all;
           @allcursole = reverse(@allcursole); 

        foreach my $line (@allcursole){
              $clients->{$id}->send({json => $line });
        }

           $self->app->log->debug("DEBUG: $username delay BLOCK END!");
           $delay_once = 'false';
           } # delay block

        )->wait if ($delay_once);

      } # NPC bipass block


 # on message Websocket
  $self->on(message => sub {
        my ($self,$msg) = @_;

           $self->app->log->debug("DEBUG: $username ws msg: $msg");

           my $jsonobj = from_json($msg);

           # chatデータの判定用データ Makerでも利用
           $userobj = clone($jsonobj) if ( $jsonobj->{userid} eq $userid ); 

       #walkchat処理
           if ( defined $jsonobj->{chat} ){

         #      if ( $userobj->{category} eq "NPC" ) { return; }   #NPC bypass

               my  $chatevt = clone($jsonobj);

               $self->app->log->debug("INFO: $username chat msg: $msg");

           #NGワードチェック
           my $chkword = encode_utf8($chatevt->{chat});  #上でmsgをエンコードしたから不要になるのでは？

           my $chkmsg = Inputchk->new($chkword); 
              $chkmsg->ngword;
           my $res_chkmsg = $chkmsg->result;
           my $chkmsg_string = decode_utf8($chkmsg->{string});
              $self->app->log->debug("DEBUG: res_chkmsg: $res_chkmsg | $chkmsg_string ");
           undef $chkmsg;

           my $chatobj;

            # drop処理
            if ($res_chkmsg > 0 ) {

                  my $drpMSG = $chkword;
                     $drpMSG = decode_utf8($drpMSG);

                  #日付設定 重複記述あり
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  # TTLレコードを追加する。
                  my $ttl = DateTime->now();

                     $chatobj = { geometry => $chatevt->{geometry},
                                       loc => $chatevt->{loc},
                                  icon_url => $icon_url,
                                  username => $username,
                                       hms => $dt->hms,
                                       chat => $drpMSG,
                                       ttl => $ttl,
                                };

                  # walkchat_dropmsgへの書き込み dropメッセージのバックアップ
                  $walkchatdrpmsg->insert($chatobj); 

                  } # if res_chkmsg
              
              my $msgtxt = $chatevt->{chat}; # chat用のメッセージ

              # DROPの場合はメッセージを差し替える
              if ($res_chkmsg > 0 ) { $msgtxt = 'キーワードチェックで除外されました。'; }

              undef $res_chkmsg;

                  # DROPメッセージで無い場合の処理
                  #日付設定 重複記述あり
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  # TTLレコードを追加する。
                  my $ttl = DateTime->now();

                     $chatobj = { geometry => $chatevt->{geometry},
                                       loc => $chatevt->{loc},
                                  icon_url => $icon_url,
                                  username => $username,
                                       hms => $dt->hms,
                                      chat => $msgtxt,
                                       ttl => $ttl,
                                };

                   # walkchatへの書き込み
                   $walkchatcoll->insert($chatobj);
                   $self->app->log->debug("DEBUG: $username insert chat");

                   my $chatjson = to_json($chatobj);
                      
                   # 書き込み通知
                   $self->redis->publish( $chatname , $chatjson );
                   $self->redis->expire( $chatname => 3600 );
                   $self->app->log->debug("DEBUG: $username publish WALKCHAT");

           return;
           } #chat


      # 攻撃確認シグナルチェック npcからの戻り値 ,攻撃シグナルは重複するケースが在るため
           # 書き込みはLOG側
           if ( defined $jsonobj->{hitname} ){
        
               $timelinelog->insert($jsonobj);
               $self->app->log->debug("DEBUG: $username hitname write");

               #WalkWorld.MemberTimeLineに残るデータを削除する。
               $timelinecoll->delete_many({"userid" => "$jsonobj->{to}"}); # mognodb3.2
               $self->app->log->debug("DEBUG: $username hit delete many execute.");

             #撃墜結果を集計      
                                          #NPCが接続した状態で、executeしたuidのデータを作成する。 
               my $executelist = $timelinelog->find({ 'execute' => $jsonobj->{execute}, 'hitname' => {'$exists' => 1} });

               my @execute = $executelist->all;
               my $pcnt = $#execute + 1;

               $self->redis->set( "GHOSTGET$jsonobj->{execute}" => $pcnt );

               undef @execute;
               undef $pcnt;
               undef $jsonobj;
               return;
               }


      # 攻撃シグナルの送信 toにuserid
           if ( $jsonobj->{to} ) {
              $self->app->log->debug("DEBUG: $username Attack send: $msg");

                      # TTLレコードを追加する。
                      $jsonobj = { %$jsonobj,ttl => DateTime->now() };  
                      $timelinecoll->insert($jsonobj);
                   #   $timelinelog->insert($jsonobj); # hitnameパラメータを記録するのでtoはLOGから除外する。

                      $self->app->log->debug("DEBUG: $username execute Command write....");

                      undef $jsonobj;
                      return;

              } # if $jsonobj->to

          # putmaker処理 redisへマーカーをセット
            if ( defined $jsonobj->{putmaker}) {
              # maker固有のuidを設定
              my $makeruid = Sessionid->new($userid)->uid;
              my $makerobj = $jsonobj->{putmaker};
                 $makerobj->{userid} = $makeruid;
                 $makerobj = { %$makerobj,ttl => DateTime->now() };
              my $makerobj_json = to_json($makerobj);
                 $self->redis->set("Maker$makeruid" => $makerobj_json);
                 $self->redis->expire("Maker$makeruid" => 1800);

              return;
            } #putmaker

       # 以下、map系のメッセージ処理
           # TTLレコードを追加する。
           $jsonobj = { %$jsonobj,ttl => DateTime->now() };  

           $self->app->log->debug("DEBUG: $username msg: $msg");

           # 負荷軽減になるのか？　MemberTimeLineを1個に限定出来るのか？　書き込み前に削除を加えてみる
           $timelinecoll->delete_many({"userid" => "$jsonobj->{userid}"}); # mognodb3.2

           # TTl DB
           $timelinecoll->insert($jsonobj);
           # LOG用DB
           $timelinelog->insert($jsonobj);

           # 攻撃を受けたか確認する　基本NPC用
           my $attack_chk = $timelinecoll->find_one({ "to" => $userid });
           my $jsonattackchk = to_json($attack_chk);
              $self->app->log->debug("DEBUG: $username $jsonattackchk") if ($attack_chk); 
              if ($attack_chk) {
                                $clients->{$id}->send({ json => $attack_chk });
                                return;  # この処理が入るとボットはダウンするので終了する。
                               }

           # 現状の情報を送信 
           # mongo3.2用 3000m以内のデータを返す
           my $geo_points_cursole = $timelinecoll->query({ geometry => { 
                                                           '$nearSphere' => {
                                                           '$geometry' => {
                                                            type => "point",
                                                                "coordinates" => [ $jsonobj->{loc}->{lng} , $jsonobj->{loc}->{lat} ]}, 
                                                           '$minDistance' => 0,
                                                           '$maxDistance' => 3000 
                                     }}});

            # DEBUG not work cursole clear becose non DATAs
            #  $self->app->log->debug("DEBUG: $username MongoDB find.");
            #      my @geo_points = $geo_points_cursole->all;
            #      my $ddump = Dumper(@geo_points);
            #      $self->app->log->debug("DEBUG: Dumper: $ddump");

            #データから最新ポイントだけを抽出するには、降順で時刻をsortして、
            my @all_points = $geo_points_cursole->all;
            
         #   my $datadebug = Dumper(@all_points);
         #   $self->app->log->debug("DEBUG: all_points: $datadebug");

            my @all_points_sort = sort { $b->{time} <=> $a->{time} } @all_points;

            # push時にgrepで重複を弾く
            my @pointlist = ();
               foreach my $po ( @all_points_sort){
                   push(@pointlist,$po) unless grep { $_->{userid} =~ /^\Q$po->{userid}\E$/ } @pointlist;
                   }
            undef @all_points;
            undef @all_points_sort;

          #    $self->app->log->debug("DEBUG: GEO points send###################");

       #makerをredisから抽出して、距離を算出してリストに加える。

             my $makerkeylist = $self->redis->keys("Maker*");
             my @makerlist = ();

             foreach my $aline (@$makerkeylist) {
                       my $makerpoint = from_json($self->redis->get($aline));

                      # radianに変換
                      my @s_p = NESW($userobj->{loc}->{lng}, $userobj->{loc}->{lat});
                      my @t_p = NESW($makerpoint->{loc}->{lng}, $makerpoint->{loc}->{lat});
                      my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                       
                      if ( $t_dist < 3000) {
                       push (@makerlist, $makerpoint );
                       }
                   }

               # makerとメンバーリストを結合する
                 push @pointlist,@makerlist;

               #    my @pointlist = $geo_points_cursole->all;
                   my $listhash = { 'pointlist' => \@pointlist };
                   my $jsontext = to_json($listhash); 
                      $clients->{$id}->send($jsontext);
                      $self->app->log->debug("DEBUG: $username geo_points: $jsontext");

                   undef @pointlist;
                   undef @makerlist;
                   undef $listhash;
                   undef $jsontext;
                   undef $geo_points_cursole;

  }); # on message

  $self->on(finish => sub {
        my ($self,$msg) = @_;

        $self->app->log->debug("DEBUG: $username On finish!!");
        delete $clients->{$id};

        #redis unsubscribe
        $self->redis->unsubscribe(\@chatArray);

     # 再接続で利用するから。
     #   undef $timelinecoll;
     #   undef $timelinelog;
     #   undef $wwdb;
     #   undef $wwlogdb;

     #   undef $self->tx->connection;
     #   undef $self->tx;
  });

sub NESW { deg2rad($_[0]), deg2rad( 90 - $_[1]) }

#redis receve
     $self->redis->on(message => sub {
                  my ($redis,$mess,$channel) = @_;
                      $self->app->log->debug("DEBUG: on channel:($username) $mess");

                      if ( $channel ne $chatname ) { return; } # filter channel

                      my $messobj = from_json($mess);

                      #攻撃シグナルは優先で送信する。
                      if ( defined $messobj->{to} ) {
                         $clients->{$id}->send($mess);
                         return;
                      }
                      
                      if ( $userobj->{category} eq "NPC" ) { return; } # NPCへはチャットを送信しない

                      if ( defined $userobj ){
                      # radianに変換
                      my @s_p = NESW($userobj->{loc}->{lng}, $userobj->{loc}->{lat});
                      my @t_p = NESW($messobj->{loc}->{lng}, $messobj->{loc}->{lat});
                      my $t_dist = great_circle_distance(@s_p,@t_p,6378140);

                      if ( $t_dist < 3000 ){
                        if ( defined $clients->{$id} ){ 
                           $clients->{$id}->send($mess);
                           $self->app->log->debug("DEBUG: send websocket:($username) $mess");
                            }
                          }

                      } # if $userobj
                       return;
                  });  # redis on message

     $self->redis->subscribe(\@chatArray, sub {
                   my ($redis, $err) = @_;
                 #     return $redis->publish( $chatname => $err) if $err;
                      $self->app->log->debug("DEBUG: $username redis subscribe");
                      return $redis->incr(@chatArray);
                   });
     $self->redis->expire( \@chatArray => 3600 );

     $self->redis->on(error => sub {
                   my ($redis,$err) = @_;
                      $self->app->log->info("DEBUG: $username redis error: $err");
                   });

      # 複数クライアントに対応している為 websocket毎に stream_ioはあまり意味がないのか？送信するわけでも無いから
         $stream_io->{$id} = Mojo::IOLoop->stream($id);
         $stream_io->{$id}->timeout(30);  # 30sec
         $self->inactivity_timeout(12000); # 12sec 

 # for NYTProf
 #     $debugCount--;
 #     if ($debugCount == 0 ) {
 #        exit;
 #     }

} # echo

sub pointget {
    my $self = shift;
  # mongodbからredisに移行
    my $uid = $self->stash('uid');
#    my $wwlogdb = $self->app->mongoclient->get_database('WalkWorldLOG');
#    my $timelinelog = $wwlogdb->get_collection('MemberTimeLinelog');
                                          # executeが自分かつ、hitnameが存在する
#    my $executelist = $timelinelog->find({ 'execute' => $uid, 'hitname' => {'$exists' => 1} });

#    my @execute = $executelist->all;
#    my $pcnt = $#execute + 1;

    my $pcnt = $self->redis->get("GHOSTGET$uid");

    if ( ! defined $pcnt ) { $pcnt = "Not collect" };

    my $resultpoint = { "count" => $pcnt }; 

   $self->res->headers->header("Access-Control-Allow-Origin" => 'https://www.backbone.site' );
   $self->render(json => $resultpoint);

   undef $uid;
#   undef $executelist;
#   undef @execute;
   undef $pcnt;
   undef $resultpoint;

}


sub supervise {
   my $self = shift;

   $self->render(msg_w => '');
}

sub overviewWW {
    my $self = shift;
    # TOP表示用にsuperviseのコピー

    $self->render(msg_w => '');
}

# supervise websocket
sub echo3 {
    my $self = shift;

       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx->connection;
    #   $clients->{$id} = $self->tx;

    my $userid = $self->stash('uid');

    my $wwdb = $self->app->mongoclient->get_database('WalkWorld');
    my $timelinecoll = $wwdb->get_collection('MemberTimeLine');

    my $wwdblog = $self->app->mongoclient->get_database('WalkWorldLOG');
    my $timelinelog = $wwdblog->get_collection('MemberTimeLinelog');

    my $chatname = "WALKCHAT";
    my @chatArray = ( $chatname );

  # WalkChat用
#    my $holldb = $self->app->mongoclient->get_database('holl_tl');
#    my $walkchatcoll = $holldb->get_collection('walkchat');
#    my $walkchatdrpmsg = $holldb->get_collection('walkchat_dropmsg');

    # chat loop

    # 接続時点での末尾を返す  chatではmongodbを使わなくなったのでコメントした
#    my $last = $walkchatcoll->find_one();
#    my $lid = $last->{_id};
#       $lid = 0 if ( !defined $lid);


    # mongo3.2用 チャットの文を6000ｍ以内に限る
#    my $walkchat_cursole = $walkchatcoll->find()->sort({_id => -1});
          
#    my @allcursole = $walkchat_cursole->all;
#       @allcursole = reverse(@allcursole); 

#    foreach my $line (@allcursole){
#          $clients->{$id}->send({json => $line });
#        }


    $self->on(message => sub {
        my ($self,$msg) = @_;

           my $jsonobj = from_json($msg);

           if ( defined($jsonobj->{username})) {

# usernamから360件(1hour)ほど検索して返す "upointlist"
              my $unamegetlist = $timelinelog->find({ "name" => $jsonobj->{username} })->sort({ "_id" => -1 })->limit(360);
              my @unamepointlist = $unamegetlist->all;
              my $listhash = { 'upointlist' => \@unamepointlist };
              my $jsontext = to_json($listhash);
                 $self->tx->send($jsontext);
                 $self->app->log->debug("DEBUG: user_point_list: $jsontext");

                 undef $unamegetlist;
                 undef @unamepointlist;
                 undef $listhash;
                 undef $jsontext;
              }

           my $geo_points_cursole = $timelinecoll->query({ "geometry" => { 
                                           '$nearSphere' => [ $jsonobj->{loc}->{lng} , $jsonobj->{loc}->{lat} ], 
                                        #   '$maxDistance' => 1 
                                         }});

            #データから最新ポイントだけを抽出するには、降順で時刻をsortして、
            my @all_points = $geo_points_cursole->all;
            my @all_points_sort = sort { $b->{time} <=> $a->{time} } @all_points;

            # push時にgrepで重複を弾く
            my @pointlist = ();
               foreach my $po ( @all_points_sort){
                   push(@pointlist,$po) unless grep { $_->{userid} =~ /^\Q$po->{userid}\E$/ } @pointlist;
                   }
            undef @all_points;
            undef @all_points_sort;

                ####   my @pointlist = $geo_points_cursole->all;
                   my $listhash = { 'pointlist' => \@pointlist };
                   my $jsontext = to_json($listhash); 
                      $self->tx->send($jsontext);
                      $self->app->log->debug("DEBUG: geo_points: $jsontext");

                   undef @pointlist;
                   undef $listhash;
                   undef $jsontext;
                   undef $geo_points_cursole;
                   undef $jsonobj;

    });

  $self->on(finish => sub {
        my ($self,$msg) = @_;
        $self->app->log->debug("DEBUG: On finish!!");
    });

#redis receve
     $self->redis->on(message => sub {
                  my ($redis,$mess,$channel) = @_;
                      $self->app->log->debug("DEBUG: on redis channel:($userid) $mess");

                      if ( $channel ne $chatname ) { return; } # filter channel

                      my $messobj = from_json($mess);

                        if ( defined $clients->{$id} ){
                           $clients->{$id}->send($mess);
                           $self->app->log->debug("DEBUG: send websocket:($userid) $mess");
                        }

                       return;
                  });  # redis on message

     $self->redis->subscribe(\@chatArray, sub {
                   my ($redis, $err) = @_;
                 #     return $redis->publish( $chatname => $err) if $err;
                      $self->app->log->debug("DEBUG: $userid redis subscribe");
                      return $redis->incr(@chatArray);
                   });
     $self->redis->expire( \@chatArray => 3600 );

     $self->redis->on(error => sub {
                   my ($redis,$err) = @_;
                      $self->app->log->info("DEBUG: $userid redis error: $err");
                   });

  my $stream = Mojo::IOLoop->stream($self->tx->connection);
        $stream->timeout(0);  # no timeout!
        $self->inactivity_timeout(10000);

}


1;
