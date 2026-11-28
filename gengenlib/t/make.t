#!perl
#
# t/make.t - make file serialization and MY/*.mk state tests

use utf8;
use 5.006;
use strict;
use warnings;
use Test::More tests => 15 + 19 + 6;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw(
	read_make write_make write_file
	escape_vars unescape_vars
	load_state
);

my $dir = tempdir(CLEANUP => 1);

# --- write_make / read_make / write_file
{
	my $f = "$dir/x.mk";
	# (a file of that name is someone else's)
	open my $other, '>', "$dir/tmp-x.mk" or die $!;
	print $other "mine\n";
	close $other or die $!;
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, prog => 'test'),
		'==', 2, 'write_make creates');
	is_deeply({ read_make($f) }, { b => 'site', aa => 'a b', c => 'é' },
		'read_make reads it back');
	like(do { open my $fh, '<', $f; local $/; <$fh>; }, qr/^b=\tsite\nc=.*\naa=/m,
		'short keys first');

	# Preserve the mtime of an unchanged file.
	utime 1000000000, 1000000000, $f;
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, prog => 'test'),
		'==', 0, 'unchanged');
	is((stat $f)[9], 1000000000, 'mtime kept');
	cmp_ok(write_make($f, { b => 'docs' }, prog => 'test'),
		'==', 1, 'changed');
	opendir my $dh, $dir or die $!;
	is_deeply([sort grep { !/\A\.\.?\z/ } readdir $dh], ['tmp-x.mk', 'x.mk'], 'no temporary left behind');
	is(do { open my $fh, '<', "$dir/tmp-x.mk"; local $/; <$fh>; }, "mine\n", '... and tmp-x.mk is as it was');
	is((stat $f)[2] & 07777, 0666 & ~umask, '... and the mode is as umask says');
	ok(!eval { write_make($f, { 'a=b' => 1 }, prog => 'test'); 1; }, 'bad name refused');
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
	cmp_ok(write_make($f, \%v, prog => 'test'), '==', 2, 'write_make: any value');
	is_deeply({ read_make($f) }, \%v, 'read_make: all of them back');
	my $text = do { open my $fh, '<:encoding(UTF-8)', $f or die; local $/; <$fh>; };
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
	is($text =~ tr/\n//, keys %v, 'a line for each, and no more');

	cmp_ok(write_make($f, \%v, prog => 'test'), '==', 0, 'the same values, the same file');

	# written by hand: any case, any width
	open my $fh, '>:encoding(UTF-8)', $f or die;
	print $fh "a=\tx\${u+20}y\${U+00000041}\${\$}\n";
	close $fh;
	is_deeply({ read_make($f) }, { a => 'x yA$' }, 'read_make: u+, and leading zeros');

	open $fh, '>:encoding(UTF-8)', $f or die;
	print $fh "a=\tx\${U+110000}\n";
	close $fh;
	ok(eval { read_make($f); 1; }, 'read_make: pass through');
	ok(!eval { read_make("$dir/nonesuch.mk", prog => 'configure'); 1; }, 'read_make: no file');
}
is(escape_vars(undef), undef, 'escape_vars: undef is undef');
is(unescape_vars('a${U+0020}b${$}{x}'), 'a b${x}', 'unescape_vars');
ok(eval { unescape_vars('${U+FFFFFFFF}'); 1; }, 'unescape_vars: pass through');

# --- load_state
{
	mkdir "$dir/MY" or die;
	ok(!eval { load_state($dir); 1; }, 'unconfigured');
	like($@, qr/not configured/, '... says so');
	write_make("$dir/MY/config.mk", { a => 'html' }, prog => 't');
	write_make("$dir/MY/option.mk", { base_url => '/' }, prog => 't');
	my ($D, $O) = @{+{ load_state($dir) }}{ qw(config option) };
	is($D->{a}, 'html', 'D from config.mk');
	is($O->{base_url}, '/', 'O from option.mk');
	ok(!exists $D->{base_url}, 'namespaces are separate');
}

# --- flat options: prefixes, forwarding, and byte output
{
	ok(!eval { load_state("$dir/missing", prog => 'state-test'); 1; },
		'load_state: flat prog option');
	like($@, qr/^state-test:/, 'load_state: chosen prefix');
	my $f = "$dir/raw";
	cmp_ok(write_file($f, "\xFF", raw => 1, prog => 'raw-test'), '==', 2,
		'write_file: flat raw and prog options');
	open my $fh, '<:raw', $f or die $!;
	is(do { local $/; <$fh>; }, "\xFF", 'write_file: bytes unchanged');
	close $fh;
	ok(eval { load_state($dir, prog => 'state-test'); 1; },
		'load_state: flat options with configured state');
	ok(!eval { read_make("$dir/missing.mk", prog => 'read-test'); 1; }
		&& $@ =~ /^read-test:/, 'read_make: chosen prefix');
}
