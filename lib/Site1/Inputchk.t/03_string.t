#t/03_string.t

use strict;
use warnings;
use Test::More;
use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use Inputchk;

my $str = 'aaa@bbb.com';
my $obj = Inputchk->new($str);

subtest 'string check' => sub {

   my $res = $obj->string;
   is $res,'aaa@bbb.com';
};

done_testing;
