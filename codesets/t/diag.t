#!perl
#
# t/diag.t - diag_mode, diag_name, diag

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More tests => 33;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

use RdKw::I18N::CodeSets;
my $CS = 'RdKw::I18N::CodeSets';

# --- diag_mode
{
	is($CS->new(stderr => 'UTF-8')->diag_mode, 'unicode', 'diag_mode: unicode by default');
	my $cs = $CS->new(stderr => 'US-ASCII');
	is($cs->diag_mode, 'ascii', '... ascii if stderr is');
	$cs->stderr('UTF-8');
	is($cs->diag_mode, 'unicode', '... as stderr is now');
	is($CS->new(stderr => 'ascii', diag => 'unicode')->diag_mode, 'unicode',
		'... unless set');
	is($CS->new(stderr => 'UTF-8', diag => 'ascii')->diag_mode, 'ascii', '... either way');
	ok(!eval { $CS->new(diag => 'UTF-8'); 1 }, 'diag_mode: unicode or ascii');
	like($@, qr/\Aunknown diag mode "UTF-8"/, '... says so');
}

# (stderr as it would be, whatever the locale is)
my $u = $CS->new(stderr => 'UTF-8', diag => 'unicode');
my $a = $CS->new(stderr => 'UTF-8', diag => 'ascii');

# --- diag_name
is($u->diag_name('a.png'), "`a.png'", 'diag_name: printable ASCII');
is($a->diag_name('a b.png'), "`a b.png'", '... with a space');
is($a->diag_name("it's.png"), q{"it's.png"}, 'diag_name: a quote is no printable ASCII');
is($u->diag_name("it's.png"), q{"it's.png"}, '... unicode, the same');
is($a->diag_name("`a'"), q{"`a'"}, '... nor a backquote');
is($u->diag_name("`a'"), q{"`a'"}, '... unicode, the same');
is($u->diag_name("炒饭's"), q{"炒饭's"}, '... with what is not ASCII');
is($u->diag_name("\x89PNG\r\n\x1a\n"), '"\x{89}PNG\r\n\x{1a}\n"', 'diag_name: unicode, controls');
is($a->diag_name("\x89PNG\r\n\x1a\n"), '"\x{89}PNG\r\n\x{1a}\n"', '... ascii, the same');
is($u->diag_name('炒饭.png'), '"炒饭.png"', 'diag_name: unicode, as it is');
is($a->diag_name('炒饭.png'), '"\x{7092}\x{996d}.png"', '... ascii, escaped');
is($u->diag_name("炒饭\x{a0}pic.png\r\n"), '"炒饭\x{a0}pic.png\r\n"',
	'diag_name: unicode, but for what would not show');
is($u->diag_name("\x{2028}\x{200b}\x{d800}\x{3000}"), '"\x{2028}\x{200b}\x{d800}\x{3000}"',
	'... separators, formats, surrogates');
is($u->diag_name("é \$x \@y \"\\"), '"é \$x \@y \"\\\\"', '... a Perl string all the same');
is($u->diag_name(undef), 'undef', 'diag_name: undef');

# --- diag
is($a->diag("cannot open file %q: %s\n", "炒饭", "No such file"),
	qq{cannot open file "\\x{7092}\\x{996d}": No such file\n}, 'diag: %q and %s');
is($u->diag('100%% %q', 'a'), "100% `a'", 'diag: %%');
is($a->diag('no %q', "a'b"), q{no "a'b"}, 'diag: %q of a quote');
ok(!eval { $u->diag('%d', 1); 1 }, 'diag: no other conversion');
ok(!eval { $u->diag('%q'); 1 }, 'diag: no missing argument');

# --- what stderr cannot spell
{
	my $l = $CS->new(stderr => 'latin1');
	is($l->diag_mode, 'unicode', 'latin1 stderr: unicode');
	is($l->diag_name("é炒饭"), '"é\x{7092}\x{996d}"', 'diag_name: escaped if stderr cannot');
	is($l->diag("%s: café 炒饭 %q\n", "炒", "é"),
		qq{\\x{7092}: café \\x{7092}\\x{996d} "é"\n}, 'diag: format and %s, escaped if stderr cannot');
	my $x = $CS->new(stderr => 'ascii');
	is($x->diag("无法打开文件 %q：%s", "nopeé", "x"),
		'\x{65e0}\x{6cd5}\x{6253}\x{5f00}\x{6587}\x{4ef6} "nope\x{e9}"\x{ff1a}x',
		'diag: ascii stderr');
	is($u->diag("无法打开文件 %q：%s", "炒饭", "é"), '无法打开文件 "炒饭"：é',
		'diag: UTF-8 stderr, as it is');
	is($a->diag("无法打开文件 %q", "炒饭"), '无法打开文件 "\x{7092}\x{996d}"',
		'diag: ascii mode is for names only');
}
