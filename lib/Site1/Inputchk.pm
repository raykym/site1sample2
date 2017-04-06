package Inputchk;

use strict;
use warnings;
use Encode;

# 入力結果のチェックルーチン集
# email:e-mail形式のチェック
# password: passwordの入力形式をチェックする
# ngword: NGワードをチェックする。

# newの引数でスカラー変数を受けて、オブジェクトにする
# 結果は@result配列で返す。
# stringとresがアクセサーとして値を確認出来る。
# resultアクセサーではresult値から結果を０，１で返す

sub new {
  my ($class,$arg,@result) = @_;
  return bless {string => $arg,result => \@result},$class;
  }

# e-mailアドレス形式（aaa@bbb.ccc)かどうか
sub email {
   my $self = shift;
   
   my $str = $self->{string};
   my $res = $self->{result};

   if ($str =~ /[\/\\\!"#\$%&'\(\)=~\|;:\^\*<>\?\+`]/){
         push (@{$res},1); # format error 
     } else { 
         push (@{$res},0); # format ok
     }
   if ($str !~ /@/) {
         push (@{$res},1); # @ error 
     } else { 
         push (@{$res},0); # @ ok
     }

   my @chk_addr = split(/@/,$str);

   if (scalar @chk_addr > 2) {
         push (@{$res},1); # dup@ error 
     } else { 
         push (@{$res},0); # dup@ ok
     }

   if (!defined $chk_addr[0]){ $chk_addr[0] = 'a' } # 空白入力のエラー処理(パスさせる）
   if (!defined $chk_addr[1]){ $chk_addr[1] = 'a' } # @が無いケースのエラー処理
   if ($chk_addr[0] =~ /[A-Za-z0-9]*/ and $chk_addr[1] =~ /[A-Za-z0-9]*/) { 
         push (@{$res},0); # char ok 
     } else { 
         push (@{$res},1); # char error
     }

   undef $str;
   undef @chk_addr;

  } #email

sub result {
    my $self = shift;
    
    # @$resが全部0ならOK　それ以外はNG
    my $res = $self->{result};
    my $sum = 0;
    foreach my $i (@$res){
           $sum = $sum + $i;
        }
    
    if ( $sum == 0 ) { return 0} else { return 1}

  } # result

sub string {
    my $self = shift;

    return $self->{string};
  } # string

sub res {
   my $self = shift;
   # 配列リファレンスが返る
   return $self->{result};
  }# res

sub password {
    #文字数8文字以上、英数字、_!-#%&を１文字づつ以上使う:
    my $self = shift;

    my $count = 8;

    my $str = $self->{string};
    my $res = $self->{result};

    if ( length($str) > 8 ) {
         push (@{$res},0); # length ok
     } else { 
         push (@{$res},1); # length error 
     }

    if ( $str !~ /[A-Za-z]/ ) {
         push (@{$res},1); # char error 
     } else { 
         push (@{$res},0); # char ok
     }

    if ( $str =~ /[_!#%&-]/ ) {
         push (@{$res},0); # mark ok
     } else { 
         push (@{$res},1); # mark not error 
     }
    if ( $str =~ /[0-9]/ ) {
         push (@{$res},0); # numeric ok
     } else { 
         push (@{$res},1); # numeric not error 
     }

  undef $str;
  undef $res;

  } # password

sub ngword {
    my $self = shift;
    # ngword.txtのキーワードをチェックする。単独、または前後に空白がある状態を検知する。
    #記号などを用いてキーワードを修飾していると検知出来ない。
    my $str = $self->{string};
    my $res = $self->{result};

     #空白チェック
        if ( $str eq '') { push (@{$res},1) } else { push (@{$res},0)};

    my $filename = '/home/debian/perlwork/mojowork/server/site1/ngword.txt';

    open (IN,"< $filename");

    my @ngword = <IN>;

    foreach my $w (@ngword){
        chomp $w;
        if ( $str =~ /\s$w\s/m or $str =~ /^$w$/ ) { push (@{$res},1) } else { push (@{$res},0)};
        }

   undef $str;
 #  undef @ngword;  #パフォーマンスを優先するとundefしない、

  } #ngword

1;
