package Site1::Controller::Top;
use Mojo::Base 'Mojolicious::Controller';

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

1;
