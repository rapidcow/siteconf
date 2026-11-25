#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe task_cmd );

BEGIN { use_ok('RdKw::WwW::SiteConf::Builder::Task') or BAIL_OUT }
is($RdKw::WwW::SiteConf::Builder::Task::VERSION, $RdKw::WwW::SiteConf::VERSION,
	'the version of siteconf');
diag( "Testing RdKw::WwW::SiteConf::Builder::Task $RdKw::WwW::SiteConf::Builder::Task::VERSION, Perl $], $^X" );
# (the program that t/e2e-task.t runs)
diag( describe(q(task ($GO_TASK)), task_cmd(), q(--version)) );
