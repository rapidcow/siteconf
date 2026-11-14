#!perl
#
# t/make.t - make file serialization and MY/*.mk state tests

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 13 + 22;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw(
	read_make write_make update_file
	escape_make unescape_make
	load_state
);

my $dir = tempdir(CLEANUP => 1);

# --- write_make / read_make / update_file
{
	my $f = "$dir/x.mk";
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'==', 2, 'write_make creates');
	is_deeply({ read_make($f) }, { b => 'site', aa => 'a b', c => 'é' },
		'read_make reads it back');
	like(do { open my $fh, '<', $f; local $/; <$fh> }, qr/^b=\tsite\nc=.*\naa=/m,
		'short keys first');

	# Preserve the mtime of an unchanged file.
	utime 1000000000, 1000000000, $f;
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'==', 0, 'unchanged');
	is((stat $f)[9], 1000000000, 'mtime kept');
	cmp_ok(write_make($f, { b => 'docs' }, 'test'),
		'==', 1, 'changed');
	ok(!-e "$dir/tmp-x.mk", 'no temporary left behind');
	ok(!eval { write_make($f, { 'a=b' => 1 }, 'test'); 1 }, 'bad name refused');
}

# --- values say what a line cannot hold
{
	my $f = "$dir/esc.mk";
	my %v = (
		plain  => 'site/blog',
		inner  => 'my dir/sub dir',          # one space between others is a space
		lead   => ' x',
		trail  => 'x ',
		run    => 'a  b',                   # ... two are not
		nl     => "a\nb",
		tab    => "a\tb",
		cr     => "a\rb",
		nbsp   => "a\x{A0}b",
		ideo   => "a\x{3000}b",
		bidi   => "a\x{202E}b",
		zwj    => "a\x{200D}b",
		ls     => "a\x{2028}b",
		kana   => 'ディレクトリ é',          # not white space: as it is
		dollar => 'a$b ${x} $',
		lit    => 'a${U+20}b ${$}',         # what looks like an escape, spelled out
		empty  => '',
	);
	cmp_ok(write_make($f, \%v, 'test'), '==', 2, 'write_make: any value');
	is_deeply({ read_make($f) }, \%v, 'read_make: all of them back');
	my $text = do { open my $fh, '<:encoding(UTF-8)', $f or die; local $/; <$fh> };
	my %line = $text =~ /^(\w+)=\t(.*)$/mg;
	is($line{inner}, 'my dir/sub dir', 'one space is a space');
	is($line{lead} . '|' . $line{trail}, '${U+0020}x|x${U+0020}', 'spaces at the ends are not');
	is($line{run}, 'a${U+0020}${U+0020}b', 'neither are two in a row');
	is($line{nl}, 'a${U+000A}b', 'a newline is a character');
	is($line{nbsp}, 'a${U+00A0}b', 'a no-break space too');
	is($line{bidi}, 'a${U+202E}b', 'bidi override too');
	is($line{kana}, 'ディレクトリ é', 'letters of any script are letters');
	is($line{dollar}, 'a$b ${$}{x} $', 'a $ is a $, but for one before a {');
	is($line{lit}, 'a${$}{U+20}b ${$}{$}', 'an escape that is not one is spelled out');
	is($text =~ tr/\n//, 3 + keys %v, 'a line for each, and no more');

	cmp_ok(write_make($f, \%v, 'test'), '==', 0, 'the same values, the same file');

	# written by hand: any case, any width
	open my $fh, '>:encoding(UTF-8)', $f or die;
	print $fh "a=\tx\${u+20}y\${U+00000041}\${\$}\n";
	close $fh;
	is_deeply({ read_make($f) }, { a => 'x yA$' }, 'read_make: u+, and leading zeros');

	open $fh, '>:encoding(UTF-8)', $f or die;
	print $fh "a=\tx\${U+110000}\n";
	close $fh;
	ok(!eval { read_make($f); 1 }, 'read_make: no such code point');
	like($@, qr/\Aread_make: .*\bline 1: bad escape \$\{U\+110000\}\n\z/, '... says where');
	ok(!eval { read_make($f, 'configure'); 1 }, 'read_make: ... and who we are');
	like($@, qr/\Aconfigure: /, '... as we are called');
	ok(!eval { read_make("$dir/nonesuch.mk", 'configure'); 1 }, 'read_make: no file');
}
is(escape_make(undef), '', 'escape_make: undef is empty');
is(unescape_make('a${U+0020}b${$}{x}'), 'a b${x}', 'unescape_make');
ok(!eval { unescape_make('${U+FFFFFFFF}'); 1 }, 'unescape_make: no such code point');

# --- load_state
{
	mkdir "$dir/MY" or die;
	ok(!eval { load_state($dir); 1 }, 'unconfigured');
	like($@, qr/not configured/, '... says so');
	write_make("$dir/MY/config.mk", { a => 'html' }, 't');
	write_make("$dir/MY/option.mk", { base_url => '/' }, 't');
	my ($D, $O) = @{+{ load_state($dir) }}{ qw(config option) };
	is($D->{a}, 'html', 'D from config.mk');
	is($O->{base_url}, '/', 'O from option.mk');
	ok(!exists $D->{base_url}, 'namespaces are separate');
}
