#!perl
#
# t/e2e-names.t - siteconf -g, then GNU make or ninja, for a page that
# needs files that are hard to name: spelled in its header by
# escape_dep, and in the build file as each tool would have them

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make escape_dep );

my $script = script_path();
$ENV{PERL5LIB} = perl5lib();

# A GNU make that can escape a `:' (which 3.81 cannot)
my ($gmake) = grep {
	my $v = `$_ --version 2>/dev/null`;
	$v =~ /\AGNU Make (\d+)\.(\d+)/ && ($1 > 3 || $1 == 3 && $2 > 81);
} grep { defined } $ENV{GMAKE}, 'gmake', 'make';
my $ninja = $ENV{NINJA} || 'ninja';
$ninja = undef if system("$ninja --version >/dev/null 2>&1");
plan tests => 15;

my @name = ('sp ace', "ta\tb", 'ha#sh', 'co:lon', 'do$llar', 'st*ar', 'qu?est',
	'br[ack]et', '~tilde', 'back\\slash', 'back\\ space');

# A project in a directory of its own (which is its own build directory)
# whose page needs @need
sub project
{
	my (@need) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html", "$dir/MY");
	my %f = (
		MANIFEST => "MAKE all\n\tNEED a.html\n",
		'Makefile.in' => "a.html:\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n",
		'html/a.html' => join('', map { "# NEED: " . escape_dep($_, unicode => 1) . "\n" } @need),
		map { ($_ => '') } @need, 'stXar', 'quXest', 'brXet',
	);
	for my $name (keys %f) {
		open my $fh, '>', "$dir/$name" or die "$name: $!";
		print $fh $f{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok' }, 'test');
	$dir;
}

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

# Builds, is then up to date, and is out of date again for each of
# @need (but not for what a wildcard would have matched)
sub builds
{
	my ($tool, $up_to_date, @need) = @_;
	my $dir = project(@need);
	my $G = defined $ninja && $tool eq $ninja ? 'ninja' : 'gmake';
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', $G);
	is($status, 0, "siteconf -g -G $G") or return diag $out;
	($status, $out) = run($dir, $tool);
	ok($status == 0 && -f "$dir/site/a.html", "$G builds it") or return diag $out;
	ok($up_to_date->($dir), '... and then it is up to date');
	my $t = time + 10;
	utime $t, $t, "$dir/$_" for qw( stXar quXest brXet );
	ok($up_to_date->($dir), '... whatever a wildcard would have matched');
	my @stale;
	for my $name (@need) {
		utime ++$t, $t, "$dir/$name" or die "$name: $!";
		push @stale, $name if $up_to_date->($dir);
		run($dir, $tool);
	}
	is_deeply(\@stale, [], '... and out of date when what it needs is newer');
}

SKIP: {
	skip 'no GNU make newer than 3.81', 5 unless $gmake;
	builds($gmake, sub { !(run($_[0], $gmake, '-q'))[0] }, @name);
}

SKIP: {
	skip 'no ninja', 5 unless $ninja;
	builds($ninja, sub { (run($_[0], $ninja, '-n'))[1] =~ /no work to do/ }, @name);
}

# What they cannot name, they say so of
{
	my $dir = project('sp ace');
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q');
	isnt($status, 0, 'make cannot name a space');
	like($out, qr/make cannot name `sp ace' \(with U\+0020 in it\); GNU make can \(-G gmake\)/,
		'... and says that GNU make can');
	$dir = project('pi|pe');
	($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'ninja');
	like($out, qr/ninja cannot name `pi\|pe' \(with `\|' in it\)/, 'ninja cannot name a |');
	$dir = project('se;mi');
	($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'gmake');
	like($out, qr/GNU make cannot name `se;mi' \(with `;' in it\)/, 'GNU make cannot name a ;');
	ok(!-e "$dir/Makefile", '... and writes nothing');
}
