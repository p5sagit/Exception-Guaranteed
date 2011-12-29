package Exception::Guaranteed;

use warnings;
use strict;

our $VERSION = '0.00_06';
$VERSION = eval $VERSION if $VERSION =~ /_/;

use Config;
use Carp qw/croak cluck/;

use base 'Exporter';
our @EXPORT = ('guarantee_exception');
our @EXPORT_OK = ('guarantee_exception');

# this is the minimum acceptable threads.pm version, before it
# inter-thread signalling may not work right (or is totally missing)
use constant THREADS_MIN_VERSION => '1.39';

# older perls segfault if the cref behind the goto throws
# Perl RT#35878
use constant BROKEN_GOTO => ($] < 5.008_008_1);

# kill (and signaling) plain doesn't work on win32 (works on cygwin though)
use constant RUNNING_IN_HELL => ($^O eq 'MSWin32');

# perls up until 5.12 (inclusive) seem to be happy with self-signaling
# newer ones however segfault, so we resort to a killer sentinel fork
use constant BROKEN_SELF_SIGNAL => (!RUNNING_IN_HELL and $] > 5.012_9);

# win32 can only simulate signals with threads - off we go
# loading them as early as we can
if (RUNNING_IN_HELL) {
  require threads;
  threads->import;
}
elsif (BROKEN_SELF_SIGNAL) {
  require POSIX;  # for POSIX::_exit below
}

# fail early
if ($INC{'threads.pm'} and ! eval { threads->VERSION(THREADS_MIN_VERSION) }) {
  die "At least threads @{[THREADS_MIN_VERSION]} is required in a threaded environment\n";
}

=head1 NAME

Exception::Guaranteed - Throw exceptions from anywhere - including DESTROY callbacks

=head1 DESCRIPTION

TODO

=cut

my $in_global_destroy;
END { $in_global_destroy = 1 }

# sig-to-number
my $sigs = do {
  my $s;
  for (split /\s/, $Config{sig_name}) {
    $s->{$_} = scalar keys %$s;
  }

  # we do not allow use of these signals
  delete @{$s}{qw/ZERO ALRM KILL SEGV ILL BUS CHLD/};
  $s;
};

# not a plain sub declaration - we want to inline as much
# as possible into the signal handler when we create it
# without having to do any extra ENTERSUBs
my $in_destroy_eval_src = <<'EOS';
do {
  if (defined $^S and !$^S) {
    0;
  }
  else {
    # we can always skip the first 2 frames because we are called either
    # from the __in_destroy_eval sub generated below whic is called by guarantee_exception
    # OR
    # we are called from a signal handler where the first 2 frames are the SIG and an eval
    my ($f, $r) = 2;
    while (my $called_sub = (caller($f++))[3] ) {
      if ($called_sub eq '(eval)') {
        last
      }
      elsif ($called_sub =~ /::DESTROY$/) {
        $r = 1;
      }
    }

    $r;
  }
}
EOS

# we also call it externally, so declare a plain sub as well
eval "sub __in_destroy_eval { $in_destroy_eval_src }";


my $guarantee_state = {};
sub guarantee_exception (&;@) {
  my ($cref, $signame) = @_;

  # use SIGABRT unless asked otherwise (available on all OSes afaict)
  $signame ||= 'ABRT';

  # because throwing any exceptions here is a delicate thing, we make the
  # exception text and then try real hard to throw when it's safest to do so
  my $sigwrong = do {sprintf
    "The requested signal '%s' is not valid on this system, use one of %s",
    $_[0],
    join ', ', map { "'$_'" } sort { $sigs->{$a} <=> $sigs->{$b} } keys %$sigs
  } if (! defined $sigs->{$signame} );

  croak $sigwrong if ( defined $^S and !$^S and $sigwrong );

  if (
    $in_global_destroy
      or
    $guarantee_state->{nested}
  ) {
    croak $sigwrong if $sigwrong;

    return $cref->() if BROKEN_GOTO;

    @_ = (); goto $cref;
  }

  local $guarantee_state->{nested} = 1;

  my (@result, $err);
  {
    local $@; # not sure this localization is necessary
    eval {
      croak $sigwrong if $sigwrong;

      {
        my $orig_sigwarn = $SIG{__WARN__} || sub { CORE::warn $_[0] };
        local $SIG{__WARN__} = sub { $orig_sigwarn->(@_) unless $_[0] =~ /^\t\Q(in cleanup)/ };

        my $orig_sigdie = $SIG{__DIE__} || sub {};
        local $SIG{__DIE__} = sub { ($err) = @_; $orig_sigdie->(@_) };

        if (!defined wantarray) {
          $cref->();
        }
        elsif (wantarray) {
          @result = $cref->();
        }
        else {
          $result[0] = $cref->();
        }
      }

      # a DESTROY-originating exception will not stop execution, but will still
      # land the error into $SIG{__DIE__} which places it in $err
      die $err if defined $err;

      1;
    } and return ( wantarray ? @result : $result[0] );  # return on successfull eval{}
  }

### if we got this far - the eval above failed
### just plain die if we can
  die $err unless __in_destroy_eval();

### we are in a destroy eval, can't just throw
### prepare the ninja-wizard exception guarantor
  if ($sigwrong) {
    cluck "Unable to set exception guarantor - invalid signal '$signame' requested. Proceeding in undefined state...";
    die $err;
  }

  my $use_threads = (
    RUNNING_IN_HELL
      or
    ($INC{'threads.pm'} and threads->tid != 0)
  );
  if ($use_threads and ! eval { threads->VERSION(THREADS_MIN_VERSION) } ) {
    cluck "Unable to set exception guarantor thread - minimum of threads @{[THREADS_MIN_VERSION()]} required. Proceeding in undefined state...";
    die $err;
  }

  # non-localized, restorable from within the callback
  my $orig_handlers = {
    $signame => $SIG{$signame},
    BROKEN_SELF_SIGNAL ? ( CHLD => $SIG{CHLD} ) : (),
  };

  # use a string eval, minimize time spent in the handler
  # the longer we are here, the further the main thread/fork will
  # drift down its op-tree
  my $sig_handler = $SIG{$signame} = eval( sprintf
    q|sub {
      if (%s) {
        %s
      }
      else {
        for (keys %%$orig_handlers) { # sprintf hence the %%
          if (defined $orig_handlers->{$_}) {
            $SIG{$_} = $orig_handlers->{$_};
          }
          else {
            delete $SIG{$_};
          }
        }
        die $err;
      }
    }|,

    $in_destroy_eval_src,

    $use_threads        ? __gen_killer_src_threads ($sigs->{$signame}, $$) :
    BROKEN_SELF_SIGNAL  ? __gen_killer_src_sentinel ($sigs->{$signame}, $$) :
                          __gen_killer_src_selfsig ($sigs->{$signame}, $$)
  ) or warn "Coderef fail!\n$@";

  # start the kill-loop
  $sig_handler->();
}


sub __gen_killer_src_threads {
  return sprintf <<'EOH', $_[0];

  threads->create(
    sub { $_[0]->kill(%d) },
    threads->self
  )->detach;
EOH
}

sub __gen_killer_src_sentinel {
  sprintf <<'EOH', $_[0], $_[1];

    # the SIGCHLD handling is taken care of at the callsite
    my $killer_pid = fork();
    if (! defined $killer_pid) {
      die "Unable to fork ($!) while trying to guarantee the following exception:\n$err";
    }
    elsif (!$killer_pid) {
      kill (%d, %d);
      POSIX::_exit(0);
    }

EOH
}

sub __gen_killer_src_selfsig {
  "kill( $_[0], $_[1] );"
}

=head1 AUTHOR

ribasushi: Peter Rabbitson <ribasushi@cpan.org>

=head1 CONTRIBUTORS

None as of yet

=head1 COPYRIGHT

Copyright (c) 2011 the Exception::Guaranteed L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut

1;

1;
