#!perl
#
# t/e2e.t - siteconf -i, ./configure, siteconf -g, make; on t/fixture/web

use strict;
use warnings;
use Test::More;
use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );
use File::Spec;
use File::Temp qw( tempdir );

for my $m (qw( Template URI )) {
	eval "require $m; 1" or plan skip_all => "$m is not installed";
}
my $make = $ENV{MAKE} || 'make';
system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0 or plan skip_all => "no make";

plan tests => 49;

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $script = "$root/blib/script/siteconf";
-f $script or plan skip_all => "not built: perl Makefile.PL && make, in engine/ and genlib/";
my $fixture = "$root/t/fixture/web";
# Whatever lets us load our modules lets the children do so
local $ENV{PERL5LIB} = join ':', map { abs_path($_) } grep { defined && -d } @INC;

my $dir = tempdir(CLEANUP => 1);
system('cp', '-R', "$fixture/.", $dir) == 0 or die "cp: $?";
chdir $dir or die;

sub run {
	my ($desc, @cmd) = @_;
	my $out = `@cmd 2>&1`;
	my $ok = ok($? == 0, $desc);
	diag $out unless $ok;
	$out;
}
sub slurp { open my $fh, '<:utf8', $_[0] or return; local $/; <$fh> }

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build ));
ok(-x 'configure', 'configure is executable');
my $text = slurp('configure');
my $again = do { run('siteconf -i again', $^X, $script,
	qw( -i -P web -Osite_url=https://example.test -SB=build -o configure.2 ));
	slurp('configure.2') };
is($again, $text, 'configure is generated deterministically');

# a missing Template (not core) is reported by configure, not later
{
	my $stub = tempdir(CLEANUP => 1);
	open my $fh, '>', "$stub/Template.pm" or die;
	print $fh "die 'not here';\n1;\n";
	close $fh;
	local $ENV{PERL5LIB} = "$stub:$ENV{PERL5LIB}";
	my $out = `$^X ./configure 2>&1`;
	isnt($?, 0, 'configure without Template fails');
	like($out, qr/E: missing Template\nE: 1 module missing/, '... and says so');
}

like(run('./configure', $^X, './configure'), qr/Writing MY\/config\.mk/, 'configure');
my $quiet = run('./configure again', $^X, './configure');
unlike($quiet, qr/Writing|Updating/, 'reconfiguring changes nothing');
like(slurp('build/MY/config.mk'), qr/^A=\t\.\.$/m, 'A seen from build');
like(slurp('build/MY/option.mk'), qr/^site_url=\thttps:\/\/example\.test$/m, 'O');
unlike(slurp('build/MY/option.mk'), qr/^[abAB]=/m, 'O has no D');

my $err = run('siteconf -g', $^X, $script, qw( -g -G make -B build ));
like($err, qr/dropping WANT `extra\/index\.html'/, 'WANT with a missing need is dropped');
like($err, qr/dropping WANT `ghost\.html'/, 'WANT without a rule is dropped');
like(slurp('build/MY/MANIFEST.all'), qr/\A.*^MAKE all\n\tNEED index\.html\n\tNEED sub\/index\.html\n\tNEED robots\.txt\n/ms,
	'MY/MANIFEST.all');
like(slurp('build/MY/MANIFEST.basic'), qr/NEED sub\/index\.html/, 'WANT that can be had is kept');
unlike($err = run('siteconf make (alias)', $^X, $script, qw( make -B build )),
	qr/Writing|Updating/, 'regenerating changes nothing');

run('make basic', $make, '-C', 'build', 'basic');
ok(-f 'build/site/sub/index.html', 'basic: sub built');
ok(!-e 'build/site/robots.txt', 'basic: only the subset');
ok(-f 'build/site/style.css', 'basic: and what index.html needs from ${b}');
like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'O.location');
like(slurp('build/site/index.html'), qr/out=site .*site=https:\/\/example\.test/s, 'D and O');
like(slurp('build/site/sub/index.html'), qr/href="\.\.\/index\.html"/, 'locate');

run('make (default goal)', $make, '-C', 'build');
ok(-f 'build/site/robots.txt', 'all');
my $nothing = run('make again', $make, '-C', 'build');
# (GNU make says so, bmake says nothing: what matters is that no recipe ran)
unlike($nothing, qr/\brender\b|\bcp\b|\bmkdir\b/, 'incremental');

# an option changes => the pages are rendered anew; a definition is not.
sleep 1;
run('reconfigure', $^X, './configure', '-Osite_url=https://other.test');
run('make after -O', $make, '-C', 'build');
like(slurp('build/site/index.html'), qr/other\.test/, 'options reach the pages');

run('make clean', $make, '-C', 'build', 'clean');
ok(!-e 'build/site/index.html', 'clean');

# ... and the same through ninja
SKIP: {
	my $ninja = $ENV{NINJA} || 'ninja';
	system("$ninja --version >/dev/null 2>&1") == 0 or skip "no ninja", 9;

	run('siteconf -g -G ninja', $^X, $script, qw( -g -q -G ninja -B build ));
	run('ninja basic', $ninja, '-C', 'build', 'basic');
	ok(-f 'build/site/sub/index.html', 'ninja basic: sub built');
	ok(!-e 'build/site/robots.txt', 'ninja basic: only the subset');
	like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'ninja: O.location');
	like(run('ninja again', $ninja, '-C', 'build', 'basic'), qr/no work to do/, 'ninja: incremental');
	run('ninja (default goal)', $ninja, '-C', 'build');
	ok(-f 'build/site/robots.txt', 'ninja all');
	run('ninja -t clean', $ninja, '-C', 'build', '-t', 'clean');
	ok(!-e 'build/site/index.html', 'ninja clean');
}

# a NEED that cannot be had is fatal
open my $fh, '>>', 'MANIFEST' or die;
print $fh "MAKE broken\n\tNEED ghost.html\n\tNEED extra/index.html\n";
close $fh;
my $bad = `$^X $script -g -q -B build 2>&1`;
isnt($?, 0, 'NEED of the missing is fatal');
like($bad, qr/goal `broken' needs `ghost\.html'.*\n.*goal `broken' needs `extra\/index\.html'.*\n.*2 problems/,
	'all problems are reported at once');

chdir '/';
