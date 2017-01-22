package Site1::Controller::Login;
use Mojo::Base 'Mojolicious::Controller';
use Encode;
use DateTime;
use MIME::Base64::URLSafe; # icon用oidを渡す
use Mojo::JSON qw(from_json to_json encode_json decode_json);
use Mojo::Util qw(dumper);

# 独自パスを指定して自前モジュールを利用
use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1';
use Sessionid;
use Inputchk;

sub signup {
  my $self = shift;
  #表示のみで入力結果を/signupactで処理する
  $self->render(msg => '');
}
sub signin {
  my $self = shift;
  #表示のみで入力結果を/signinactで処理する
  $self->render(msg => '');
}
sub signupact {
  my $self = shift;

  my $config = $self->app->plugin('Config');

  # DB設定
  my $sth_signup = $self->app->dbconn->dbh->prepare("$config->{sql_signup}");
  my $sth_user = $self->app->dbconn->dbh->prepare("$config->{sql_user}");
  my $sth_chk_signup = $self->app->dbconn->dbh->prepare("$config->{sql_chk_signup}");

  #signupから入力パラメータを受け取る。
  #入力チェックと重複チェックを行い、表示ページを振り分ける

  my $email = $self->param('email');
     $email = encode_utf8($email);
  my $username = $self->param('username');
     $username = encode_utf8($username);
  my $password = $self->param('password');
     $password = encode_utf8($password);

# 入力チェック
  my $chkemail = Inputchk->new($email);
     $chkemail->email;
  my $res_e = $chkemail->result;
     undef $chkemail;
     if ($res_e > 0 ) { 
          $self->app->log->debug('Notice: email check error.');
         }

     # 登録済みチェック
     if ( $res_e == 0 ) { 
         $sth_chk_signup->execute($email);
         if ( $sth_chk_signup->rows != 0 ) { $res_e = 1; }
                   # $res_eを１にしてエラーにする
         if ($res_e > 0 ) { 
              $self->app->log->debug('Notice: email DB check error.');
              }
          }

  my $chkuname = Inputchk->new($username);
     $chkuname->ngword;
  my $res_un = $chkuname->result;
     undef $chkuname;
     if ( $res_un > 0 ) {
         $self->app->log->debug('Notice: username check error.');
        }

  my $chkpass = Inputchk->new($password);
     $chkpass->password;
  my $res_pa = $chkpass->result;
     undef $chkpass;
     if ( $res_pa > 0 ) { 
        $self->app->log->debug('Notice: password check error.');
       }

  # 入力エラーの場合の表示遷移
  if ($res_e != 0 or $res_un != 0 or $res_pa != 0) {
     $self->app->log->debug('Notice: Input Error');
     $self->render(msg => '--- input error ---', template => 'login/signup');
     return;
   } # error 入力ページへ戻る

   # UTF-8デコード
     $email = decode_utf8($email);
     $username = decode_utf8($username);
     $password = decode_utf8($password);


  my $sid = Sessionid->new->sid;
  my $uid = Sessionid->new($email)->uid;
  my $checkdate = DateTime->now();
     # user情報の登録
     $sth_user->execute($email,$username,$password,$uid,$checkdate);
     $sth_signup->execute($email,$sid);


# cookie設定
     $self->cookie('site1'=>"$sid",{httponly => 'true',path => '/', max_age => '31536000', secure => 'true'});

  $self->redirect_to('/menu'); #/menuへリダイレクト

# 利用した変数の解放
  undef $sid;
  undef $email;
  undef $username;
  undef $password;
  undef $sth_signup;
  undef $sth_user;
  undef $sth_chk_signup;
}

sub usercheck {
    my $self = shift;
    # 認証が必要な場合すべてこのパスを通過する
    # redisでキャッシュして応答速度を上げる

       $self->app->log->debug('Notice: Usercheck ON!');

    # DB接続
    my $config = $self->app->plugin('Config');
    my $sth_sid_chk = $self->app->dbconn->dbh->prepare("$config->{sql_sid_chk}");
    my $sth_user_chk = $self->app->dbconn->dbh->prepare("$config->{sql_user_chk}");
    my $sth_chktimeupdate = $self->app->dbconn->dbh->prepare("$config->{sql_chktime_update}");
    my $sth_atoken_update_sid = $self->app->dbconn->dbh->prepare("$config->{sql_atoken_update_sid}");

    my $sid = $self->cookie('site1');

    # cookieが取れない->リダイレクト
    if ( ! defined $sid ){ 
        $self->app->log->debug('Notice: Not get Cookie!');
        $self->redirect_to('/');
        return;
      }

    my $userredisid = "SID$sid";

    # redisバイパスチェック
    my $userredis = $self->redis->get($userredisid);

    if (defined $userredis) {

             my $userobj = from_json($userredis);

             $self->app->log->debug("DEBUG: redis: $userredis");
             $self->app->log->debug("DEBUG: redis: $userobj->{email}");

        # $iconを無くす方向で考えていたが、表示で利用していたので削除出来なかった。
            $self->stash( email => $userobj->{email} );
            $self->stash( username => $userobj->{username} );
            $self->stash( uid => $userobj->{uid} ); #uidはページで利用しないのでencodeしない
            $self->stash( icon => $userobj->{icon} );
            $self->stash( icon_url => $userobj->{icon_url} );

        undef $userredis;
        undef $userobj;

        # underのため、stashに設定して次へ
        return 1;
        }


    # sidからチェック開始 (signup_tbl)
       $sth_sid_chk->execute($sid);
    my $get_value = $sth_sid_chk->fetchrow_hashref();
    my $email = $get_value->{email};
    my $atoken = $get_value->{atoken};
    my $rtoken = $get_value->{rtoken};


    #ローカル認証（user_tbl)
       $sth_user_chk->execute($email);
    my $get_uname = $sth_user_chk->fetchrow_hashref();
    my $username = $get_uname->{username};
       $self->app->log->debug("DEBUG: username(local): $username") if ( defined $username);
    my $uid = $get_uname->{uid};
       $self->app->log->debug("DEBUG: uid(local): $uid") if ( defined $uid);
    my $icon = $get_uname->{icon};
    # $iconが空ならNow printingが設定される。
       if (! defined $icon ) { $icon = 'nowprint';}
       $icon = urlsafe_b64encode($icon) if ( $icon ne "nowprint"); #urlsafe_b64encode
    my $icon_url ;


 if (! defined $username ) {   

    # OAuth2の認証確認 ローカル認証で結果が得られない前提で！
    my $ua = Mojo::UserAgent->new;
    my $value = $ua->get(
                "https://www.googleapis.com/plus/v1/people/me?access_token=$atoken"
                )->res->json if (defined $atoken);

    my $text = to_json($value);
       $self->app->log->info("DEBUG: value: $text");

    #結果がエラーならrefresh tokenでaccess tokenを取得
    if (! defined $value->{displayName}) {
        my $data = $ua->post(
               "https://accounts.google.com/o/oauth2/token" => form => {
                                  refresh_token => $rtoken,
                                  client_id => "861600582037-j2gm11pu28gapapmdkjacjfi5jknngho.apps.googleusercontent.com", 
                                  client_secret => "gsoKlLoL4vXI6u5GakodvS72",
                                  grant_type => "refresh_token",
                                           })->res->json;
               my $new_token = to_json($data);
               $self->app->log->info("DEBUG: newtoken: $new_token");

       if ( $data->{token_type} eq "Bearer" ) {
       #id_tokenでリトライ
       $value = $ua->get(
                "https://www.googleapis.com/plus/v1/people/me?access_token=$data->{id_token}"
                )->res->json if (defined $atoken);

       $text = to_json($value);
       $self->app->log->info("DEBUG: value 2: $text");
           } # if token_type

            # リフレッシュトークンの取得失敗
               if (( defined $value->{error} ) || ( $new_token == "null" )){
                   $self->app->log->debug('Notice: refresh token MISS TAKE');
                   $self->redirect_to('/');
                   return;
                  }

                  $atoken = $data->{access_token};
                  $self->app->log->debug("DEBUG: new access_token: $atoken");
               
               $sth_atoken_update_sid->execute($atoken,$sid);

    # 再度atokenを取得 DBにatokenが格納されたか確認する
       $sth_sid_chk->execute($sid);
       $get_value = $sth_sid_chk->fetchrow_hashref();
       $email = $get_value->{email};
       $atoken = $get_value->{atoken};
       $rtoken = $get_value->{rtoken};

     #$atokenが有れば再度取得し直す
     $value = $ua->get(
                "https://www.googleapis.com/plus/v1/people/me?access_token=$atoken"
                )->res->json if ( defined $atoken );
       #self->app->log->info("DEBUG: new atoken: $atoken");

       $text = to_json($value);
       $self->app->log->info("DEBUG: new value: $text"); 

        } # defined displayName

    my $valueobj = encode_json($value);
       $email = $value->{emails}->[0]->{value} unless $email; # 無ければ
       $self->app->log->debug("DEBUG: email: $email");
       $username = $value->{displayName} unless $username; #無ければ
       $self->app->log->debug("DEBUG: displayName: $username");
       $icon_url =$value->{image}->{url};
       $self->app->log->debug("DEBUG: icon_url: $icon_url") if (defined $icon_url);
    my $gpid = $value->{id};

       $uid = Sessionid->new($gpid)->guid unless $uid; #無ければ
       $self->app->log->info("DEBUG: guid: $uid");

    # email,usernameが取得できない場合 ->リダイレクト
    if ( ! defined $email and ! defined $username ) {
        $self->app->log->info('Notice: email or username not get Error!');
        $self->redirect_to('/');
        return;
       }

    undef $text;
    undef $value;
    undef $valueobj;

  } # if defined $username


    #日付update
    my $dumytime = time;
    my $checkdate = DateTime->now();
    $sth_chktimeupdate->execute($checkdate,$dumytime,$sid);
  ###  $self->app->log->debug("DEBUG: DBI: $DBI::errstr ");

    $self->stash( email => $email );
    $self->stash( username => $username );
    $self->stash( uid => $uid ); #uidはページで利用しないのでencodeしない
    $self->stash( icon => $icon );
    $self->stash( icon_url => $icon_url );

    # redis登録
    if ( ! defined $icon_url) {
           $icon_url = "/imgcomm?oid=$icon"; 
        } 

    my $jsonobj = { email => $email, username => $username, uid => $uid, icon => $icon, icon_url => $icon_url };
    my $jsontext = to_json($jsonobj);
    $self->app->log->info("DEBUG: set redis: $jsontext ");

       $self->redis->set($userredisid => $jsontext);
       $self->redis->expire( $userredisid => 86400);


  # 変数の解放
  undef $config;
  undef $sth_sid_chk;
  undef $sth_user_chk;
  undef $sid;
  undef $sth_chktimeupdate;
  undef $icon;
  undef $dumytime;
  undef $checkdate;
  undef $uid;
  undef $get_value;
  undef $jsonobj;
  undef $jsontext;
  
  # underのため、stashに設定して次へ
  return 1;
}

sub signinact {
    my $self = shift;

    # DB設定
    my $config = $self->app->plugin('Config');
    my $sth_signin_chk = $self->app->dbconn->dbh->prepare("$config->{sql_signin_chk}");
    my $sth_signup_update = $self->app->dbconn->dbh->prepare("$config->{sql_signup_update}");
    
    my $email = $self->param('email');
       $email = encode_utf8($email);
    my $password = $self->param('password');
       $password = encode_utf8($password);

    # 入力されたセットがあるのか確認
      $sth_signin_chk->execute($email,$password);
    my $signin_chk_uname =  $sth_signin_chk->fetchrow_hashref();
    my $username = $signin_chk_uname->{username};

       # usernameが取得できなければエラーとして入力ページヘ
       if ( ! defined $username ) {
           $self->app->log->debug('Notice: Not get username!');
           $self->render(msg => '--- e-mail or password Not match! ---', template => 'login/signin');
           return;
          }

    # sessionidのアップデート
    my $sid = Sessionid->new->sid;
       $sth_signup_update->execute($sid,$email);

# cookie設定
       $self->cookie('site1'=>"$sid",{httponly => 'true',path => '/', max_age => '31506000', secure => 'true'});

   undef $sid;
   undef $sth_signup_update;
   undef $username;
   undef $signin_chk_uname;
   undef $sth_signin_chk;
   undef $password;
   undef $email;
   undef $config;
   undef $sth_signup_update;

  $self->redirect_to('/menu'); #/menuへリダイレクト
}

sub menusettings {
  my $self = shift;
  #表示のみ テンプレートを共有化の為、emailsetact,unamesetact,passwdsetactと同じもの
  $self->render(msg => 'Google+アカウントはここで変更できません！！ と、言うか、しないで下さい。。。');
}

sub emailset {
  my $self = shift;
  #表示のみ
  $self->render();
}

sub emailsetact {
  my $self = shift;

  my $config = $self->app->plugin('Config');
  my $sth_email_update = $self->app->dbconn->dbh->prepare("$config->{sql_email_update}");   
  my $sth_email_update_sid = $self->app->dbconn->dbh->prepare("$config->{sql_email_update_sid}");

  my $old_email = $self->stash('email');
  my $new_email = $self->param('email');
     $new_email = encode_utf8($new_email);
  my $emailcheck = Inputchk->new($new_email);
     $emailcheck->email;
  my $res_e = $emailcheck->result;
     
     #　入力エラーが在った場合
     if ($res_e > 0 ) {
        $self->app->log->debug('Notice: No good e-mail');
        $self->render(msg => '--- Input Error ---', template => 'login/menusettings');
        return; 
     }

     $new_email = decode_utf8($new_email);

  my $sid = $self->cookie('site1');
    
     $sth_email_update->execute($new_email,$old_email);
     $sth_email_update_sid->execute($new_email,$sid);
     # usercheck()はsidから検索可能かを調べているだけなので、書き換えても問題は無いはず

  #$self->stashはusercheck()で上書きされるはずだが、
     $self->stash( email => $new_email );

  $self->redirect_to('/menu/settings'); #元のページヘ戻る
}

sub unameset {
  my $self = shift;
  #表示のみ
  $self->render();
}

sub passwdset {
  my $self = shift;
  #表示のみ
  $self->render();
}

sub unamesetact {
  my $self = shift;

  my $config = $self->app->plugin('Config');
  my $sth_uname_update = $self->app->dbconn->dbh->prepare("$config->{sql_uname_update}");   
  my $uname = $self->param('username');
     $uname = encode_utf8($uname);
  my $email = $self->stash('email');

  my $unamechk = Inputchk->new($uname);
     $unamechk->ngword;
  my $res_un = $unamechk->result;
     if ( $res_un > 0 ) {
         $self->app->log->debug('Notice: username check error.');
         $self->render(msg => '--- Input Error ---', template => 'login/menusettings');
         return; 
        }
      $uname = decode_utf8($uname);

      $sth_uname_update->execute($uname,$email);

      #$self->stashはusercheck()で上書きされるはずだが、
      $self->stash( username => $uname );

  $self->redirect_to('/menu/settings'); #元のページヘ戻る
}

sub passwdsetact {
  my $self = shift;

  my $config = $self->app->plugin('Config');
  my $sth_passwd_update = $self->app->dbconn->dbh->prepare("$config->{sql_passwd_update}");   
  my $email = $self->stash('email');
  my $passwd = $self->param('password');
     $passwd = encode_utf8($passwd);

  my $passwdchk = Inputchk->new($passwd);
     $passwdchk->password;
  my $res_pass = $passwdchk->result;
     if ( $res_pass > 0 ) {
         $self->app->log->debug('Notice: password check error.');
         $self->render(msg => '--- Input Error ---', template => 'login/menusettings');
         return; 
        }
      $passwd = decode_utf8($passwd);

     $sth_passwd_update->execute($passwd,$email);

  $self->redirect_to('/menu/settings'); #元のページヘ戻る
}

# google+の認証コールバック
sub oauth2callback {
    my $self = shift;

  my $config = $self->app->plugin('Config');

  # DB設定
  my $sth_signup_gp = $self->app->dbconn->dbh->prepare("$config->{sql_signup_gp}");
  my $sth_signup_update_gp1 = $self->app->dbconn->dbh->prepare("$config->{sql_signup_update_gp1}");
  my $sth_signup_update_gp2 = $self->app->dbconn->dbh->prepare("$config->{sql_signup_update_gp2}");
  my $sth_chk_signup = $self->app->dbconn->dbh->prepare("$config->{sql_chk_signup}");


    $self->delay(
        sub {
         my $delay = shift;
             my $args = {redirect_uri => "https://westwind.iobb.net/oauth2callback"};
             $self->oauth2->get_token(google => $args,$delay->begin);
         },
        sub {
            my ($delay,$err,$data) = @_;

                return $self->redirect_to("/") unless $data;

                $self->app->log->info("DEBUG: get_token err: $err ");
                my $datajson = to_json($data);
                $self->app->log->info("DEBUG: data: $datajson");

            my $ua = Mojo::UserAgent->new;
            my $value = $ua->get(
             #   "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$data->{access_token}"
                "https://www.googleapis.com/plus/v1/people/me?access_token=$data->{access_token}"
                )->res->json;


               $self->app->log->debug("DEBUG: Access_token: $data->{access_token}");
               $self->app->log->debug("DEBUG: Refresh_token: $data->{refresh_token}");

            my $valueobj = encode_json($value);

            my $email = $value->{emails}->[0]->{value};
               $self->app->log->debug("DEBUG: email: $email");

            my $sid = Sessionid->new->sid;

           # cookie設定
               $self->cookie('site1'=>"$sid",{httponly => 'true',path => '/', max_age => '31536000', secure => 'true'});

           # 重複チェック
            $sth_chk_signup->execute($email);
           my $chkcnt = $sth_chk_signup->rows;

           # DBへの登録 重複ならupdate、初回ならinsert
               $sth_signup_gp->execute($email,$sid,$data->{access_token},$data->{refresh_token}) if ($chkcnt == 0); 
               $sth_signup_update_gp1->execute($sid,$email) if ($chkcnt != 0); 
               $sth_signup_update_gp2->execute($data->{access_token},$email) if ($chkcnt != 0); 

           my $username = $value->{displayName};
           my $icon_url =$value->{image}->{url};
           my $gpid = $value->{id};

           $self->stash(username => $username);
           $self->stash(icon_url => $icon_url);
           $self->stash(gpid => $gpid);

           $self->app->log->debug("DEBUG: Displayname: $value->{displayName}");
           $self->app->log->debug("DEBUG: image: $value->{image}->{url}");
           $self->app->log->debug("DEBUG: gpid: $value->{id}");

            # uidの生成
            my $uid = Sessionid->new($gpid)->guid;
               $self->app->log->debug("DEBUG: uid: $uid");
           $self->stash(uid => $uid);

         #      return $self->render("connect",error => $err) unless $data;
         #      return $self->render( json => $data);

           $self->redirect_to("/menu");
         });
}

1;
