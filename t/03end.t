use warnings;
use strict;

use Test::More;
use Exception::Guaranteed;

use lib 't';
use __SelfDestruct;

my $dummy = 0;

my $err;
$SIG{__DIE__} = sub { $err = shift };

my $final_fn = __FILE__;
my $final_ln = __LINE__ + 1;
__SelfDestruct->spawn_n_kill( sub { guarantee_exception { die 'Final untrapped exception' } } );

while ($dummy < 2**31) {
  $dummy++;
}
fail ('Should never reach here :(');

END {
  diag( ($dummy||0) . " inc-ops executed before kill-signal delivery\n" );

  is (
    $err,
    "Final untrapped exception at $final_fn line $final_ln.\n",
    'Untrapped DESTROY exception correctly propagated',
  );

  my $ok;

  # on win32 the $? is *not* set to 255, not sure why :(
  if ($^O eq 'MSWin32') {
    cmp_ok ($?, '!=', 0, '$? correctly set to a non-0 value under windows' )
      and $ok = 1;
  }

  {
    local $TODO = 'Win32 buggery - $? is unstable for some reason'
      if $^O eq 'MSWin32';

    # check, and then change $? set by the last die
    is ($?, 255, '$? correctly set by untrapped die()')   # $? in END{} is *NOT* 16bit
      and $ok = 1;
  }

  $? = 0 if $ok; # adjust the exit to "passing" (0) IFF the test didn't fail

  done_testing;
}
