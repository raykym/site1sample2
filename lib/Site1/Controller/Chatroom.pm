package Site1::Controller::Chatroom;
use Mojo::Base 'Mojolicious::Controller';
use utf8;
use DateTime;
use MIME::Base64::URLSafe;
use Data::Dumper;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use MongoDB;
use Encode;

#use Mojo::Pg;
use Mojo::Pg::PubSub;

# 独自パスを指定して自前モジュールを利用
use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1';
use Inputchk;

# 300秒待機設定秒じゃないのか？ミリ秒？どんどん短くなる。。。
#$ENV{MOJO_INACTIVITY_TIMEOUT} = 3000;

sub view {
    my $self = shift;

    $self->render(msg_w => 'morboサーバの場合のみ動作します。　表示のみで履歴は残りません。');
}

my $clients = {};

# websocket
sub echo {
    my $self = shift;
  
    my $username = $self->stash('username');
    my $icon = $self->stash('icon'); #encodeされたままのはず。
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
       my $id = sprintf "%s", $self->tx;
       $clients->{$id} = $self->tx;

  # connect message write
      for (keys %$clients) {
        $clients->{$_}->send({json => {
                                 icon_url => $icon_url,
                                 username => $username,
                                 hms => 'XX:XX:XX',
                                 text => 'Connect'
                              }});
       }


       # 5分つなぎっぱなし。デフォルトは数秒で切れる
       #Mojo::IOLoop->stream($self->tx->connection)->timeout(300);
       #$self->inactivity_timeout(300);

       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

                  for (keys %$clients) {
                      $clients->{$_}->send({json => {
                              icon_url => $icon_url,
                              username => $username,
                              hms => $dt->hms,
                              text => $msg,
                           }}); 
                      }
                  }
         );
             
         $self->on(finish => sub{
                 $self->app->log->debug('Client disconnected');
                 delete $clients->{$id};

              # Disconnect message write
                for (keys %$clients) {
                    $clients->{$_}->send({json => {
                               icon_url => $icon_url,
                               username => $username,
                               hms => 'XX:XX:XX',
                               text => 'Has gone.....'
                            }});
                  }
             }
         );
}

sub viewdb {
    my $self = shift;

    $self->render(msg_w => '1時間でコメントは消えていきます。。。');
}

# websocket mongodb経由タイプ
sub echodb {
    my $self = shift;

# mongoDBの用意
  #  my $mongoclient = MongoDB::MongoClient->new(host => 'localhost', port => '27017');
    my $holldb = $self->app->mongoclient->get_database('holl_tl');
    my $hollcoll = $holldb->get_collection('holl');
    my $holldrpmsg = $holldb->get_collection('holl_dropmsg');
  
    my $username = $self->stash('username');
    my $icon = $self->stash('icon'); #encodeされたままのはず。
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);


       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
       my $id = sprintf "%s", $self->tx;
       $clients->{$id} = $self->tx;

    #日付設定
 #   my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

    # TTLレコードを追加する。
 #   my $ttl = DateTime->now();

       # holldbへの書き込み $iconはurlsafeの状態で記録
 #      $hollcoll->insert({ icon_url => $icon_url, 
 #                          username => $username, 
 #                          hms => $dt->hms,
 #                          text => 'Connect',
 #                          ttl => $ttl
 #                        });

       # 接続時点でのすべてを返す
       my $last = $hollcoll->find_one();
       my $lid = $last->{_id};

       #holldbから差分読み出し
       my $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
       my @allcursol = $datacursol->all;

       foreach my $line (@allcursol){
             $self->tx->send({json => $line });
       }

       # 初期値で値が取れない場合の対応
       if ($#allcursol > 0){
           $lid = $allcursol[$#allcursol]->{_id};  # 最後のidを更新
           }

       # デフォルトは数秒で切れる 300秒で切れる
       # 環境変数 MOJO_INECTIVITY_TIMEOUTを設定では出来なかった。。。
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
       #   $stream->timeout(10);
          $self->inactivity_timeout(30000);

 #      Mojo::IOLoop->recurring(
 #         60 => sub {
 #            my $char = "dummey";
 #            my $bytes = $clients->{$id}->build_message($char);
 #            $clients->{$id}->send( {binary => $bytes}) if ($clients->{$id}->is_websocket);
 #         });

# on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  $msg = encode_utf8($msg);

                  # NGワードチェック
                  my $chkmsg = Inputchk->new($msg);
                     $chkmsg->ngword;
                  my $res_chkmsg = $chkmsg->result;
                  my $chkmsg_string = decode_utf8($chkmsg->{string}); 
              #    $self->app->log->debug("DEBUG: res_chkmsg: $res_chkmsg | $chkmsg_string ");
                  undef $chkmsg;

                  # drop処理
                  if ($res_chkmsg > 0 ) {

                      my $drpMSG = $msg;
                         $drpMSG = decode_utf8($drpMSG);

                      #日付設定 重複記述あり
                      my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                      # TTLレコードを追加する。
                      my $ttl = DateTime->now();

                      # holl_dropmsgへの書き込み dropメッセージのバックアップ
                      $holldrpmsg->insert({ icon_url => $icon_url, 
                                           username => $username, 
                                           hms => $dt->hms,
                                           text => $drpMSG, 
                                           ttl => $ttl,
                                         });

                      } # if res_chkmsg

                  if ($res_chkmsg > 0 ) { $msg = 'キーワードチェックで除外されました。'; }
   
                  # DROPメッセージで無い場合の処理
                  #日付設定 重複記述あり
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  # TTLレコードを追加する。
                  my $ttl = DateTime->now();

                     $msg = decode_utf8($msg);

                   # holldbへの書き込み
                   $hollcoll->insert({ icon_url => $icon_url, 
                                       username => $username, 
                                       hms => $dt->hms,
                                       text => $msg, 
                                       ttl => $ttl,
                                     });
                   # holldbから差分の読み出し
                   $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
                   @allcursol = $datacursol->all;
                   foreach my $line (@allcursol){
                               $self->tx->send({json => $line });
                   }
                   $lid = $allcursol[$#allcursol]->{_id};  # 最後のidを更新
                  }
         );

       #MongoDBからリストを受けて、送信
       my $loopid = Mojo::IOLoop->recurring(
          1 => sub {
              my $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
              my @alldata = $datacursol->all;
              @alldata = reverse(@alldata);  #検索結果をリバースしてDESC同等に
              if ( @alldata ){
                  $clients->{$id}->send({json => @alldata });
                  $lid = $alldata[$#alldata]->{_id};
                  }
              undef @alldata;
             });

# on finish・・・・・・・
         $self->on(finish => sub{
                 $self->app->log->debug('Client disconnected');
                 delete $clients->{$id};

               #日付設定 重複記述あり
          #      my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
               # TTLレコードを追加する。
          #      my $ttl = DateTime->now();

               #holldbへの書き込み
          #         $hollcoll->insert({ icon_url => $icon_url, 
          #                             username => $username, 
          #                             hms => $dt->hms,
          #                             text => 'Has gone...',
          #                             ttl => $ttl 
          #                           });
               #更新チェックのループ停止
                if ( ! defined $clients->{$id}){ Mojo::IOLoop->remove($loopid); }

                $self->tx->finish;
             }
         );

         # mongoDBをポーリングして表示する 失敗　mongojson.plが受け口
         # 書き込みしないと更新されない問題あり。
#         Mojo::IOLoop->timer(1 => sub {
#             my $loop = shift;
#
#             $self->ua->websocket('ws://192.168.0.8:3801' => sub {
#                 my ($ua,$tx) = @_;
#
#                     $tx->on(json => sub{
#                         my ($tx,$dbline) = @_;
#                         $self->tx->send({json => $dbline});
#                  });
#              my $dbline = $self->ua->tx->res->json;
#              if ($dbline != '' ){
#                $self->tx->send({json => $dbline});
#                }
#               });
#         });
#         Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

}

sub viewpg {
    my $self = shift;

    $self->render(msg_w => 'pg経由すぐにリアクションが戻る');
}

sub echopg {
    my $self = shift;

#echodbと同じだが、pubsub通信を利用したPushを利用する。
# mongodbが64bitならTTL indexで時間が来たら消すことが出来るが、環境的に無理。

    # postgresqlの準備 pgdbhはSite1.pmで全体定義した。
 ###   my $pg = Mojo::Pg->new('postgresql://sitedata:sitedatapass@192.168.0.8/sitedata');
    my $pg = $self->app->pgdbh;
    my $pubsub = Mojo::Pg::PubSub->new(pg => $pg);

    # mongoDBの用意
    my $mongoclient = MongoDB::MongoClient->new(host => 'localhost', port => '27017');
    my $holldb = $mongoclient->get_database('holl_tl');
    my $hollcoll = $holldb->get_collection('holl');
  
    #param 認証をパスしているので、username,icon_url,emailがstashされている。
    my $username = $self->stash('username');
    my $icon = $self->stash('icon'); #encodeされたままのはず。
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);


       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
       my $id = sprintf "%s", $self->tx;
       $clients->{$id} = $self->tx;

    # connect message write
    #日付設定
    my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

       # holldbへの書き込み $iconはurlsafeの状態で記録
       $hollcoll->insert({ icon_url => $icon_url, 
                           username => $username, 
                           hms => $dt->hms,
                           text => 'Connect'
                         });
       # 書き込みを通知
       $pubsub->notify( messagetl => 'send message');

       # 接続時点でのすべてを返す
    my $last = $hollcoll->find_one();
    my $lid = $last->{_id};
       #holldbから差分読み出し
    my $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
    my @allcursol = $datacursol->all;
       foreach my $line (@allcursol){
             $self->tx->send({json => $line });
       }
       $lid = $allcursol[$#allcursol]->{_id};  # 最後のidを更新

       # 5分つなぎっぱなし。デフォルトは数秒で切れる でも1分30秒で切れる
       # 環境変数 MOJO_INECTIVITY_TIMEOUTを設定では出来なかった。。。
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
          $stream->timeout(3600);
          $self->inactivity_timeout(3000);
       #つなぎっぱなしの為のループ
       Mojo::IOLoop->recurring(
          60 => sub {
             my $char = "dummey";
             my $bytes = $clients->{$id}->build_message($char);
             $clients->{$id}->send( {binary => $bytes}) if ($clients->{$id}->is_websocket);
          });

       #pubsubから受信設定 messagetlをキーとして利用
    my $cb = $pubsub->listen(messagetl => sub {
            my ($pubsub, $payload) = @_;
            #$payloadは通知のみで意味を利用しない
            # holldbから差分の読み出し
               $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
               @allcursol = $datacursol->all;
            my @alldata = reverse(@allcursol);  #検索結果をリバースしてDESC同等に
               foreach my $line (@alldata){
                           $self->tx->send({json => $line });
                   }
               $lid = $allcursol[$#allcursol]->{_id};  # 最後のidを更新
        });

# on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  #日付設定 重複記述あり
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

                   # holldbへの書き込み
                   $hollcoll->insert({ icon_url => $icon_url, 
                                       username => $username, 
                                       hms => $dt->hms,
                                       text => $msg, 
                                     });
                   # 書き込みを通知
                   $pubsub->notify( messagetl => 'send message');
                  }
         );

       #MongoDBからリストを受けて、送信 pubsubで代用の為コメントアウト
 #      my $loopid = Mojo::IOLoop->recurring(
 #         3 => sub {
 #             my $datacursol = $hollcoll->find({_id => { '$gt' => $lid }});
 #             my @alldata = $datacursol->all;
 #             @alldata = reverse(@alldata);  #検索結果をリバースしてDESC同等に
 #             if ( @alldata ){
 #                 $clients->{$id}->send({json => @alldata });
 #                 $lid = $alldata[$#alldata]->{_id};
 #                 }
 #             undef @alldata;
 #            });

# on finish・・・・・・・
         $self->on(finish => sub{
                 $self->app->log->debug('Client disconnected');
                 delete $clients->{$id};

               #日付設定 重複記述あり
                my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

               #holldbへの書き込み
                   $hollcoll->insert({ icon_url => $icon_url, 
                                       username => $username, 
                                       hms => $dt->hms,
                                       text => 'Has gone...' 
                                     });
               # 書き込みを通知
               $pubsub->notify( messagetl => 'send message');

               #更新チェックのループ停止
         ###       if ( ! defined $clients->{$id}){ Mojo::IOLoop->remove($loopid); }
               # pubsubリスナーの停止
                if ( ! defined $clients->{$id}){ $pubsub->unlisten('messagetl' => $cb); }
             }
         );
}

sub webrtcx4 {
    my $self = shift;

    $self->render();
}

sub signaling {
    my $self = shift;

    # webRTC用にシグナルサーバとしてJSONを受けてそのままJSONを届ける
    # セッションテーブルをredisのsignal_tblに作成。websocket切断で削除される。
    # 呼び出し元のURLに引数?r=ルーム名をつけるとテーブルを作成して、そのテーブルにsubscribeする。
    # メッセージ内にsendtoが含まれる場合、sessionidが指定されて、個別送信とする。
    # Pgからredisへの書き換え実施

    #cookieからsid取得
    my $sid = $self->cookie('site1');
    ###$self->app->log->debug("DEBUG: SID: $sid");
    my $username = $self->stash('username');
    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

    # getパラメータでroom指定を行う。 ->roomはリスト名として利用 
    my $room = $self->param('r');
    if ( ! defined $room ) { $room = 'signal_tbl'; }
    $self->app->log->debug("DEBUG: room: $room");

    #websocket 確認
    $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx->connection;
    $clients->{$id} = $self->tx;
    # sidをpubsubの受信に利用する
    my $connid = $sid;

    my $recvlist = [ $sid , $room ];

    # postgresqlの準備 Site1.pmに共通設定追加
 #####       my $pg = Mojo::Pg->new('postgresql://sitedata:sitedatapass@192.168.0.8/sitedata');
#        my $pg = $self->app->pgdbh;
#        my $pubsub = Mojo::Pg::PubSub->new(pg => $pg);
 # 目的を見失った行       my $subscall = Mojo::Pg::PubSub->new(pg => $pg);
#
#           $pg->db->query("CREATE TABLE IF NOT EXISTS $room (connid text, sessionid text,username varchar(255),icon_url char(255))");
#           $self->app->log->debug("INFO: CREATE TABLE $room");
#
#    my @values = ($connid, $sid, $username, $icon_url);
#       $self->app->log->debug("INFO: @values");
#
#    #リスナー登録　pgのsignal_tblへsidを登録 $roomがテーブル名
#        $pg->db->query("INSERT INTO $room values(?,?,?,?)",@values);
# 上記はredis移行の為、不要になった

     # room LISTへの登録
     my $entry = { connid => $sid, username => $username, icon_url => $icon_url };

     my $entry_json = to_json($entry);

      #重複を避ける為に一度削除、空処理も有り
        $self->redis->lrem($room,'1',$entry_json);

      # redis LISTにエントリー
        $self->redis->lpush($room => $entry_json);


    # 接続維持設定 WebRTCではICE交換が終わればすぐにwebsocketは閉じたい。
    # はずが、方針変更、rooentrylistをマージしてクローズしない方向で。。。
    # 接続タイミングを合わせるまでは接続を続ける必要がある。
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
          $stream->timeout(60);
    #      $self->inactivity_timeout(3000);
       #つなぎっぱなしの為のループ  ・・・ つながれば切れてOKなので
       Mojo::IOLoop->recurring(
          50 => sub {
             my $char = "dummey";
             my $bytes = $clients->{$id}->build_message($char);
             $clients->{$id}->send( {binary => $bytes}) if ($clients->{$id}->is_websocket);
          });

#    #pubsubから受信設定 
#        my $cb = $pubsub->listen($connid => sub {
#            my ($pubsub, $payload) = @_;
#
#            #JSONキャラ->perl形式
#            my $jsonobj = from_json($payload);
#
#      ###       my $connid = $self->tx->connection;
#                 $self->app->log->debug("DEBUG: go session: $connid");
#             #    $self->app->log->debug("DEBUG: payload: $payload");
#
#                 #websocketは自分にだけ送信する
#                 $clients->{$id}->send({ json => $jsonobj});
#          });
# 上記もredisに置き換え

         #redis receve
         $self->redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

                    $self->app->log->debug("DEBUG: on channel: {$channel} ($username) $mess");

                    my $messobj = from_json($mess);

                    #websocket送信 perl形式->jsonへ変換されている。
                    $clients->{$id}->send({json => $messobj});

                    return;
                 });  # redis on message

        $self->redis->subscribe($recvlist, sub {
                 my ($redis, $err) = @_;
                       #     return $redis->publish('errmsg' => $err) if $err;
                       return $redis->incr($recvlist);
                 });

    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;
                   # $msgはJSONキャラを想定
                   my $jsonobj = from_json($msg);
          ###         my $connid = $self->tx->connection;
                   $self->app->log->debug("DEBUG: on session: $connid");
                   $self->app->log->debug("DEBUG: msg: $msg");

           # fromとしてconnidを付加
                 $jsonobj->{from} = $connid;
                 $msg = to_json($jsonobj);
                 $self->app->log->debug("DEBUG: msgaddid: $msg");

              if ($jsonobj->{sendto}){
                 #個別送信が含まれる場合、単独送信
                 $self->redis->publish( $jsonobj->{sendto} , $msg);

              } else {
              # 個別では無い場合！！！
              # 書き込みを通知 signal_tblにsubscriberされたidのみ通知
              # 自分は除外する。
          #    my $subs_member = $pg->db->query("SELECT * FROM $room");
          #    while ( my $subs_id = $subs_member->hash){
          #         $pubsub->notify( $subs_id->{connid} => $msg) unless ($connid eq $subs_id->{connid});
          #         $self->app->log->debug("DEBUG: subs_id: $subs_id->{connid}") unless ($connid eq $subs_id->{connid});
          #    }
          # 上記はredisに置き換え
               # チャットルーム全体に送信
               $self->redis->publish( $room , $msg);
               $self->app->log->debug("DEBUG: publish: $username :  $room : $msg");

             } # else
          });

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $msg) = @_;

               $self->app->log->debug('Client disconnected');
               delete $clients->{$id};

               # pubsubリスナーの停止
            #   if ( ! defined $clients->{$id}){ $pubsub->unlisten($connid => $cb); }
            #   # リスナー登録の解除 削除はconnidではなくそのままsidで・・・
            #   $pg->db->query("DELETE FROM $room WHERE sessionid = ?" , $sid);
            #   $self->app->log->info("INFO: DEL Entry $room $sid");
            #上記はredisに置き換え

                # pubsubのunsubscribe
                $self->redis->unsubscribe($recvlist, sub {
                       my ($redis, $err) = @_;

                          return;
                       });
                # LIST登録の解除
                $self->redis->lrem($room,'1', $entry_json);
                $self->app->log->debug("DEBUG: finish: lrem: $entry_json");
                $self->app->log->debug('Client disconnected');
                delete $clients->{$id};

        });  # on finish

}

sub webrtcx2 {
    my $self = shift;

    $self->render(msg_w => 'StartVideoを押して画面が来る状態で待機してください。その後、入室確認してからconnectボタンをどちらかが押してください');
}

sub roomentrycheck {
    my $self = shift;
    # websocketで入室状況を送信する。r=XXXXXで受け取ったルーム名のエントリー数をJSONで返す。

    #websocket 確認
    $self->app->log->debug(sprintf 'room Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx->connection;
  ####  $clients->{$id} = $self->tx;

   ### 更新のイベント処理をタイマーで実行
   # ブラウザからイベントが届くと切断する。
    my $room = $self->param('r');
    if ( ! defined $room) { $room = 'signal_tbl'};

 #   my $pg = $self->app->pgdbh;
 # redis移行で不要に

    my $stream = Mojo::IOLoop->stream($self->tx->connection);
       $stream->timeout(60);
    #   $self->inactivity_timeout(3000);

#    my $result;
    my $roomcount;
    my $loopid = Mojo::IOLoop->recurring( 10 => sub {
            #    $result = $pg->db->query("SELECT count(*) FROM $room");
            #    $roomcount = $result->hash->{count};
                 $roomcount = $self->redis->llen($room);
                my $jsontext = to_json( {count => $roomcount});
                $self->app->log->debug("send jsontext: $jsontext");
                $self->tx->send($jsontext);
                });

       $self->on(message => sub {
                  my ($self, $msg) = @_;
                #メッセージが届いたら切断する。
                  $self->app->log->debug("ROOMENTRY: $msg");
                  $self->tx->finish;
        });

       $self->on(finish => sub{
          Mojo::IOLoop->remove($loopid);
          $self->app->log->debug('roomcount stop...');
       });
}

sub voicechat {
    my $self = shift;

    $self->render(msg_w => '参加メンバーがそろったら、それぞれconnectを押してください。アイコン横のカウンターが動いていれば通じているはずです。切断時はブラウザを完全に閉じないとネットワークが切れていない場合が有ります。スマホでは通知にマイクマークが無いことを確認してください。!!!後から接続した場合、表示が出ません公開チャットであることを忘れずに!!!');
}

sub roomentrylist {
    my $self = shift;
    # websocketで入室状況を送信する。r=XXXXXで受け取ったルーム名のエントリーメンバーをJSONで返す。
    #voicechatのメンバー表示用 connidとsessionidを返すのでエレメントとして利用

    my $sid = $self->cookie('site1');
    my $username = $self->stash('username');

    #websocket 確認
    $self->app->log->debug(sprintf 'room Client connected: %s', $self->tx);
    my $id = sprintf "%s", $self->tx->connection;

   ### 更新のイベント処理をタイマーで実行
   # ブラウザからイベントが届くと切断する。
    my $room = $self->param('r');
    if ( ! defined $room) { $room = 'signal_tbl'};

    my $recvlist = [ "roomentry" ];


    #DB設定
####    my $pg = $self->app->pgdbh;
#    my $pg = $self->app->pg;
#    my $pubsub = Mojo::Pg::PubSub->new(pg => $pg);
#
#    my $config = $self->app->plugin('Config');
#    my $sth_sesi_email = $self->app->dbconn->dbh->prepare("$config->{sql_sesi_email}");
#    my $sth_getchatmemb = $self->app->dbconn->dbh->prepare("$config->{sql_getchatmemb}");
# redis移行で上記は不要に

    my $stream = Mojo::IOLoop->stream($self->tx->connection);
       $stream->timeout(60);
#       $self->inactivity_timeout(3000);

    #pubsubから受信設定 
#        my $cb = $pubsub->listen('roomentry' => sub {
#            my ($pubsub, $payload) = @_;
#
#                  $self->app->log->debug("ROOMENTRY: $payload");
#
#                  # 通知が届いたら切断する
#                  $self->tx->finish;
#           });
# redis移行でコメント

         #redis receve
         $self->redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

                    $self->app->log->debug("DEBUG: on channel: {$channel} ($username) $mess");

                   # 通知が届いたら切断する
                    $self->tx->finish;

                    return;
                 });  # redis on message

        $self->redis->subscribe($recvlist, sub {
                 my ($redis, $err) = @_;
                       #     return $redis->publish('errmsg' => $err) if $err;
                       return $redis->incr($room);
                 });


 #   my $result;
    my $memberlist;

    my $loopid = Mojo::IOLoop->recurring( 
             1 => sub {
 #               $result = $pg->db->query("SELECT connid,sessionid,username,icon_url FROM $room");
 #               # $result  $_->{sessionid}の配列の想定
 #               ####my $rownum = $result->rows;  # 何故か1回で０に成る。。
 #         #      my $resultcount = $pg->db->query("SELECT count(*) FROM $room");
 #         #      my $rownum = $resultcount->hash->{count};
 #         #      $self->app->log->debug("room rows: $rownum");
 #
 #         # 送信元id 付加
 #                push @memberlist, to_json({from => $sid});
 #               while (my $next = $result->hash){
 #                   push @memberlist, to_json({sessionid => $next->{sessionid}, username => $next->{username}, icon_url => $next->{icon_url}, connid => $next->{connid}});
 #         #         $self->app->log->debug("memberlist: $next->{sessionid} $next->{username} $next->{icon}");
 #               } #while

              $memberlist = $self->redis->lrange($room,'0','-1');

              #以前はfromを付けていたが、javascriptで無視しているので、あえて書かない

              # 配列で１ページ分を送る。
                my @memberlist_json = to_json([@$memberlist]);
                $self->app->log->debug("send jsontext: @memberlist_json");
                $self->tx->send(@memberlist_json);

                @memberlist_json = (); #空にする
          #      $result = {}; #エラー消える。 何故？
                });

       $self->on(message => sub {
                  my ($self, $msg) = @_;
                #メッセージが届いたら切断する。 callした人だけ、callするまで動く
                  $self->app->log->debug("ROOMENTRY: $msg");
                  $self->tx->finish;
                # その他のメンバーにも通知する
#                 $pubsub->notify( 'roomentry' => $msg);
                  $self->redis->publish( $recvlist , $msg );
        });

       $self->on(finish => sub{
          Mojo::IOLoop->remove($loopid);
          $self->app->log->debug('roomentrylist stop...');

          # リスナー登録の解除
            $self->redis->unsubscribe($recvlist, sub {
                     my ($redis, $err) = @_;
                        $self->app->log->debug("DEBUG: unsbscribe $username ");
                        return;
                   }); # redis
       }); # finish
}

sub videochat {
    my $self = shift;

    $self->render(msg_w => '参加メンバーが揃ったらconnectを押してください。切断時はブラウザを完全に閉じないとネットワークが切れていない場合が有ります。スマホでは通知にマイクマークが無いことを確認してください。');
}

sub voicechat2 {
    my $self = shift;
    # webroom.pmへの対応用ページ

    $self->render(msg_w => '');
}

sub videochat2 {
    my $self = shift;
    # webroom.pmへの対応用ページ

    $self->render(msg_w => '');
}

sub chatopen {
    my $self = shift;

    $self->render(msg_w => '履歴は残りません。切断はブラウザを完全に閉じて下さい。左上のメニューからボイスチャット、ビデオチャットに展開出来ます。');
}

sub echopubsub {
    my $self = shift;
 # chatopen用 

    # postgresqlの準備 pgdbhはSite1.pmで全体定義した。
    my $pg = $self->app->pgdbh;
    my $pubsub = Mojo::Pg::PubSub->new(pg => $pg);

    #param 認証をパスしているので、username,icon_url,emailがstashされている。
    my $username = $self->stash('username');
    my $icon = $self->stash('icon'); #encodeされたままのはず。
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx);
       my $id = sprintf "%s", $self->tx;
       $clients->{$id} = $self->tx;

    # 接続時間延長 最大90sec
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
          $stream->timeout(40);


    # connect message write
    #日付設定
    my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

       my $resmsg = { icon_url => $icon_url, 
                           username => $username, 
                           hms => $dt->hms,
                           text => 'Connect'
                         };
           # $resmsgがperl形式で、jsonで送信
          $clients->{$id}->send({ json => $resmsg});

       # 書き込みを通知
       $resmsg = to_json($resmsg); #JSONにしてから 
       $pubsub->notify('openchat' => $resmsg);

    #pubsubから受信設定 共通なので基本ブロードキャスト
        my $cb = $pubsub->listen(openchat => sub {
            my ($pubsub, $payload) = @_;
                $self->app->log->debug("on Message!! pubsub.");
                # $payloadはJSON形式->perl形式        
                $payload = from_json($payload);

                 #websocketは自分にだけ送信する
                 $self->tx->send({ json => $payload});
          });

    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  # dummyイベントはパスする
                  my $chkmsg = from_json($msg);
                  if ($chkmsg->{dummy}){
                      $self->app->log->debug("Receive Dummy: $chkmsg->{dummy}");                      return; 
                      }

                  #日付設定 重複記述あり
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

                  my $resmsg = { icon_url => $icon_url, 
                                       username => $username, 
                                       hms => $dt->hms,
                                       text => $chkmsg->{text}, 
                                     };
                     $resmsg = to_json($resmsg);
                   $self->app->log->debug("resmsg: $resmsg");
                   # 書き込みを通知 念の為後置のunless
                   $pubsub->notify('openchat' => $resmsg ) unless ($chkmsg->{dummy});
                  });

    # on finish・・・・・・・
         $self->on(finish => sub{
                 $self->app->log->debug('Client disconnected');
                 delete $clients->{$id};

               #日付設定 重複記述あり
                my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

                my $resmsg = { icon_url => $icon_url, 
                                       username => $username, 
                                       hms => $dt->hms,
                                       text => 'Has gone...' 
                                     };
                   $resmsg = to_json($resmsg);
               # 書き込みを通知
               $pubsub->notify('openchat' => $resmsg);

               # pubsubリスナーの停止
                if ( ! defined $clients->{$id}){ $pubsub->unlisten( 'openchat' => $cb); }
              });

}

sub voicechatspot {
    my $self = shift;
    # webroom.pmへの対応用ページ
    # ユーザが出入り自由な形式を目指す

    $self->render(msg_w => '１．共通のroom名を入力して待機して下さい。(エンター押してね）２．メンバーがそろったらStandbyを押して下さい。３．全員がStandbyしたら、connectボタンを押して通話状態を確認して下さい。');
}

sub videochat2pc {
    my $self = shift;
    # webroom.pmへの対応用ページ PC用draggable対応

    $self->render(msg_w => '１．共通のroom名を入力して待機して下さい。(エンター押してね）２．メンバーがそろったらStandbyを押して下さい。３．全員がStandbyしたら、connectボタンを押して通話状態を確認して下さい。');
}

1;
