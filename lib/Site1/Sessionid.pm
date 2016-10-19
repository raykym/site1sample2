package Sessionid;

# sidを時刻と乱数で生成する　sid cookieに設定される。
# uidをキーワードと時刻で生成する uid base64エンコード　システム内部での利用だけを想定
# オブジェクトではなく、サブルーチンとして結果を返す

use strict;
use warnings;
use Digest::SHA3;
use Digest::MD5;

sub new {
    my ($class,$args,$sid) = @_;
    #引数なくてもとりあえずok
    return bless { word => $args, sid => $sid } ,$class;
}

sub word {
    my $self = shift;

    return $self->{word};
}

sub sid {
    my $self = shift;

    my $sha3 = Digest::SHA3->new();
    $sha3->add($$, time(), rand(time) );
    $self->{sid} = $sha3->hexdigest();
    return $self->{sid};

    undef $sha3;
};

sub uid {
    my $self = shift;

    my $ctx = Digest::MD5->new();
       $ctx->add($self->word,time);
    my $uid = $ctx->b64digest;
    return $uid;

    undef $ctx;
    undef $uid;
}

sub guid {
    my $self = shift;

    my $ctx = Digest::MD5->new();
       $ctx->add($self->word);
    my $guid = $ctx->b64digest;
    return $guid;

    undef $ctx;
    undef $guid;
}

1;
