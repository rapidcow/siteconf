#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe doit_cmd );

BEGIN { use_ok('RdKw::WwW::SiteConf::Backend::Doit') or BAIL_OUT }
is($RdKw::WwW::SiteConf::Backend::Doit::VERSION, $RdKw::WwW::SiteConf::VERSION,
	'the version of siteconf');
diag( "Testing RdKw::WwW::SiteConf::Backend::Doit $RdKw::WwW::SiteConf::Backend::Doit::VERSION, Perl $], $^X" );
# (the program that t/e2e-doit.t runs)
diag( describe(q(doit), doit_cmd(), q(--version)) );
