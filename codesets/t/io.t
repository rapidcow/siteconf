#!perl
#
# t/io.t - initstd, reinitstd, file names, arguments and the environment

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More tests => 89;
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
ok(!eval { $asc->to_fs($bad, { prog => 'here' }); 1 }, 'to_fs: cannot spell it');
is($@, qq{here: cannot encode "r\\x{e9}sum\\x{e9}" in US-ASCII\n}, '... and says who could not');
is($bad, 'résumé', '... leaving the name be');
ok(!eval { $asc->un_fs("\xe9"); 1 }, 'un_fs: cannot read it');
is($@, qq{cannot decode "\\x{e9}" in US-ASCII\n}, '... and says so');
is_deeply([ $lat->to_fs('résumé', 'é') ], ["r\xe9sum\xe9", "\xe9"], 'to_fs: a list');
is_deeply([ $lat->un_fs("r\xe9sum\xe9", "\xe9") ], ['résumé', 'é'], 'un_fs: a list');
is(scalar $lat->un_fs("\xe9", 'x'), 'é', '... the first in scalar context');
is_deeply([ $lat->to_fs ], [], 'to_fs: nothing');
ok(!eval { $asc->to_fs('ok', 'é'); 1 }, 'to_fs: one cannot be spelled');
like($@, qr/\Acannot encode "\\x\{e9\}"/, '... says which');

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
	ok(!eval { $asc->un_argv(@args, { start => 1, prog => 'me' }); 1 }, 'un_argv: prog');
	like($@, qr/\Ame: cannot decode argv 1: .+\n\z/, '... says who first');
	ok(!eval { $asc->to_argv('é', { prog => 'me' }); 1 }, 'to_argv: prog');
	like($@, qr/\Ame: cannot encode argv 0: .+\n\z/, '... likewise');
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
	ok(!eval { $asc->decode_argv({ prog => 'me' }); 1 }, 'decode_argv: prog');
	like($@, qr/\Ame: cannot decode argv 1: .+\n\z/, '... says who first');
	$asc->decode_argv({ check => Encode::FB_DEFAULT() });
	is_deeply(\@ARGV, ["r\x{fffd}sum\x{fffd}", 'x'], 'decode_argv: check, as an option');
	ok(!eval { $asc->encode_argv({ prog => 'me' }); 1 }, 'encode_argv: prog');
	like($@, qr/\Ame: cannot encode argv 1: .+\n\z/, '... says who first');
	ok(!eval { $lat->decode_argv({ start => 2 }); 1 }, 'decode_argv: start is not ours to say');
}

# --- check: FB_CROAK, unless told otherwise
{
	my $s = "r\xe9";
	is(scalar $asc->un_argv($s, { check => Encode::FB_DEFAULT() }), "r\x{fffd}",
		'un_argv: check');
	is(scalar $asc->to_argv('é', { check => Encode::FB_PERLQQ() }), '\x{00e9}',
		'to_argv: check');
	ok(!eval { $asc->un_argv($s, { check => Encode::FB_QUIET() | Encode::DIE_ON_ERR() }); 1 },
		'un_argv: check without LEAVE_SRC');
	is($s, "r\xe9", '... leaving the source be all the same');
	scalar $asc->un_argv($s, { check => Encode::FB_QUIET() });
	is($s, "r\xe9", '... even if Encode would not');
	local @ARGV = ("r\xe9");
	$asc->decode_argv(Encode::FB_DEFAULT());
	is_deeply(\@ARGV, ["r\x{fffd}"], 'decode_argv: check');
	@ARGV = ('é');
	$asc->encode_argv(Encode::FB_PERLQQ());
	is_deeply(\@ARGV, ['\x{00e9}'], 'encode_argv: check');
	is($asc->un_fs("r\xe9", { check => Encode::FB_DEFAULT() }), "r\x{fffd}", 'un_fs: check');
	is($asc->to_fs('é', { prog => 'here', check => Encode::FB_PERLQQ() }), '\x{00e9}',
		'to_fs: check, with prog');
	ok(!eval { $asc->to_fs('é', { prog => 'here', check => Encode::FB_CROAK() }); 1 },
		'to_fs: FB_CROAK');
	like($@, qr/\Ahere: cannot encode/, '... still says who');
	ok(!eval { $asc->to_fs('é', { chekc => 0 }); 1 }, 'to_fs: unknown option');
	local %ENV = %ENV;
	$lat->setenv(CS_ONE => 'é');
	is(scalar $asc->getenv('CS_ONE', { check => Encode::FB_DEFAULT() }), "\x{fffd}",
		'getenv: check');
	$asc->setenv(CS_ONE => 'é', { check => Encode::FB_PERLQQ() });
	is($ENV{CS_ONE}, '\x{00e9}', 'setenv: check');
	ok(!eval { $asc->getenv('CS_é', { check => Encode::FB_DEFAULT() }); 1 },
		'getenv: names, never checked otherwise');
	ok(!eval { $asc->getenv('CS_é', { prog => 'me' }); 1 }, 'getenv: prog');
	like($@, qr/\Ame: cannot encode environment variable name /, '... says who first');
	$ENV{CS_TWO} = "\xe9";
	ok(!eval { $asc->getenv('CS_TWO', { prog => 'me' }); 1 }, '... for a value');
	like($@, qr/\Ame: cannot decode environment variable /, '... too');
	ok(!eval { $asc->setenv(CS_TWO => 'é', { prog => 'me' }); 1 }, 'setenv: prog');
	like($@, qr/\Ame: cannot encode the value of /, '... says who first');
	ok(!eval { $asc->unsetenv('CS_é', { prog => 'me' }); 1 }, 'unsetenv: prog');
	like($@, qr/\Ame: cannot encode environment variable name /, '... says who first');
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

# --- reinitstd, likewise: only the files it is given
{
	my $lib = File::Spec->rel2abs("$FindBin::Bin/../lib");
	my $prog = <<'EOP';
use RdKw::I18N::CodeSets;
my $cs = RdKw::I18N::CodeSets->new(stdout => 'latin1', stderr => 'latin1');
sub layers { join '+', grep /encoding/, PerlIO::get_layers($_[0]) }
my @r;
$cs->reinitstd;
push @r, 'none=' . layers(*STDOUT) . '/' . layers(*STDERR);
$cs->reinitstd(stdout => undef) for 1, 2;
push @r, 'stdout=' . layers(*STDOUT) . '/' . layers(*STDERR);
print "\x{e9}\n";
$cs->reinitstd(stdout => Encode::FB_PERLQQ());
print "\x{263a}\n";
$cs->stdout('ascii');
print "\x{e9}\n";
$cs->reinitstd(stdout => Encode::FB_PERLQQ());
print "\x{e9}\n";
push @r, 'bad=' . (eval { $cs->reinitstd(stdout => undef, stdfoo => undef, { prog => 'me' }); 1 } ? 'lived' : $@);
push @r, 'odd=' . (eval { $cs->reinitstd('stdout'); 1 } ? 'lived' : $@);
push @r, 'after=' . layers(*STDOUT) . '/' . layers(*STDERR);
binmode STDOUT, ':raw';
print "$_\n" for map { (my $r = $_) =~ s{\n\z}{}; $r } @r;
EOP
	open my $fh, '-|', $^X, "-I$lib", '-e', $prog or die "cannot run $^X: $!";
	my @out = <$fh>;
	close $fh;
	chomp @out;
	is($?, 0, 'reinitstd: ran');
	is($out[0], "\xe9", 'reinitstd: stdout as it is set');
	is($out[1], '\x{263a}', '... with fallback');
	is($out[2], "\xe9", '... a code set changed later is not used yet');
	is($out[3], '\x{00e9}', '... until it is told again');
	is($out[4], 'none=/', 'reinitstd: nothing given, nothing touched');
	is($out[5], 'stdout=encoding(iso-8859-1)/', '... stdout alone, once, however often');
	like($out[6], qr/\Abad=me: not a standard file: stdfoo at /, 'reinitstd: not a standard file');
	like($out[7], qr/\Aodd=reinitstd: odd number of arguments at /, 'reinitstd: odd number of arguments');
	is($out[8], 'after=encoding(ascii)/', '... leaving the files as they were');
}
