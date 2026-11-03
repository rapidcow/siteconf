#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 3;

BEGIN {
	my @module = qw(
		RdKw::WwW::SiteConf
		RdKw::WwW::SiteConf::Make
		RdKw::WwW::SiteConf::Modifiers
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
