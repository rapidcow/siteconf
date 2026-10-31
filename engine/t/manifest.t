#!perl
#
# t/manifest.t - the MANIFEST format

use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
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
bad("MAKE a\nNEED ../x\n", qr/climbs out/, 'dotdot');
bad("MAKE a\nNEED a\$b\n", qr/bad file name/, 'dollar');
bad("MAKE a\nMAKE a\n", qr/already made/, 'duplicate goal');
bad("MAKE clean\n", qr/reserved/, 'reserved goal');
bad("MAKE\n", qr/exactly one goal/, 'nameless goal');
bad("FROB x\n", qr/expected MAKE/, 'unknown keyword');
bad("# nothing\n", qr/no goals/, 'empty');

done_testing;
