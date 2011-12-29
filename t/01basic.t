use warnings;
use strict;

use Test::More;
use Exception::Guaranteed;

use lib 't';
use __SelfDestruct;

eval {
  guarantee_exception { die "Simple exception" }
};
like( $@, qr/^Simple exception/, 'A plain exception shoots through' );

my $dummy = 0;
my $fail = 0;
eval {
  guarantee_exception {
    __SelfDestruct->spawn_n_kill(sub {
      die 'Exception outer';
    });
  };

  while( $dummy < 2**31) {
    $dummy++;
  }

  $fail = 1;  # we should never reach here
};
print STDERR "\n";
diag( ($dummy||0) . " inc-ops executed before kill-signal delivery (outer g_e)\n" );
ok (!$fail, 'execution stopped after trappable destroy exception');
like( $@, qr/^Exception outer/, 'DESTROY exception thrown and caught from outside' );

$fail = 0;
# when using the fork+signal based approach, I can't make the exception
# happen fast enough to not shoot out of its real containing eval :(
# Hence the dummy count here is essential
$dummy = 0;
eval {
  __SelfDestruct->spawn_n_kill( sub {
    guarantee_exception {
      die 'Exception inner';
    };
  });

  while( $dummy < 2**31) {
    $dummy++;
  }

  $fail = 1;  # we should never reach here
};

diag( ($dummy||0) . " inc-ops executed before kill-signal delivery (DESTROY g_e)\n" );
ok (!$fail, 'execution stopped after trappable destroy exception');
like( $@, qr/^Exception inner/, 'DESTROY exception thrown and caught from inside of DESTROY block' );

# important, for the thread re-test
if ($ENV{EXCEPTION_GUARANTEED_SUBTEST}) {
  $ENV{EXCEPTION_GUARANTEED_SUBTEST} = 42;
  0; # like an exit(0)
}
else {
  done_testing;
}
