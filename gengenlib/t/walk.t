#!perl
#
# t/walk.t - split_dep, walk_deps, and what must never be read

use 5.006;
use strict;
use warnings;
use Test::More tests => 71;
use File::Temp qw( tempdir );
use File::Path qw( make_path );
use Cwd qw( getcwd );

use RdKw::WwW::GenGenLib qw( split_dep walk_deps follow_ok norm_deps );

# --- split_dep (no side effects; no warnings)
{
	my @warn;
	local $SIG{__WARN__} = sub { push @warn, @_ };
	my %want = (
		'temple/x'                 => [ '', 'temple/x' ],
		'${a}/x'                   => [ '${a}', 'x' ],
		'$a/x'                     => [ '${a}', 'x' ],
		'${A}/temple/x'            => [ '', 'temple/x' ],
		'${B}/${b}/hello.${HTML}'  => [ '${B}/${b}', 'hello.${HTML}' ],
		'${B}/${b}'                => [ '${B}/${b}', '' ],
		'${B}/${b}/x/y.css'        => [ '${B}/${b}', 'x/y.css' ],
		'${B}x/y'                  => [ '', '${B}x/y' ],
		'${a}-foo/f'               => [ '', '${a}-foo/f' ],
		'x/${B}/y'                 => [ '', 'x/${B}/y' ],
		'${a}/../../etc/passwd'    => [ '${a}', '../../etc/passwd' ],
		'${B}/${b}/../../x'        => [ '${B}/${b}', '../../x' ],
		'/etc/passwd'              => [ '', '/etc/passwd' ],
		'$$/x'                     => [ '', '${$}/x' ],
		'${$}/${a}/x'              => [ '', '${$}/${a}/x' ],
	);
	for my $spec (sort keys %want) {
		is_deeply([ split_dep($spec) ], $want{$spec}, "split_dep $spec");
	}
	is_deeply(\@warn, [], 'split_dep warns about nothing');
}

# --- walk_deps, in a project of its own with a secret next to it
my $top = tempdir(CLEANUP => 1);
my $cwd = getcwd();
sub spew {
	my ($name, $text) = @_;
	(my $d = $name) =~ s{/[^/]*\z}{};
	make_path($d) if $d ne $name;
	open my $fh, '>', $name or die "$name: $!";
	print $fh $text;
	close $fh or die;
}
sub hdr { my %h = @_; join '', "[%\n", (map { " # $_: $h{$_}\n" } sort keys %h), "-%]\n" }

make_path("$top/proj");
spew("$top/secret", hdr(NEED => 'leaked'));
chdir "$top/proj" or die $!;
my %D = (A => '.', a => 'src', B => 'build', b => 'public', c => '.cache', tem => 'tem');

spew('src/index.html', hdr(HAVE => '${a}/index.html',
	NEED => 'tem/head.html ${B}/${b}/base.css', WANT => '${a}/gone.html'));
spew('tem/head.html', hdr(NEED => '${a}/part.html', WANT => '${a}/index.html'));
spew('src/part.html', hdr(NEED => 'tem/head.html leaf'));
spew('leaf', '');
spew('build/public/base.css', hdr(NEED => 'must-not-be-read'));
spew('must-not-be-read', '');

{
	my %G;
	my @got = walk_deps(\%D, '${a}/index.html', { graph => \%G });
	is_deeply(\@got, [ '${a}/index.html', 'tem/head.html', '${a}/part.html', 'leaf',
		'${B}/${b}/base.css', '${a}/gone.html' ],
		'depth first, NEED before WANT, symbolic, cycles stop');
	ok(!defined $G{'${B}/${b}/base.css'}, 'a build dependent is listed, not read');
	ok(!defined $G{'must-not-be-read'}, '... nor what it names');
	is_deeply($G{'${a}/gone.html'}, {}, 'a missing file is forgiven');

	# the cache is trusted: no file is read twice
	spew('leaf', hdr(NEED => 'changed'));
	spew('tem/head.html', hdr(NEED => 'other'));
	my @again = walk_deps(\%D, '${a}/index.html', { graph => \%G });
	is_deeply(\@again, \@got, 'a graph given back is used as it is');
	my @fresh = walk_deps(\%D, '${a}/index.html');
	isnt(join(',', @fresh), join(',', @got), '... and without one, files are read again');
}

# --- what must not be followed: listed (it is what the file says), never opened
{
	my $bad = sub {
		my ($spec) = @_;
		my $norm = norm_deps($spec);
		my %G;
		spew('src/evil.html', hdr(NEED => $spec));
		my @got = walk_deps(\%D, '${a}/evil.html', { graph => \%G });
		is_deeply(\@got, [ '${a}/evil.html', $norm ], "listed: $spec");
		ok(exists $G{$norm} && !defined $G{$norm}, "not read: $spec");
		ok(!grep({ $_ eq 'leaked' } @got), "nothing it leads to: $spec");
	};
	$bad->($_) for (
		'../secret',
		'${a}/../secret',
		'${a}/x/../../secret',
		'${a}/../../secret',
		'tem/../../secret',
		'${B}/${b}/../../../secret',
		"$top/secret",
		'/etc/passwd',
		'${A}//etc/passwd',
		'${a}//etc/passwd',
		'${c}//etc/passwd',
	);
	# the start itself is held to the same rules
	my %G;
	my @got = walk_deps(\%D, '../secret', { graph => \%G });
	is_deeply(\@got, ['../secret'], 'the entry itself may not be traversal');
	ok(!grep({ defined } values %G), '... and is not read');
}

# --- spellings are one node; a directory is not a header to read
{
	spew('src/dup.html', hdr(NEED => '$a/part.html ${a}/part.html tem/../x'));
	make_path('src/adir');
	spew('src/dir.html', hdr(NEED => '${a}/adir ${a}/adir/'));
	my %G;
	my @got = walk_deps(\%D, '$a/dup.html', { graph => \%G });
	is_deeply([ grep { /part/ } @got ], [ '${a}/part.html' ], 'dollar-a and braces: one entry');
	ok(exists $G{'${a}/dup.html'}, '... keyed by the normalized spec');
	my @dir = eval { walk_deps(\%D, '${a}/dir.html') };
	is($@, '', 'a directory dependency does not die');
	is_deeply(\@dir, [ '${a}/dir.html', '${a}/adir', '${a}/adir/' ], '... and is listed without dependents');
}

# --- a variable's own value may climb: it is the host's, not the source's
{
	my %E = (%D, a => '../proj/src');
	spew('leaf', '');
	spew('src/ok.html', hdr(NEED => 'leaf'));
	my @got = walk_deps(\%E, '${a}/ok.html');
	is_deeply(\@got, [ '${a}/ok.html', 'leaf' ], 'a value with .. in it is trusted');
	# ${B}x is not ${B}: it is read like any other source
	spew('buildx/y', hdr(NEED => 'leaf'));
	my %G;
	walk_deps(\%D, '${B}x/y', { graph => \%G });
	ok(defined $G{'${B}x/y'}, '${B}x is not a build dependent');
}

# --- follow: the caller says what may be read
spew('tem/head.html', hdr(NEED => '${a}/part.html', WANT => '${a}/index.html'));
{
	my (%G, @asked);
	my @got = walk_deps(\%D, '${a}/index.html', { graph => \%G, follow => sub {
		my ($D, $spec) = @_;
		push @asked, $spec;
		return $spec =~ m{\Atem/} || $spec eq '${a}/index.html' ? 1 : 0;
	} });
	ok(!defined $G{'${a}/part.html'}, 'follow: refused is not read');
	ok(defined $G{'tem/head.html'}, 'follow: allowed is read');
	ok((grep { $_ eq '${a}/part.html' } @got), 'follow: refused is still listed');
	is($asked[0], '${a}/index.html', 'follow gets the symbolic spec');
}

chdir $cwd;

# --- follow_ok: leaving the root
{
	my $D = { a => '.', B => 'build' };
	ok(!follow_ok($D, '/etc/passwd'), 'absolute path denied');
	ok(!follow_ok($D, '${a}//etc/passwd'), '... also when hidden behind ${a}//');
	ok(!follow_ok($D, '${A}//etc/passwd'), '... and ${A}//');
	ok(follow_ok($D, '${a}/x/y'), 'ordinary path okay');
}
