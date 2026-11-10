#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 1;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

BEGIN {
	my @module = qw(
		RdKw::WwW::GenGenLib
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
diag( "Testing RdKw::WwW::GenGenLib $RdKw::WwW::GenGenLib::VERSION, Perl $], $^X" );
