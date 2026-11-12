#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 4;

BEGIN {
	my @module = qw(
		RdKw::WwW::SiteConf
		RdKw::WwW::SiteConf::GMake
		RdKw::WwW::SiteConf::Make
		RdKw::WwW::SiteConf::Modifiers
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
diag( "Testing RdKw::WwW::SiteConf $RdKw::WwW::SiteConf::VERSION, Perl $], $^X" );
