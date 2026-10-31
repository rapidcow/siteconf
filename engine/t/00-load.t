#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
	my @module = qw(
		RdKw::WwW::SiteConf
		RdKw::WwW::SiteConf::Make
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
