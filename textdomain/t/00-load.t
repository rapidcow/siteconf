#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 1;

BEGIN {
	require_ok( 'RdKw::L10N::TextDomain' ) or BAIL_OUT;
}
diag( "Testing RdKw::L10N::TextDomain $RdKw::L10N::TextDomain::VERSION, Perl $], $^X" );
