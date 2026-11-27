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

BEGIN { use_ok('RdKw::WwW::SiteConf::Builder::Ninja') or BAIL_OUT; }
ok(eval { RdKw::WwW::SiteConf->VERSION(q(0.03_00)); 1; }, q(siteconf 0.03_00 or later))
	or diag($@);
diag( "Testing RdKw::WwW::SiteConf::Builder::Ninja $RdKw::WwW::SiteConf::Builder::Ninja::VERSION, Perl $], $^X" );
# (the program that t/e2e-ninja.t runs)
diag( describe(q(ninja ($NINJA)), ninja_cmd(), q(--version)) );
