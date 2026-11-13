#!perl
#
# t/manifest.t - the MANIFEST format

use strict;
use warnings;
use Test::More tests => 40;
use File::Temp qw( tempdir );
# (what is said is said as it is written, whatever the locale)
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::SiteConf;

# read_manifest does not look at the configuration; fake an object.
my $sc = bless {}, 'RdKw::WwW::SiteConf';
sub parse { my $t = shift; $sc->read_manifest(\$t) }
sub files { [ map { $_->{file} } @{ $_[0] } ] }

my @g = parse(<<'M');
# comment

MAKE all
  NEED file1  # trailing comment
	NEED  file2
MAKE small-subset
WANT file1
    NEED a/b.c
M
is(scalar @g, 2, 'two goals');
is($g[0]{name}, 'all', 'name');
is_deeply(files($g[0]{need}), [qw( file1 file2 )], 'indentation is only for the eyes');
is_deeply(files($g[1]{want}), ['file1'], 'WANT');
is_deeply(files($g[1]{need}), ['a/b.c'], 'NEED after WANT');
is($g[0]{need}[1]{line}, 5, 'line numbers kept');

sub bad {
	my ($text, $re, $what) = @_;
	ok(!eval { parse($text); 1 }, "$what: dies");
	like($@, $re, "$what: says why");
}
bad("NEED x\n", qr/NEED before any MAKE/, 'orphan');
bad("MAKE a\nNEED x y\n", qr/exactly one file/, 'two files (old format?)');
bad("MAKE a\nNEED x\tdescription\n", qr/exactly one file/, 'description');
bad("MAKE a\nNEED /etc/passwd\n", qr/must be relative/, 'absolute');
bad("MAKE a\nNEED ../x\n", qr/out of tree/, 'dotdot');
# Accept either quoting style in the error returned by GenGenLib.
bad("MAKE a\nNEED a\$b\n", qr/\AE: (?:MANIFEST|`MANIFEST') line 2: bad substitution: \$\{b\}$/, 'a variable');
bad("MAKE a\nNEED a\${\$}b\n", qr/line 2: bad file name `a\$b'/, 'an escaped $, unescaped');
@g = parse("MAKE a\nNEED a\${U+0020}b\nWANT c\${U+20}d\n");
is_deeply(files($g[0]{need}), ['a b'], 'an escaped blank in NEED');
is_deeply(files($g[0]{want}), ['c d'], 'a short escaped blank in WANT');
bad("MAKE a\nNEED \${U+002E}\${U+002E}/x\n", qr/out of tree/, 'an escaped ..');
bad("MAKE a\nWANT ok\nNEED x\nWANT /y\nNEED ../z\n", qr/line 4: .*must be relative/,
	'in the order it is said');
bad("MAKE a\nNEED ok\nMAKE Makefile\n", qr/line 3: `Makefile' is a reserved/,
	'reserved, with its line');
bad("MAKE a\nMAKE a\n", qr/already made/, 'duplicate goal');
bad("MAKE clean\n", qr/reserved/, 'reserved goal');
bad("MAKE\n", qr/exactly one goal/, 'nameless goal');
bad("FROB x\n", qr/expected MAKE/, 'unknown keyword');
bad("# nothing\n", qr/no goals/, 'empty');

# Names are unescaped (by GenGenLib) before anything else looks at them
@g = parse("MAKE all\n\tNEED \${A}/x\${U+002E}html\n\tWANT r\${U+00E9}sum\${U+00E9}.html\n");
is_deeply(files($g[0]{need}), ['x.html'], 'escapes: ${U+...} and ${A}/');
is_deeply(files($g[0]{want}), ["r\x{e9}sum\x{e9}.html"], '... to what is not ASCII');
