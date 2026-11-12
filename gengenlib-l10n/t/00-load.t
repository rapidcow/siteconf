#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
	use_ok( 'RdKw::WwW::GenGenLib::L10N' ) or BAIL_OUT;
}
ok( defined $RdKw::WwW::GenGenLib::L10N::LOCALEDIR
	&& length $RdKw::WwW::GenGenLib::L10N::LOCALEDIR, 'LOCALEDIR is filled in' );
diag( "Testing RdKw::WwW::GenGenLib::L10N $RdKw::WwW::GenGenLib::L10N::VERSION,"
	. " LOCALEDIR $RdKw::WwW::GenGenLib::L10N::LOCALEDIR, Perl $], $^X" );
