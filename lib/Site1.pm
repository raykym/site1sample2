package Site1;
use Mojo::Base 'Mojolicious';
use DBIx::Connector;
use Mojolicious::Plugin::OAuth2;
use MongoDB;
use Mango;
use Mojo::Redis2;

sub startup {
  my $self = shift;

  # hypnotoad start
  $self->config(hypnotoad=>{
                       listen => ['http://*:3800'],
                       accepts => 100,
                       clients => 2,
                       workers => 10,
                       proxy => 1,
                       });

# DB設定 $self->app->dbconn->dbh でアクセス可能になる

  # TEST環境用DSN
  if ( defined $ENV{TEST_DSN} ){
    (ref $self)->attr(
       dbconn => sub {
            DBIx::Connector->new($ENV{TEST_DSN});
        })
    } else {
  # 実環境ではこちらのDSN設定
  my   $config = $self->plugin('Config');
  (ref $self)->attr(
       dbconn => sub {
           DBIx::Connector->new("dbi:mysql:dbname=sitedata;host=$config->{dbhost};port=3306","$config->{dbname}","$config->{dbpass}",
        {RaiseError=>1, AutoCommit=>1,mysql_enable_utf8=>1});
       }
      );
  } # else

   # mongodb SSL option
  # my $mongooption = { ssl => {
  #                         ###   SSL_ca_file => "/etc/letsencrypt/live/westwind.iobb.net/fullchain.pem",
  #                            SSL_cert_file => "/etc/letsencrypt/mongodb.pem",
  #                            },
  #                   };

   # $self->app->mongoclientでアクセス
   $self->app->helper(mongoclient =>
      ###  sub { state $mongoclient = MongoDB->connect('mongodb://104.155.205.100:27017');
        sub { state $mongoclient = MongoDB->connect('mongodb://192.168.0.5:27017');
      #  sub { state $mongoclient = MongoDB->connect('mongodb://mongodb.backbone.site:27017',$mongooption);
            });

   # $self->app->mango mongodb3.0 need...
   $self->app->helper(mango =>
        sub { state $mango = Mango->new('mongodb://192.168.0.5:27017');
            });

   # $self->app->redis
   $self->app->helper( redis =>
        ###sub { shift->stash->{redis} ||= Mojo::Redis2->new;
        sub { state $redis = Mojo::Redis2->new;
         });

#OAuth2
   $self->plugin('OAuth2' => {
              google => {
                  key => '861600582037-j2gm11pu28gapapmdkjacjfi5jknngho.apps.googleusercontent.com',
                  secret => 'gsoKlLoL4vXI6u5GakodvS72',
               #   authorize_url => "https://accounts.google.com/o/oauth2/auth",
                  authorize_url => "https://accounts.google.com/o/oauth2/v2/auth",
               #   token_url => "https://accounts.google.com/o/oauth2/token",
                  token_url => "https://www.googleapis.com/oauth2/v4/token",
                    },
               fix_get_token => 1,
                  });

  # Router
  my $r = $self->routes;

### bridge設定
  my $bridge = $r->under->to('Login#usercheck'); 
# listviewを付加したもの。
  my $listbridge = $bridge->under->to('Filestore#listview');

# websocket setting
########  $r->websocket('/menu/chatroom/echo')->to(controller => 'Chatroom', action => 'echo');
#  $bridge->websocket('/menu/chatroom/echo')->to(controller => 'Chatroom', action => 'echo');
  $bridge->websocket('/menu/chatroom/echodb')->to(controller => 'Chatroom', action => 'echodb');
#  $bridge->websocket('/menu/chatroom/echopg')->to(controller => 'Chatroom', action => 'echopg');
  $bridge->websocket('/signaling')->to(controller => 'Chatroom', action => 'signaling');
#  $bridge->websocket('/roomentrycheck')->to(controller => 'Chatroom', action => 'roomentrycheck');
  $bridge->websocket('/roomentrylist')->to(controller => 'Chatroom', action => 'roomentrylist');
  $bridge->websocket('/wsocket/signaling')->to(controller => 'Webroom', action => 'signaling');
  $bridge->websocket('/wsocket/webpubsub')->to(controller => 'Webroom', action => 'webpubsub');
  $bridge->websocket('/echopubsub')->to(controller => 'Chatroom', action => 'echopubsub');
#  $bridge->websocket('/webnotice')->to(controller => 'Webnotice', action => 'webnotice');
#  $bridge->websocket('/menu/rec-timeline/record')->to(controller => 'Timeline',action => 'record');
#  $r->websocket('/menu/rec-timeline/chrome')->to(controller => 'Timeline',action => 'chrome');
#  $bridge->websocket('/menu/maptimeline/echo')->to(controller => 'Timeline',action => 'echo');
  $bridge->websocket('/walkworld')->to(controller => 'Walkworld',action => 'echo');
  $r->websocket('/walkworldsupv')->to(controller => 'Walkworld',action => 'echo3');


  # Normal route to controller
#   $r->get('/example')->to('example#welcome');
  $r->any('/')->to('top#top');
  $r->get('/signup')->to('login#signup');        
  $r->get('/signin')->to('login#signin');       
  $r->post('/signinact')->to('login#signinact'); #template未使用
  $r->post('/signupact')->to('login#signupact'); #template未使用 

  $r->get('/valhara')->to('top#valhara');

  $r->get('/googleauth')->to('top#googleauth'); # login short url

  $r->any('/oauth2callback')->to(controller => 'Login', action => 'oauth2callback');

   # 以下はログイン認証済でないとページに入れない
  $bridge->get('/menu')->to('top#mainmenu');          
  $bridge->get('/menu2')->to('top#mainmenu2');          
  $bridge->get('/menu/settings')->to('login#menusettings');
  $bridge->get('/menu/settings/email')->to('login#emailset');
  $bridge->post('/menu/settings/emailact')->to('login#emailsetact'); #template未使用
  $bridge->get('/menu/settings/uname')->to('login#unameset');
  $bridge->post('/menu/settings/unameact')->to('login#unamesetact'); #template未使用
  $bridge->get('/menu/settings/passwd')->to('login#passwdset');
  $bridge->post('/menu/settings/passwdact')->to('login#passwdsetact'); #template未使用
  $listbridge->any('/menu/settings/seticon')->to('filestore#seticon');
  $bridge->any('/menu/settings/seticonact')->to('filestore#seticonact');

#  $r->get('/menu/upload')->to('filestore#upload');
  $bridge->route('/menu/upload')->to('filestore#upload');
  $bridge->post('/menu/uploadact')->to('filestore#uploadact');

## listbridgeへ移行  $bridge->get('/menu/listview')->to('filestore#listview');
# list処理をbridgeに噛ませたもの
# filelist => \@slice, page => $pageを受ける
  $listbridge->get('/menu/listview')->to('filestore#listview_p');

  $bridge->any('/menu/fileview')->to('filestore#fileview'); # 個別表示ページ
  $bridge->post('/menu/fileviewact')->to('filestore#fileviewact'); # コメントの入力

  $bridge->any('/imgload')->to('filestore#imgload'); # imgload用パス
  $bridge->any('/imgcomm')->to('filestore#imgcomm'); # chatroom用パス

  $bridge->post('/putfileimg')->to('filestore#putfileimg'); 
  $r->get('/getfileimg')->to('filestore#getfileimg'); 

  $listbridge->any('/menu/delfileview')->to('filestore#delfileview');
  $bridge->post('/menu/delfileviewact')->to('filestore#delfileviewact');

#  $bridge->get('/menu/chatroom')->to('chatroom#view');
  $bridge->get('/menu/chatroomdb')->to('chatroom#viewdb');
#  $bridge->get('/menu/chatroompg')->to('chatroom#viewpg');
#  $bridge->get('/menu/mirror')->to('mirror#mirror');

#  $bridge->get('/webrtcx4')->to('chatroom#webrtcx4'); # 未完
#  $bridge->get('/webrtcx2')->to('chatroom#webrtcx2');
  $bridge->get('/voicechat')->to('chatroom#voicechat');
  $bridge->get('/videochat')->to('chatroom#videochat');
  $bridge->get('/voicechat2')->to('chatroom#voicechat2');
  $bridge->get('/voicechat2n')->to('chatroom#voicechat2n');
  $bridge->get('/videochat2')->to('chatroom#videochat2');
  $bridge->get('/videochat2n')->to('chatroom#videochat2n');
  $bridge->get('/menu/chatopen')->to('chatroom#chatopen');
#  $bridge->get('/voicechatspot')->to('chatroom#voicechatspot'); # 未完
#  $bridge->get('/videochat2pc')->to('chatroom#videochat2pc');

#  $bridge->get('/webnotice/view')->to('webnotice#view');

#  $bridge->get('/menu/rec-timeline')->to('timeline#view');
#  $bridge->get('/menu/maptimeline')->to('timeline#mapview');

  $bridge->any('/notifications')->to('top#notifications');
  $bridge->post('/receive')->to(controller => 'Top', action => 'receive');
  $bridge->get('/delwebpush')->to(controller => 'Top', action => 'delwebpush');
  $bridge->post('/sendwebpush')->to(controller => 'Top', action => 'sendwebpush');

  $bridge->get('/test/webpubsub')->to('chatroom#webpubsub');

  $bridge->get('/walkworld/view')->to('walkworld#view');
  $bridge->get('/walkworld/pointget')->to('walkworld#pointget');
  $bridge->get('/walkworld/supervise')->to('walkworld#supervise');

  $r->get('/walkworld/overviewWW')->to('walkworld#overviewWW');

#  $r->any('/walkworld/rcvpush')->to(controller => 'Walkworld', action => 'rcvpush');

  $r->any('*')->to('Top#unknown'); # 未定義のパスは全てunknown画面へ
}

1;
