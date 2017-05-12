package Site1::Controller::Top;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::UserAgent;
use Mojo::JSON qw(from_json to_json);
use DateTime;

# This action will render a template
sub top {
  my $self = shift;

  $self->render(msg => 'Welcome to this site!');
}

sub mainmenu {
    my $self = shift;

    $self->render(msg => 'OPEN the Menu!');
}

sub mainmenu2 {
    my $self = shift;

    $self->render(msg => 'OPEN the Menu!');
}

sub unknown {
    my $self = shift;
    # 未定義ページヘのアクセス
    $self->render();
}

sub valhara {
    my $self = shift;
    # ヴァルハラゲート用タグ集
    $self->render();
}

sub notifications {
    my $self = shift;
    # sw.js

    my $endpoint = $self->param('endpoint');
       $self->app->log->info("DEBUG: noti endpoint: $endpoint");

    my $icon = $self->stash('icon');
    my $icon_url = $self->stash('icon_url');
       $icon_url = "https://westwind.iobb.net/imgcomm?oid=$icon" if (! defined $icon_url);

    my $redis ||= Mojo::Redis2->new;
    my $getmess = $redis->get("$endpoint");
    my $messobj = from_json($getmess);

    my $push_json = { "title" => "通知が届きました！",
                      "icon" => "$icon_url",
                      "body" => "$messobj->{body}",
                      "url" => "$messobj->{url}"
                    };
           #####           "body" => "$messobj->{from}さんから,$messobj->{page}の申請です。roomは$messobj->{roomname}です。",
    $self->res->headers->header("Access-Control-Allow-Origin" => 'https://westwind.iobb.net/' );
    $self->render( json => $push_json );

    undef $endpoint;
    undef $icon;
    undef $icon_url;
    undef $getmess;
    undef $messobj;
    undef $push_json;
}

sub receive {
    my $self = shift;
    # webpushでsubscribeしたendpointを登録

    my $hash = $self->req->json;
    my $debug = to_json($hash);
       $self->app->log->info("DEBUG: rec hash: $debug");

    my $email = $self->stash('email');
    my $pushdb = $self->app->mongoclient->get_database('WEBPUSH');
    my $endpoints = $pushdb->get_collection('endpoints');

       $hash->{email} = $email;
       $hash->{ttl} = DateTime->now();
       $endpoints->delete_one({'email' => $email});
       $endpoints->insert_one($hash);

       $self->res->headers->header("Access-Control-Allow-Origin" => 'https://westwind.iobb.net/' );
       $self->render( status => '200' );

   undef $debug;
   undef $hash;
   undef $email;
}

sub delwebpush {
    my $self = shift;
    # webpush unsubscribe

    my $email = $self->stash('email');
    my $pushdb = $self->app->mongoclient->get_database('WEBPUSH');
    my $endpoints = $pushdb->get_collection('endpoints');

       $endpoints->delete_one({'email' => $email});

       $self->app->log->info("DEBUG: delete webpush $email ");

       $self->res->headers->header("Access-Control-Allow-Origin" => 'https://westwind.iobb.net/' );
       $self->render( status => '200' );

    undef $email;

}

sub sendwebpush {
    my $self = shift;
    # 送信者からの情報を元にnotificationsで選択出来るように情報を書き込む。
    # 宛先のエンドポイントが登録されていない場合はメッセージを戻す

    my $hash = $self->req->json;
    my $debug = to_json($hash);
       $self->app->log->info("DEBUG: sendwebpush hash: $debug");
    my $pushdb = $self->app->mongoclient->get_database('WEBPUSH');
    my $endpoints = $pushdb->get_collection('endpoints');
    my $result;

    my $toEndpoint = $endpoints->find_one({email => $hash->{to} });
 #      $self->app->log->info("DEBUG: toEndpoint: $toEndpoint->{endpoint}");

       if (! defined $toEndpoint) {
            $result = "Error Not send message!";

            my $messobj = { "mess" => $result };
            $self->render( json => $messobj);

            return;
       }
    my $redis ||= Mojo::Redis2->new;

    my $hash_json = to_json($hash);

       $redis->set( "$toEndpoint->{endpoint}" => $hash_json );
       $redis->expire( "$toEndpoint->{endpoint}" => 300 );

    my @ep = split(/\//,$toEndpoint->{endpoint});
    my $toep = $ep[$#ep];
#       $self->app->log->info("DEBUG: ep: $toep ");

    my $ua = Mojo::UserAgent->new;

    my $tx = $ua->post('https://android.googleapis.com/gcm/send' => {Authorization => "key=AAAAyJtliZU:APA91bFy4CbCSTFQVLcKaanxPjBR_taMRJDzqgtYFAYYCN-rMbsqOd5NLFXn6J8WiQzrG180Yyy6B2L0AqnG1YPTCy7KsVCUbht-5Ng5yQJt7UpqRO_ZlFOpI7JzlxWDYcR_6R5iVBHX" , "Content-Type" => "application/json" } => json => { "to" => $toep });

    my $res = $tx->result->body;
    my $resobj = from_json($res);
#       $self->app->log->info("DEBUG: FMC res: $res");

       if ( $resobj->{success} eq 1 ) {
             $result = "Sending...";
           } else {
             $result = "Not Sending...";
           }

    my $messobj = { "mess" => $result };

    $self->res->headers->header("Access-Control-Allow-Origin" => 'https://westwind.iobb.net/' );
    $self->render( json => $messobj);
}

1;
