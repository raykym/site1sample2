package Site1::Controller::Webroom;
use Mojo::Base 'Mojolicious::Controller';

use utf8;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
#use Mojo::Pg::PubSub;
use Mojo::Util qw(dumper encode decode url_escape url_unescape md5_sum sha1_sum);
use Mojo::Redis2;

use Data::Dumper;

#my $tablename;
my $clients = {};

sub signaling {
  my $self = shift;

     #Chatroom.pmのsignaringとroomentrylistをマージした処理を作る。
     # connectの同期を取るためにreadyフラグを用意している。
     # さらにチャットも機能させる
     # open対応にスイッチを設定r=open

    #cookieからsid取得 認証を経由している前提
    my $sid = $self->cookie('site1');
       $self->app->log->debug("DEBUG: SID: $sid");
    my $uid = $self->stash("uid");
    my $username = $self->stash('username');
    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "/imgcomm?oid=$icon" if (! defined $icon_url);

    #websocket 確認
       $self->app->log->debug(sprintf 'Client connected: %s', $self->tx->connection);
       my $id = sprintf "%s", $self->tx;
          $self->app->log->debug("socket id: $id");
      $clients->{$id} = $self->tx;

    # WebSocket接続維持設定
       my $stream = Mojo::IOLoop->stream($self->tx->connection);
        #  $stream->timeout(90);
          $self->inactivity_timeout(500);

    # エントリーメンバー一覧を返す処理 global変数として残す
    my $memberlist;
    my $chatroomname;
    my $entry_json;

#受信用リスト
my $recvlist;
   $recvlist = [ $sid ];

    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;
                   # $msgはJSONキャラを想定
                   my $jsonobj = from_json($msg);
                   $self->app->log->debug("DEBUG: on session: $sid");
                   $self->app->log->debug("DEBUG: msg: $msg");

           if ( $jsonobj->{dummy} ) {
                   # dummy pass
                   return;
              }

           # fromとしてsidを付加
               $jsonobj->{from} = $sid;
               $msg = to_json($jsonobj);
               $self->app->log->debug("DEBUG: msgaddid: $msg");

           # room作成 {entry:room名}受信
           if ( $jsonobj->{entry} ) {

                      # 受信リストの追加
                      push(@$recvlist,$jsonobj->{entry});
                      my $debugjson = to_json($recvlist);
                      $self->app->log->debug("DEBUG: recvlist: $debugjson");

                      # 0 is false
                   my $entry = { connid => $sid, username => $username, icon_url => $icon_url, ready => 0 };

                      $entry_json = to_json($entry);

                   #重複を避ける為に一度削除、空処理も有り
                   $self->redis->lrem($chatroomname,'1',$entry_json);

                   # redis LISTにエントリー
                   $self->redis->lpush($jsonobj->{entry} => $entry_json);

                   $chatroomname = $jsonobj->{entry};

                   $self->app->log->debug("DEBUG: $username entry finish.");             


           #        #redis receve
           #        $self->redis->on(message => sub {
           #               my ($redis,$mess,$channel) = @_;

           #               if ( $channel == 'WALKCHAT' ) { return; } # WALKCHATは除外する
           #                   $self->app->log->debug("DEBUG: on channel: {$channel} ($username) $mess");
                     
           #                   my $messobj = from_json($mess);

           #                   #websocket送信 perl形式->jsonへ変換されている。
           #                   $clients->{$id}->send({json => $messobj});

           #                   return;
           #                });  # redis on message

                  $self->redis->subscribe($recvlist, sub {
                           my ($redis, $err) = @_;
                                 #     return $redis->publish('errmsg' => $err) if $err;
                                 return $redis->incr($recvlist);
                           });

                    return;
                  } # $jsonobj->{entry}

              # setReadyを受信  connidを受信するが、利用しなくなった。Redisの為
              if ($jsonobj->{setReady}) {
                  $self->app->log->debug("setreadyconn: $jsonobj->{setReady}");
                  # LISTから削除
                  $self->redis->lrem($chatroomname,'1',$entry_json);
                  # LIST更新  1 is true
                   my $entry = { connid => $sid, username => $username, icon_url => $icon_url, ready => 1 };
                      $entry_json = to_json($entry);
                      $self->redis->lpush($chatroomname => $entry_json);
                      # 結果はgetlistが呼ばれるのでこれだけ

                  $self->app->log->debug("DEBUG: setReady on $username");
                 return;

              } # setReady

              #gpslocationを受信  今は使わないと思う
              if ($jsonobj->{gpslocation}) {
                    
                  return;
              } # gpslocation


              # sendtoが含まれる場合
                if ($jsonobj->{sendto}){
                   #個別送信が含まれる場合、単独送信

                   my $jsontxt = to_json($jsonobj);
                   
                   $self->redis->publish( $jsonobj->{sendto} , $jsontxt);
                   $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");
  
                   return;  # スルーすると全体通信になってしまう。
                   } 


        #エントリーメンバーを送信コマンドの受信 自分宛て
             if ($jsonobj->{getlist}){

                 $memberlist = $self->redis->lrange($chatroomname,'0','-1');

        # 配列で１ページ分を送る。
             my $memberlist_json = to_json( { from => $sid, type => "reslist", reslist => $memberlist } );   
 
                 $self->app->log->debug("DEBUG: memberlist: $memberlist_json ");

                 $clients->{$id}->send($memberlist_json);

                 return;
                } 

        # roomからエントリー削除
            if ($jsonobj->{bye}){
                   # LISTから削除
                   $self->redis->lrem($chatroomname,'1',$entry_json);

                   # リスナー登録の解除 
                   $self->redis->unsubscribe($recvlist, sub {
                       my ($redis, $err) = @_;
                          $self->app->log->debug("DEBUG: unsbscribe $username ");
                          return;
                       });
                 return;
               } # {bye}

                 # チャットルーム全体に送信
                       my $jsontxt = to_json($jsonobj);
                       $self->redis->publish( "$chatroomname" , $jsontxt);
                       $self->app->log->debug("DEBUG: publish: $username :  $chatroomname : $jsontxt");

                }); # onmessageのはず。。。

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $msg) = @_;

            # pubsubのunsubscribe
               $self->redis->unsubscribe($recvlist, sub {
                   my ($redis, $err) = @_;

                      return;
                   });
            # LIST登録の解除 
            $self->redis->lrem($chatroomname,'1', $entry_json);

               $self->app->log->debug('Client disconnected');
               delete $clients->{$id};

        });  # onfinish...

         #redis receve
         $self->redis->on(message => sub {
                my ($redis,$mess,$channel) = @_;

           #     if ( $channel == 'WALKCHAT' ) { return; } # WALKCHATは除外する
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

#  $self->render(msg => '');
}

1;
