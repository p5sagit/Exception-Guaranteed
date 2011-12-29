use warnings;
use strict;

use 5.006;

use inc::Module::Install '1.01';

perl_version '5.006';

test_requires 'Test::More'      => '0.92';
test_requires 'Time::HiRes'     => '0';

all_from 'lib/Exception/Guaranteed.pm';

homepage 'http://git.shadowcat.co.uk/gitweb/gitweb.cgi?p=p5sagit/Exception-Guaranteed.git';
resources 'IRC'         => 'irc://irc.perl.org/#pp';
resources 'license'     => 'http://dev.perl.org/licenses/';
resources 'repository'  => 'git://git.shadowcat.co.uk/p5sagit/Exception-Guaranteed.git';
resources 'bugtracker'  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Exception-Guaranteed';

WriteAll;
