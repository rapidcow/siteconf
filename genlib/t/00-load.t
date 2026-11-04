#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 1;

BEGIN {
	my @module = qw(
		RdKw::WwW::GenLib
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
diag( "Testing RdKw::WwW::GenLib $RdKw::WwW::GenLib::VERSION, Perl $], $^X" );
