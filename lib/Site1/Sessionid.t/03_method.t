#03_method.t

use strict;
use warnings;
use Test::More;

use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use Sessionid;

my $string = 'test@test.com';


subtest 'word method' => sub {
    my $obj = Sessionid->new($string);
    my $word = $obj->word;
    is $word, 'test@test.com';
};

subtest 'sid' => sub {
    my $obj = Sessionid->new->sid;
    print "SID: $obj \n";
    ok $obj;
};

subtest 'uid' => sub {
    my $obj = Sessionid->new($string);
    my $uid = $obj->uid;
    print "UID: $uid \n";
    ok $uid;
};


done_testing;
