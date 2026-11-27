#!perl
#
# t/just.t - JUST-NEED and JUST-WANT: a name whose header is not read

use utf8;
use 5.008;
use strict;
use warnings;
use Test::More tests => 19;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

use Cwd qw( getcwd );
use Encode ();
use File::Path qw( make_path );
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw( read_deps walk_deps read_manifest );

my $top = tempdir(CLEANUP => 1);
sub spew
{
	my ($name, $text) = @_;
	open my $fh, '>', $name or die "$name: $!";
	print $fh $text;
	close $fh or die;
}

# --- read_deps
spew("$top/h", "# HAVE: h\n# NEED: a\n# JUST-NEED: b c\n# WANT: d\n# JUST-WANT: e\n# just-need: f\n# NEED: g\n");
is_deeply({ read_deps("$top/h") }, {
	HAVE => 'h', NEED => [ qw( a g ) ], 'JUST-NEED' => [ qw( b c ) ],
	WANT => ['d'], 'JUST-WANT' => ['e'],
}, 'read_deps: JUST-NEED and JUST-WANT are fields (and a field in another case is not)');
spew("$top/only", "# JUST-WANT: z\nnot a header\n# NEED: late\n");
is_deeply({ read_deps("$top/only") }, { 'JUST-WANT' => ['z'] }, '... and they begin a header');
{
	my %L = (stale => 1);
	read_deps("$top/h", lines => \%L);
	is_deeply(\%L, {
		HAVE => 1, NEED => [ 2, 7 ], 'JUST-NEED' => [ 3, 3 ], WANT => [4], 'JUST-WANT' => [5],
	}, 'read_deps lines: the line of each name, in the shape of the result');
}

# --- walk_deps
chdir $top or die;
make_path("proj");
spew('proj/root', "# NEED: proj/a\n# WANT: proj/w\n# JUST-NEED: proj/j\n# JUST-WANT: proj/jw\n");
spew('proj/a', "# NEED: proj/leaf\n");
spew('proj/w', "# NEED: proj/wleaf\n");
spew('proj/j', "# NEED: proj/never\n");
spew('proj/jw', "# NEED: proj/never\n");
spew('proj/leaf', "plain\n");
spew('proj/wleaf', "plain\n");
spew('proj/never', "plain\n");
my %D = ( A => '.' );
sub walk { [ walk_deps(\%D, @_) ]; }

my $G = {};
is_deeply(walk('proj/root', { graph => $G }),
	[ qw( proj/root proj/a proj/leaf proj/j proj/w proj/wleaf proj/jw ) ],
	'walk_deps: all four are deps, and a JUST- has its header left alone');
ok(!exists $G->{'proj/j'} && !exists $G->{'proj/jw'}, '... and are not in the graph');
ok(exists $G->{'proj/a'} && exists $G->{'proj/w'}, '... but a NEED and a WANT are');

my $mandatory_graph = {};
is_deeply(walk('proj/root', { mandatory => 1, graph => $mandatory_graph }),
	[ qw( proj/root proj/a proj/leaf proj/j ) ],
	'mandatory => 1: skip WANT and JUST-WANT');
ok(!exists $mandatory_graph->{'proj/w'} && !exists $mandatory_graph->{'proj/jw'},
	'... and neither enters the graph');
is_deeply(walk('proj/root', { terminal => 1 }),
	[ qw( proj/leaf proj/j proj/wleaf proj/jw ) ],
	'terminal => 1: what has none of its own');
is_deeply(walk('proj/root', { terminal => 1, mandatory => 1, graph => $G }),
	[ qw( proj/leaf proj/j ) ],
	'terminal and mandatory: only required leaves, even with a cached graph');

# met as a JUST- first, a NEED later: it is read then
spew('proj/two', "# NEED: proj/via proj/j2\n");
spew('proj/via', "# JUST-NEED: proj/j2\n");
spew('proj/j2', "# NEED: proj/behind\n");
spew('proj/behind', "x\n");
is_deeply(walk('proj/two'), [ qw( proj/two proj/via proj/j2 proj/behind ) ],
	'a NEED expands a file already listed through JUST-NEED');
is_deeply(walk('proj/two', { terminal => 1 }), [ 'proj/behind' ], '... and is no leaf then');

# --- read_manifest
{
	my $t = Encode::encode('UTF-8', "MAKE christmas\n  WANT not-a-lot\n  JUST-NEED one-thing two\nJUST-WANT: three\nJUST-NEED:four\nNEED five\n");
	my $mf = read_manifest({}, \$t);
	is_deeply([ $mf->needed ], [ qw( one-thing two four five ) ], 'needed: JUST-NEED too');
	is_deeply([ $mf->wanted ], [ qw( not-a-lot three ) ], 'wanted: JUST-WANT too');
	is_deeply([ map { $_->{just} } @{ ($mf->goals)[0]{need} } ], [ 1, 1, 1, 0 ], 'which are said to be JUST');
	is_deeply([ map { $_->{just} } @{ ($mf->goals)[0]{want} } ], [ 0, 1 ], '... or not');
	$t = "MAKE a\nJUST-NEED\n";
	ok(!eval { read_manifest({}, \$t); 1; }, 'JUST-NEED of nothing: dies');
	like($@, qr/line 2: JUST-NEED takes a file/, '... says so');
	$t = "MAKE a\nJUST x\n";
	ok(!eval { read_manifest({}, \$t); 1; }, 'JUST alone is not a keyword');
}

chdir '/' or die;
done_testing;
