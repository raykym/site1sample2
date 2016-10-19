#!/usr/bin/env perl

use strict;
use warnings;

use lib '/home/debian/perlwork/mojowork/server/site1/lib/Site1/';
use Inputchk;

use feature 'say';


my $str = 'soreha  エロアホ';
my $email = Inputchk->new($str);
my $res = $email->string;
#   $email->email;
#say $email->result;
   say "$res";

   $email->ngword;
my $resp = $email->result;
   say "$resp";
