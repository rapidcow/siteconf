#!perl
#
# t/00-load.t - basic load

use 5.006;
use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
	use_ok( 'RdKw::WwW::SiteConf::L10N' ) or BAIL_OUT;
}
ok( defined $RdKw::WwW::SiteConf::L10N::LOCALEDIR
	&& length $RdKw::WwW::SiteConf::L10N::LOCALEDIR, 'LOCALEDIR is filled in' );
diag( "Testing RdKw::WwW::SiteConf::L10N $RdKw::WwW::SiteConf::L10N::VERSION,"
	. " LOCALEDIR $RdKw::WwW::SiteConf::L10N::LOCALEDIR, Perl $], $^X" );
