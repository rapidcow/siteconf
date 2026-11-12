#!perl
#
# t/manifest.t - read_manifest

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More tests => 60;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use Encode ();
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw( read_manifest escape_dep );

# (the text as it is in a file: UTF-8)
sub parse { my $t = Encode::encode('UTF-8', shift); read_manifest(\$t) }

my $mf = parse(<<'M');
# comment

MAKE goal
  NEED sunshine  # trailing comment
	NEED  rainbow
	WANT disco_ball
MAKE other
MAKE third
WANT sunshine
    NEED a/b.c
M
isa_ok($mf, 'RdKw::WwW::GenGenLib::Manifest');
is($mf->file, 'MANIFEST', 'a scalar reference is MANIFEST');
is(scalar $mf->target, 'goal', 'target: the default, in scalar context');
is($mf->default_target, 'goal', 'default_target');
is_deeply([ $mf->target ], [qw( goal other third )], 'target: all, in list context');
is_deeply([ $mf->targets ], [qw( goal other third )], 'targets');
is(scalar $mf->targets, 3, '... (how many, in scalar context)');
is_deeply([ $mf->needed ], [qw( sunshine rainbow )], 'needed: of the default');
is_deeply([ $mf->wanted ], ['disco_ball'], 'wanted: of the default');
is_deeply([ $mf->needed('other') ], [], 'needed: of a goal with none');
is_deeply([ $mf->needed('third') ], ['a/b.c'], 'NEED after WANT');
is_deeply([ $mf->wanted('third') ], ['sunshine'], 'WANT');
is_deeply([ map $mf->needed($_), $mf->target ], [qw( sunshine rainbow a/b.c )], 'all NEEDs');
is_deeply([ map $mf->wanted($_), $mf->target ], [qw( disco_ball sunshine )], 'all WANTs');
ok(!eval { $mf->needed('nope'); 1 }, 'needed: no such goal');
like($@, qr/\Aread_manifest: `MANIFEST': no goal `nope'$/, '... says so');

my @g = $mf->goals;
is_deeply($g[0], { name => 'goal', line => 3,
	need => [ { file => 'sunshine', line => 4 }, { file => 'rainbow', line => 5 } ],
	want => [ { file => 'disco_ball', line => 6 } ] }, 'goals: with their lines');
push @{ $g[0]{need} }, { file => 'x', line => 0 };
$g[0]{need}[0]{file} = 'y';
is_deeply([ $mf->needed ], [qw( sunshine rainbow )], '... which are copies');

# --- escapes: what escape_dep writes, we read
{
	my @name = ( 'a b', "tab\there", 'hash#tag', 'semi;colon', 'dollar$sign',
		'50%', 'brace{}', 'ünïcödé', "no\x{a0}break", 'x:y', '"quoted"' );
	my $text = "MAKE all\n" . join '', map { "\tNEED " . escape_dep($_) . "\n" } @name;
	is_deeply([ parse($text)->needed ], \@name, 'escape_dep round-trips');
	$text = "MAKE all\n" . join '', map { "\tNEED " . escape_dep($_, unicode => 1) . "\n" } @name;
	is_deeply([ parse($text)->needed ], \@name, '... with unicode => 1 too');
}
is_deeply([ parse("MAKE all\nNEED a\${U+0023}b # c\n")->needed ], ['a#b'], 'an escaped # is no comment');
is_deeply([ parse("MAKE all\nNEED \$\$x\nNEED \${\$}y\n")->needed ], ['$x', '$y'], '$$ and ${$}');
is_deeply([ parse("MAKE all\nNEED \${U+e9}t\x{e9}\n")->needed ], ["\x{e9}t\x{e9}"], 'any case, any length');
is_deeply([ parse("MAKE all\nNEED \${A}/x\n")->needed ], ['x'], '${A}/ is the root');
is_deeply([ parse("MAKE all\nNEED résumé\x{a0}x\n")->needed ], ["résumé\x{a0}x"],
	'not ASCII, and a no-break space is no blank');
is_deeply([ parse("MAKE all\r\nNEED a\r\n")->needed ], ['a'], 'CRLF');

sub bad {
	my ($text, $re, $what) = @_;
	ok(!eval { parse($text); 1 }, "$what: dies");
	like($@, $re, "$what: says why");
}
bad("NEED x\n", qr/\Aread_manifest: `MANIFEST' line 1: NEED before any MAKE$/, 'orphan');
bad("MAKE a\nNEED x y\n", qr/line 2: NEED takes exactly one file/, 'two files');
bad("MAKE a\nNEED x\cKy\n", qr/exactly one file/, 'vertical tab is a blank');
bad("MAKE a\nMAKE a\n", qr/line 2: goal `a' is already made/, 'duplicate goal');
bad("MAKE\n", qr/exactly one goal/, 'nameless goal');
bad("MAKE a\${U+0020}b\n", qr/bad goal name/, 'goal names are not unescaped');
bad("FROB x\n", qr/expected MAKE, NEED or WANT, not `FROB'/, 'unknown keyword');
bad("# nothing\n", qr/\Aread_manifest: `MANIFEST': no goals/, 'empty');
bad("MAKE a\nNEED a\$b\n", qr/line 2: bad substitution: \$\{b\}$/, 'a variable');
bad("MAKE a\nNEED \${a}/x\n", qr/bad substitution: \$\{a\}/, '... even a well-known one');
bad("MAKE a\nNEED a\$\n", qr/line 2: trailing \$/, 'a stray $');
bad("MAKE a\nNEED \${U+110000}\n", qr/no code point/, 'no code point');
bad("MAKE a\nNEED \${A}\n", qr/`\$\{A\}' is no name/, 'the root alone');
bad("MAKE a\nNEED x\${U+0000}\n", qr/has a NUL/, 'NUL');
{
	my $t = "MAKE a\nNEED \xff\n";
	ok(!eval { read_manifest(\$t); 1 }, 'not UTF-8: dies');
	like($@, qr/line 2: not UTF-8/, 'not UTF-8: says why');
}

# --- a file, by its name
{
	my $dir = tempdir(CLEANUP => 1);
	open my $fh, '>', "$dir/MANIFEST" or die;
	print $fh "MAKE all\n\tNEED x\n";
	close $fh or die;
	my $mf = read_manifest("$dir/MANIFEST");
	is($mf->file, "$dir/MANIFEST", 'file: as it was named');
	is_deeply([ $mf->needed ], ['x'], 'read from a file');
	ok(!eval { read_manifest("$dir/nope"); 1 }, 'missing: dies');
	like($@, qr/\Aread_manifest: cannot open file `\Q$dir\E\/nope': /, 'missing: says why');
}
