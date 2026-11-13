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
use File::Basename qw( dirname );
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
plan tests => 48;

my @name = ('sp ace', "ta\tb", 'ha#sh', 'co:lon', 'do$llar', 'st*ar', 'qu?est',
	'br[ack]et', '~tilde', 'back\\slash', 'back\\ space');

# A project in a directory of its own (which is its own build directory)
# whose page needs @need
sub project
{
	my $extra = ref $_[0] eq 'HASH' ? shift : {};
	my (@need) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html", "$dir/MY");
	my %f = (
		MANIFEST => "MAKE all\n\tNEED a.html\n",
		'Makefile.in' => "a.html:\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n",
		'html/a.html' => join('', map { "# NEED: " . escape_dep($_, unicode => 1) . "\n" } @need),
		map { ($_ => '') } @need, 'stXar', 'quXest', 'brXet',
	);
	@f{keys %$extra} = values %$extra;
	for my $name (keys %f) {
		make_path(dirname("$dir/$name"));
		open my $fh, '>', "$dir/$name" or die "$name: $!";
		print $fh $f{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok' }, 'test');
	$dir;
}

sub spaced_project
{
	project({
		MANIFEST => "MAKE all\n\tNEED implicit\${U+20}name.html\n\tNEED dir\${U+0020}name/page\${U+20}name.html\n",
		'Makefile.in' => <<'RULES',
implicit${U+0020}name.html:
	cp ${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}
${b}/dir${U+20}name/page${U+0020}name.html: ${a}/source${U+20}name.txt NEED:${A}/rule${U+0020}dep WANT:${A}/optional${U+20}dep ${B}/${b}/other${U+20}name.html
	cp ${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}
other${U+20}name.html: ${a}/
	printf 'generated\n' > ${B:Q}/${b:Q}/${@:Q}
RULES
		'html/implicit name.html' => "# NEED: header\${U+20}dep\n# NEED: \${B}/\${b}/other\${U+0020}name.html\nimplicit\n",
		'html/source name.txt' => "explicit\n",
		'header dep' => '', 'rule dep' => '', 'optional dep' => '',
	});
}

sub contents
{
	open my $fh, '<', $_[0] or return undef;
	local $/; <$fh>;
}

# Names survive parsing, shell recipes, directory creation, regeneration,
# dependency checks and cleaning, using both forms of the space escape.
sub spaced_builds
{
	my ($G, $tool, $up_to_date) = @_;
	my $dir = spaced_project();
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', $G);
	is($status, 0, "$G: generate spaced targets and sources") or diag $out;
	($status, $out) = run($dir, $tool, '-j2');
	is($status, 0, "$G: build them in parallel") or diag $out;
	is(contents("$dir/site/implicit name.html"), contents("$dir/html/implicit name.html"),
		'implicit source and :Q');
	is(contents("$dir/site/dir name/page name.html"), "explicit\n", 'explicit source and spaced directory');
	is(contents("$dir/site/other name.html"), "generated\n", 'a generated dependency with a space');
	ok($up_to_date->($dir), 'spaced targets are up to date');
	($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', $G, '-F', 'MY/MANIFEST.all');
	is($status, 0, 'the resolved manifest can be read back') or diag $out;
	for my $dep ('header dep', 'rule dep', 'optional dep', 'html/source name.txt', 'site/other name.html') {
		# Put just this dependency after all outputs, without waiting
		# for the filesystem clock.  Restore its time after the query.
		my @st = stat "$dir/$dep";
		my $new = time + 10;
		utime $new, $new, "$dir/$dep" or die "$dep: $!";
		ok(!$up_to_date->($dir), "rebuild after $dep changes");
		utime $st[8], $st[9], "$dir/$dep" or die "$dep: $!";
	}
	($status, $out) = run($dir, $tool, $G eq 'ninja' ? ('-t', 'clean') : ('clean'));
	is($status, 0, "$G: clean spaced names") or diag $out;
	ok(!-e "$dir/site/implicit name.html" && !-e "$dir/site/dir name/page name.html"
		&& !-e "$dir/site/other name.html", 'clean removed the complete names');
	($status, $out) = run($dir, $tool, '-j2');
	is($status, 0, 'build again after cleaning') or diag $out;
}

SKIP: {
	skip 'no GNU make newer than 3.81', 15 unless $gmake;
	spaced_builds('gmake', $gmake, sub { !(run($_[0], $gmake, '-q'))[0] });
}
SKIP: {
	skip 'no ninja', 15 unless $ninja;
	spaced_builds('ninja', $ninja, sub { (run($_[0], $ninja, '-n'))[1] =~ /no work to do/ });
}
{
	my $dir = spaced_project();
	my ($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'make');
	isnt($status, 0, 'POSIX Make rejects spaced targets');
	like($out, qr/make cannot name .*U\+0020.*GNU Make can/s, 'rejected by the backend');
	ok(!-e "$dir/Makefile", 'no invalid POSIX Makefile written');
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
	skip 'no GNU Make newer than 3.81', 5 unless $gmake;
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
	isnt($status, 0, 'Make cannot name a space');
	like($out, qr/make cannot name `sp ace' \(with inescapable U\+0020\).*GNU Make can/s,
		'... and says that GNU Make can');
	$dir = project('pi|pe');
	($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'ninja');
	like($out, qr/ninja cannot name `pi\|pe' \(with inescapable `\|'\)/, 'ninja cannot name a |');
	$dir = project('se;mi');
	($status, $out) = run($dir, $^X, $script, '-g', '-q', '-G', 'gmake');
	like($out, qr/GNU Make cannot name `se;mi' \(with inescapable `;'\)/, 'GNU Make cannot name a ;');
	ok(!-e "$dir/Makefile", '... and writes nothing');
}
