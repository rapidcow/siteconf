#!perl
#
# t/io.t - initstd, file names, arguments and the environment

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More tests => 40;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use File::Spec;

use RdKw::I18N::CodeSets;
my $CS = 'RdKw::I18N::CodeSets';

my $lat = $CS->new(filesys => 'latin1', argv => 'latin1', env => 'latin1');
my $asc = $CS->new(filesys => 'ascii', argv => 'ascii', env => 'ascii');

# --- to_fs, un_fs
is($lat->to_fs('résumé'), "r\xe9sum\xe9", 'to_fs: as filesys spells it');
is($lat->un_fs("r\xe9sum\xe9"), 'résumé', 'un_fs: and back');
my $bad = 'résumé';
ok(!eval { $asc->to_fs($bad, 'here'); 1 }, 'to_fs: cannot spell it');
is($@, qq{here: cannot encode "r\\x{e9}sum\\x{e9}" in US-ASCII\n}, '... and says who could not');
is($bad, 'résumé', '... leaving the name be');
ok(!eval { $asc->un_fs("\xe9"); 1 }, 'un_fs: cannot read it');
is($@, qq{cannot decode "\\x{e9}" in US-ASCII\n}, '... and says so');

# --- un_argv, to_argv
{
	my @args = ("r\xe9sum\xe9", 'x');
	is_deeply([ $lat->un_argv(@args) ], ['résumé', 'x'], 'un_argv: a list');
	is_deeply(\@args, ["r\xe9sum\xe9", 'x'], '... leaving it be');
	is_deeply([ $lat->to_argv('résumé', 'x') ], \@args, 'to_argv: and back');
	is(scalar $lat->un_argv("r\xe9sum\xe9", 'x'), 'résumé', 'un_argv: the first in scalar context');
	is(scalar $lat->to_argv("r\x{e9}sum\x{e9}", 'x'), "r\xe9sum\xe9", 'to_argv: the first in scalar context');
	is_deeply([ $lat->un_argv ], [], 'un_argv: nothing');
	ok(!eval { $asc->un_argv('x', @args); 1 }, 'un_argv: cannot read one');
	like($@, qr/\Acannot decode argv 1: .+\n\z/, '... says which, from 0');
	ok(!eval { $asc->un_argv(@args, { start => 1 }); 1 }, 'un_argv: start');
	like($@, qr/\Acannot decode argv 1: .+\n\z/, '... from there');
	ok(!eval { $asc->to_argv('é'); 1 }, 'to_argv: cannot spell one');
	like($@, qr/\Acannot encode argv 0: .+\n\z/, '... says which');
	ok(!eval { $lat->un_argv('x', { begin => 1 }); 1 }, 'un_argv: unknown option');
}

# --- decode_argv, encode_argv
{
	local @ARGV = ("r\xe9sum\xe9", 'x');
	is(scalar $lat->decode_argv, undef, 'decode_argv: returns nothing');
	is_deeply(\@ARGV, ['résumé', 'x'], '... in @ARGV');
	$lat->encode_argv;
	is_deeply(\@ARGV, ["r\xe9sum\xe9", 'x'], 'encode_argv: and back');
	ok(!eval { $asc->decode_argv; 1 }, 'decode_argv: cannot read one');
	like($@, qr/\Acannot decode argv 1: .+\n\z/, '... says which, from 1');
	is_deeply(\@ARGV, ["r\xe9sum\xe9", 'x'], '... leaving @ARGV be');
}

# --- getenv, setenv, unsetenv
{
	local %ENV = %ENV;
	delete @ENV{qw( CS_ONE CS_TWO )};
	is(scalar $lat->setenv(CS_ONE => 'é', "CS_\x{e9}" => 'x'), undef, 'setenv: returns nothing');
	is($ENV{CS_ONE}, "\xe9", '... spelled as env says');
	is($ENV{"CS_\xe9"}, 'x', '... names too');
	is_deeply([ $lat->getenv(qw( CS_ONE CS_TWO ), "CS_\x{e9}") ], ['é', undef, 'x'],
		'getenv: by names, undef if not set');
	is(scalar $lat->getenv(qw( CS_ONE CS_TWO )), 'é', '... the first in scalar context');
	ok(!eval { $asc->getenv('CS_ONE'); 1 }, 'getenv: cannot read it');
	like($@, qr/\Acannot decode environment variable "CS_ONE" in US-ASCII\n/, '... says so');
	ok(!eval { $asc->setenv(CS_TWO => 'ok', CS_THREE => 'é'); 1 }, 'setenv: cannot spell it');
	ok(!exists $ENV{CS_TWO}, '... setting none');
	$lat->setenv(CS_ONE => undef);
	ok(!exists $ENV{CS_ONE}, 'setenv: undef unsets');
	$lat->setenv(CS_TWO => 1);
	$lat->unsetenv('CS_TWO', "CS_\x{e9}");
	ok(!exists $ENV{CS_TWO} && !exists $ENV{"CS_\xe9"}, 'unsetenv');
}

# --- initstd, in a process of its own
{
	my $lib = File::Spec->rel2abs("$FindBin::Bin/../lib");
	my $prog = <<'EOP';
use RdKw::I18N::CodeSets;
my $cs = RdKw::I18N::CodeSets->new(stdout => 'latin1');
$cs->initstd for 1, 2;
print "\x{e9}";
$cs->initstd(stdout => Encode::FB_PERLQQ());
print "\x{263a}";
binmode STDOUT, ':raw';
print join ',', grep /encoding/, PerlIO::get_layers(STDERR);
EOP
	open my $fh, '-|', $^X, "-I$lib", '-e', $prog or die "cannot run $^X: $!";
	my $out = do { local $/; <$fh> };
	close $fh;
	is($?, 0, 'initstd: ran');
	like($out, qr/\A\xe9\\x\{263a\}/, 'initstd: once, however often, and with fallback');
	like($out, qr/encoding\(\Q@{[ Encode::find_encoding('console_out')->name ]}\E\)\z/,
		'... stderr as the locale says');
}
