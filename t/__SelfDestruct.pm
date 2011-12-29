package __SelfDestruct;

use warnings;
use strict;

sub spawn_n_kill (&) {
  {
    my $x = bless [ $_[1], ($INC{'threads.pm'} ? threads->tid : 0) ];
    undef $x;
  }
  1;
}

sub DESTROY {
  $_[0]->[0]->() unless ($_[0]->[1] and threads->tid != $_[0]->[1]);
}

1;
