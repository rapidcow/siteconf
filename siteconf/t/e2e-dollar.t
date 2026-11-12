#!perl
#
# t/e2e-dollar.t - siteconf -g, then make, GNU make or ninja, for a
# recipe that hands the shell a :Q'd value with `$' in it: the `$' is
# the shell's, and no tool may take it for its own

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make );

my $script = script_path();
$ENV{PERL5LIB} = perl5lib();

# Whatever can run a makefile at all, as -G make; GNU make, as -G gmake
my $make = $ENV{MAKE} || 'make';
$make = undef if system("printf 'all:\\n' | $make -f - >/dev/null 2>&1");
my ($gmake) = grep {
	my $v = `$_ --version 2>/dev/null`;
	$v =~ /\AGNU Make (\d+)\.(\d+)/ && ($1 > 3 || $1 == 3 && $2 > 81);
} grep { defined } $ENV{GMAKE}, 'gmake', 'make';
my $ninja = $ENV{NINJA} || 'ninja';
$ninja = undef if system("$ninja --version >/dev/null 2>&1");
plan tests => 9;

my $X = q{d$llar $(x) ${y} $$ $ '$' "$" a|b `x`};

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

# Generates for -G `G', builds with `tool', and says what it made
sub builds
{
	my ($G, @tool) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html", "$dir/MY");
	my %f = (
		MANIFEST => "MAKE all\n\tNEED a\n",
		'Makefile.in' => "a:\n\tprintf '%s\\n' \${X:Q} > \${B:Q}/\${b:Q}/\${\@:Q}\n",
		'html/a' => '',
	);
	for my $name (keys %f) {
		open my $fh, '>', "$dir/$name" or die "$name: $!";
		print $fh $f{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok', X => $X }, 'test');
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', $G);
	is($status, 0, "siteconf -g -G $G") or return diag $out;
	($status, $out) = run($dir, @tool);
	is($status, 0, "$tool[0] builds it") or return diag $out;
	open my $fh, '<', "$dir/site/a" or return fail("$G: site/a: $!");
	my $got = do { local $/; <$fh> };
	is($got, "$X\n", "$G: the shell is given what :Q quoted");
}

SKIP: {
	skip 'no make', 3 unless $make;
	builds('make', $make);
}

SKIP: {
	skip 'no GNU make newer than 3.81', 3 unless $gmake;
	builds('gmake', $gmake);
}

SKIP: {
	skip 'no ninja', 3 unless $ninja;
	builds('ninja', $ninja);
}
