#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe redo_cmd );

BEGIN { use_ok('RdKw::WwW::SiteConf::Backend::Redo') or BAIL_OUT }
is($RdKw::WwW::SiteConf::Backend::Redo::VERSION, $RdKw::WwW::SiteConf::VERSION,
	'the version of siteconf');
diag( "Testing RdKw::WwW::SiteConf::Backend::Redo $RdKw::WwW::SiteConf::Backend::Redo::VERSION, Perl $], $^X" );
# (the programs that t/e2e-redo.t runs: redo, and what a .do runs)
diag( describe(q(redo ($REDO)), redo_cmd()) );
diag( describe(q(redo-ifchange ($PATH)), q(redo-ifchange)) );
