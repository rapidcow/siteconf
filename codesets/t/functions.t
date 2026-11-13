#!perl
#
# t/functions.t - RdKw::I18N::CodeSets::Functions

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More tests => 14;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

use RdKw::I18N::CodeSets;
use RdKw::I18N::CodeSets::Functions qw( :all );
my $CS = 'RdKw::I18N::CodeSets';

local $RdKw::I18N::CodeSets::LOCALE = $CS->new(
	stderr => 'UTF-8', diag => 'ascii',
	filesys => 'latin1', argv => 'latin1', env => 'latin1',
);

is(to_fs('résumé'), "r\xe9sum\xe9", 'to_fs: by the locale');
is(un_fs("r\xe9sum\xe9"), 'résumé', 'un_fs: and back');
is_deeply([ un_fs("\xe9", "x") ], ['é', 'x'], '... a list');
is(scalar un_fs("\xe9", "x"), 'é', '... the first in scalar context');
is(to_argv('é'), "\xe9", 'to_argv');
is(un_argv("\xe9"), 'é', 'un_argv');
{
	local @ARGV = ("\xe9");
	decode_argv();
	is_deeply(\@ARGV, ['é'], 'decode_argv');
	encode_argv();
	is_deeply(\@ARGV, ["\xe9"], 'encode_argv');
}
setenv(CODESETS_FUNCTIONS_T => 'é');
is($ENV{CODESETS_FUNCTIONS_T}, "\xe9", 'setenv');
is(getenv('CODESETS_FUNCTIONS_T'), 'é', 'getenv');
unsetenv('CODESETS_FUNCTIONS_T');
ok(!exists $ENV{CODESETS_FUNCTIONS_T}, 'unsetenv');
is(diag('%q', '炒饭'), '"\x{7092}\x{996d}"', 'diag: by the locale');
is(diag_name('a.png'), "`a.png'", 'diag_name');
{
	$! = 2;
	my $m = diag('%m');
	is($m, $CS->locale->diag('%m'), 'diag: %m is $! as we got it');
}
