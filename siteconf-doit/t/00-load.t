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

BEGIN { use_ok('RdKw::WwW::SiteConf::Builder::Doit') or BAIL_OUT; }
ok(eval { RdKw::WwW::SiteConf->VERSION(q(0.03_00)); 1; }, q(siteconf 0.03_00 or later))
	or diag($@);
diag( "Testing RdKw::WwW::SiteConf::Builder::Doit $RdKw::WwW::SiteConf::Builder::Doit::VERSION, Perl $], $^X" );
# The program that t/e2e-doit.t runs:
diag( describe(q(doit ($PY_DOIT)), doit_cmd(), q(--version)) );
