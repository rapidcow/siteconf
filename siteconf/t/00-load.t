#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 5;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe make_cmd bmake_cmd gmake_since );

BEGIN {
	my @module = qw(
		RdKw::WwW::SiteConf
		RdKw::WwW::SiteConf::Backend::Bmake
		RdKw::WwW::SiteConf::Backend::Gmake
		RdKw::WwW::SiteConf::Backend::Make
		RdKw::WwW::SiteConf::Modifiers
	);
	foreach my $module (@module) {
		use_ok( $module ) or BAIL_OUT;
	}
}
diag( "Testing RdKw::WwW::SiteConf $RdKw::WwW::SiteConf::VERSION, Perl $], $^X" );
# (the programs that t/e2e-*.t run)
diag( describe(q(make ($MAKE)), make_cmd()) );
diag( describe(q(bmake ($BMAKE)), bmake_cmd()) );
diag( describe(q(GNU make ($GMAKE, gmake, make)), gmake_since(3, 81), q(--version)) );
