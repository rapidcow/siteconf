#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More;

eval { require Template; 1 } or plan skip_all => 'Template is not installed';
plan tests => 1;
use_ok('RdKw::WwW::GenGenLib::Template::Provider') or BAIL_OUT;
diag( "Testing RdKw::WwW::GenGenLib::Template::Provider"
	. " $RdKw::WwW::GenGenLib::Template::Provider::VERSION, Perl $], $^X" );
