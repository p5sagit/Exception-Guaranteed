use warnings;
use strict;

use Time::HiRes 'time';

use Config;
# Manual skip, because Test::More can not load before threads.pm
BEGIN {
  unless( $Config{useithreads} ) {
    print( '1..0 # SKIP Your perl does not support ithreads' );
    exit 0;
  }
}

use threads;
use Test::More;

eval {
  require Exception::Guaranteed;
  threads->VERSION(Exception::Guaranteed::THREADS_MIN_VERSION() )
} or plan skip_all => "threads @{[ Exception::Guaranteed::THREADS_MIN_VERSION() ]} required for successfull testing";

my $rerun_test = 't/01basic.t';

my $worker = threads->create(sub {
  $ENV{EXCEPTION_GUARANTEED_SUBTEST} = 1;
  my $err = (do $rerun_test) || $@;
  die "FAIL: $err" if $err;
  return $ENV{EXCEPTION_GUARANTEED_SUBTEST};
});

my $started_waitloop = time();
my $sleep_per_loop = 2;
my $loops = 0;
do {
  $loops++;
  sleep $sleep_per_loop;
} while (
  !$worker->is_joinable
    and
  ( ($loops * $sleep_per_loop) < ($ENV{AUTOMATED_TESTING} ? 120 : 10 ) )  # some smokers are *really* slow
);
my $waited_for = time - $started_waitloop;

if ($worker->is_joinable) {
  my $ret = $worker->join;
  undef $worker;
  is ($ret, 42, "$rerun_test in a thread completed successfully");
}
else {
  fail sprintf( 'Worker thread executing %s still not finished after %d seconds',
    $rerun_test,
    time - $started_waitloop,
  );
}

cmp_ok ($waited_for, '>', 0, 'Main thread slept for some time');
ok (
  # there should be less than a second of difference here
  ($waited_for - ($loops * $sleep_per_loop) < 1),
  "sleep in main thread appears undisturbed: $waited_for seconds after $loops loops of $sleep_per_loop secs"
);


done_testing;
