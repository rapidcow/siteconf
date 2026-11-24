#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe ninja_cmd );

BEGIN { use_ok('RdKw::WwW::SiteConf::Backend::Ninja') or BAIL_OUT }
is($RdKw::WwW::SiteConf::Backend::Ninja::VERSION, $RdKw::WwW::SiteConf::VERSION,
	'the version of siteconf');
diag( "Testing RdKw::WwW::SiteConf::Backend::Ninja $RdKw::WwW::SiteConf::Backend::Ninja::VERSION, Perl $], $^X" );
# (the program that t/e2e-ninja.t runs)
diag( describe(q(ninja ($NINJA)), ninja_cmd(), q(--version)) );
