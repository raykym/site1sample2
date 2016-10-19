#05_passwd.t

use strict;
use warnings;
use Test::More;

use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use Inputchk;

subtest 'success check' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = 'asakiyume_34';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   is $res,0;
};

subtest 'No input check' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = ' ';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   isnt $res,0;
};

subtest 'length error' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = 'asaki_y';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   isnt $res,0;
};

subtest 'alfa only error' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = 'asakiylksk';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   isnt $res,0;
};

subtest 'numeric only error' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = '0123456789';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   isnt $res,0;
};

subtest 'mark only error' => sub {
   local $SIG{__WARN__} = sub { fail shift };
   my $str = '_#%&-';
   my $obj = Inputchk->new($str);
      $obj->password;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };

   my $res = $obj->result;
   isnt $res,0;
};

done_testing;
