#!perl
#
# t/state.t - MY/*.mk, HAVE/NEED/WANT headers, base_url, TT2 stash

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 42;
use File::Temp qw( tempdir );

use RdKw::WwW::GenLib qw(
	read_make write_make update_file load_state
	read_deps parse_base locator location
);

my $dir = tempdir(CLEANUP => 1);
sub spew {
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
	print $fh $text;
	close $fh or die;
	"$dir/$name";
}

# --- write_make / read_make / update_file
{
	my $f = "$dir/x.mk";
	is(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'created', 'write_make creates');
	is_deeply({ read_make($f) }, { b => 'site', aa => 'a b', c => 'é' },
		'read_make reads it back');
	like(do { open my $fh, '<', $f; local $/; <$fh> }, qr/^b=\tsite\nc=.*\naa=/m,
		'short keys first');

	# Preserve the mtime of an unchanged file.
	utime 1000000000, 1000000000, $f;
	is(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'', 'unchanged');
	is((stat $f)[9], 1000000000, 'mtime kept');
	is(write_make($f, { b => 'docs' }, 'test'), 'updated', 'changed');
	ok(!-e "$dir/tmp-x.mk", 'no temporary left behind');
	ok(!eval { write_make($f, { k => "a\nb" }, 'test'); 1 }, 'newline refused');
	ok(!eval { write_make($f, { 'a=b' => 1 }, 'test'); 1 }, 'bad name refused');
}

# --- load_state
{
	mkdir "$dir/MY" or die;
	ok(!eval { load_state($dir); 1 }, 'unconfigured');
	like($@, qr/not configured/, '... says so');
	write_make("$dir/MY/config.mk", { a => 'html' }, 't');
	write_make("$dir/MY/option.mk", { base_url => '/' }, 't');
	my ($D, $O) = load_state($dir);
	is($D->{a}, 'html', 'D from config.mk');
	is($O->{base_url}, '/', 'O from option.mk');
	ok(!exists $D->{base_url}, 'namespaces are separate');
}

# --- read_deps
{
	my $f = spew('a.html', <<'HTML');
[%
# HAVE: index.html
# NEED: skel/HTML skel/FOOT
# WANT: data/x
# NEED: more
-%]
# NEED: ignored, this is body text
HTML
	is_deeply({ read_deps($f) }, {
		HAVE => 'index.html',
		NEED => [qw( skel/HTML skel/FOOT more )],
		WANT => [qw( data/x )],
	}, 'TT2 header');

	$f = spew('b.css', "/*\n * HAVE: b.css\n * NEED: c.css\n */\n");
	is_deeply({ read_deps($f) }, { HAVE => 'b.css', NEED => ['c.css'] },
		'C comment header (several lines)');

	$f = spew('c.bin', "binary\n" . ("x\n" x 40) . "# HAVE: too-late\n");
	is_deeply({ read_deps($f) }, {}, 'no header, no peeking far down');

	$f = spew('d', "# HAVE: a\n# HAVE: b\n");
	ok(!eval { read_deps($f); 1 }, 'two HAVEs');
	like($@, qr/HAVE too many/, '... too many');
}

# --- read_deps: BASIC and DOS
{
	for my $head ("REM HAVE: a\nREM NEED: b\n", "rem HAVE: a\nrem NEED: b\n",
		"\@REM HAVE: a\n\@REM NEED: b\n", ":: HAVE: a\n:: NEED: b\n",
		"' HAVE: a\n' NEED: b\n") {
		my $f = spew('rem', "\@echo off\n$head\necho hi\n");
		is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => ['b'] },
			'header in ' . (split ' ', $head)[0]);
	}
	my $f = spew('remark', "REMEMBER HAVE: a\n");
	is_deeply({ read_deps($f) }, {}, 'REM is a word');
}

# --- location
{
	my %D = (B => '.', b => 'site');
	is(location(\%D, 'site/a/b.html'), 'a/b.html', 'location, in-tree');
	%D = (B => 'build', b => 'site');
	is(location(\%D, 'build/site/a/b.html'), 'a/b.html', 'location, build dir');
	is(location(\%D, 'build//site/./a.html'), 'a.html', 'location, canonical');
	ok(!eval { location(\%D, 'site/a.html'); 1 }, 'location, not ours');
}

# --- parse_base
{
	my %O = (site_url => 'https://example.test/x?y#z', base_url => '/');
	ok(eval { parse_base(\%O); 1 }, 'inherits path') or diag $@;
	is($O{base_url}, '/x', 'base_url inherited');
	is($O{site_url}, 'https://example.test', 'site_url is host only');
	ok(!ref $O{site_url}, 'site_url is a plain string');

	%O = (site_url => 'https://example.test/x/', base_url => '/y/');
	ok(!eval { parse_base(\%O); 1 }, 'path in site_url vs. base_url');
	%O = (site_url => 'ftp://example.test');
	ok(!eval { parse_base(\%O); 1 }, 'scheme');
	%O = (base_url => '/');
	ok(!eval { parse_base(\%O); 1 }, 'missing site_url');
}

# --- locator
{
	my %O = (base_url => '/', site_url => 'https://example.test');
	my $l = locator(\%O, 'a/b.html');
	is($l->('c.html'), '../c.html', 'locate, relative');
	is($l->('/c.html'), '/c.html', 'locate, host-relative');
	is($l->('//c.html'), 'https://example.test/c.html', 'locate, absolute');
	is($l->('c/'), '../c/', 'nothing is done to the spec');
	ok(!eval { $l->(); 1 }, 'one argument');
	like($@, qr/usage: \[% locate PATH %\]/, '... says how');
}
