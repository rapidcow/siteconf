#!perl
#
# t/e2e-glob.t - siteconf -g, then GNU make or ninja, for a source and a
# target of Makefile.in that are named like a dynamic route:
# feed/[year]/index.html.  A glob would match the decoy files too.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use File::Basename qw( dirname );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib );
use RdKw::WwW::GenGenLib qw( write_make );

my $script = script_path();
$ENV{PERL5LIB} = perl5lib();

my ($gmake) = grep {
	my $v = `$_ --version 2>/dev/null`;
	$v =~ /\AGNU Make (\d+)\.(\d+)/ && ($1 > 3 || $1 == 3 && $2 > 81);
} grep { defined } $ENV{GMAKE}, 'gmake', 'make';
my $ninja = $ENV{NINJA} || 'ninja';
$ninja = undef if system("$ninja --version >/dev/null 2>&1");
plan tests => 17;

sub run
{
	my ($dir, @cmd) = @_;
	open my $fh, '-|' or do {
		chdir $dir or die $!;
		open STDERR, '>&', STDOUT or die $!;
		exec @cmd;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	($? >> 8, $out);
}

sub contents { open my $fh, '<', $_[0] or return; local $/; <$fh> }

# The source, and files that [year] and [id] would match (y, e, a, r; i, d)
sub project
{
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/MY");
	my %f = (
		MANIFEST => "MAKE all\n\tNEED feed/2024/index.html\n\tNEED feed/[id].html\n",
		'Makefile.in' =>
			"feed/2024/index.html: \${a}/feed/[year]/index.html\n"
			. "\tcp \${A}/\${a}/\${<:Q} \${B}/\${b}/\${\@:Q}\n"
			. "feed/[id].html: \${a}/feed/[year]/index.html\n"
			. "\tcp \${A}/\${a}/\${<:Q} \${B}/\${b}/\${\@:Q}\n",
		'html/feed/[year]/index.html' => "year\n",
		(map { ("html/feed/$_/index.html" => "decoy $_\n") } qw( y e a r )),
	);
	for my $name (keys %f) {
		make_path(dirname("$dir/$name"));
		open my $fh, '>', "$dir/$name" or die "$name: $!";
		print $fh $f{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok' }, prog => 'test');
	$dir;
}

sub builds
{
	my ($G, $tool, $up_to_date) = @_;
	my $dir = project();
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', $G);
	is($status, 0, "siteconf -g -G $G") or return diag $out;
	($status, $out) = run($dir, $tool);
	is($status, 0, "$G builds it") or return diag $out;
	is(contents("$dir/site/feed/2024/index.html"), "year\n", 'the source is [year], not a decoy');
	is(contents("$dir/site/feed/[id].html"), "year\n", 'and a target [id].html is that file');
	ok($up_to_date->($dir), '... and then it is up to date');
	my $t = time + 10;
	utime $t, $t, "$dir/html/feed/$_/index.html" or die $! for qw( y e a r );
	ok($up_to_date->($dir), '... whatever a wildcard would have matched');
	utime $t + 1, $t + 1, "$dir/html/feed/[year]/index.html" or die $!;
	ok(!$up_to_date->($dir), '... and out of date when [year] is newer');
}

SKIP: {
	skip 'no GNU Make newer than 3.81', 7 unless $gmake;
	builds('gmake', $gmake, sub { !(run($_[0], $gmake, '-q'))[0] });
}
SKIP: {
	skip 'no ninja', 7 unless $ninja;
	builds('ninja', $ninja, sub { (run($_[0], $ninja, '-n'))[1] =~ /no work to do/ });
}
{
	my $dir = project();
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'make');
	isnt($status, 0, 'POSIX Make rejects a wildcard in a name');
	like($out, qr/make cannot name .*GNU Make can/s, 'rejected by the backend');
	ok(!-e "$dir/Makefile", 'no Makefile written');
}
