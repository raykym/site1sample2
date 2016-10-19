#t/02_new.t

use strict;
use warnings;
use Test::More;
use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use Inputchk;

subtest 'no_args' => sub {
   my $obj = Inputchk->new;
   isa_ok $obj, 'Inputchk';
};

subtest '$str is null' => sub {
    my $str = '';
    my $obj = Inputchk->new($str);
    isa_ok $obj, 'Inputchk';
};

subtest '$str' => sub {
    my $str = 'aaa@bbb.ccc';
    my $obj = Inputchk->new($str);
    isa_ok $obj, 'Inputchk';
};

done_testing;
