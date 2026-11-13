#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

BEGIN {
	use_ok( 'RdKw::I18N::CodeSets' ) or BAIL_OUT;
	use_ok( 'RdKw::I18N::CodeSets::Functions' ) or BAIL_OUT;
}
diag( "Testing RdKw::I18N::CodeSets $RdKw::I18N::CodeSets::VERSION, Perl $], $^X" );
