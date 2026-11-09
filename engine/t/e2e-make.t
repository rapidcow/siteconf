#!perl
#
# t/e2e-make.t - siteconf -i, ./configure, siteconf -g, make; on t/fixture/web
# (and, since nothing about it is particular to make, the diagnostics)

use strict;
use warnings;
use Test::More;
use Cwd ();
use File::Spec;
use File::Find;
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E;

my $script = E2E::setup();
my $make = E2E::make();
# (only now: we may have skipped all)
plan tests => 62;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build
	-MRdKw::WwW::GenLib=0 ));
ok(-x 'configure', 'configure is executable');
my $text = slurp('configure');
my $again = do { run('siteconf -i again', $^X, $script,
	qw( -i -P web -Osite_url=https://example.test -SB=build
	-MRdKw::WwW::GenLib=0 -o configure.2 ));
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

# A is seen from where configure is run, not from where it lives
{
	my $src = Cwd::getcwd();
	my $other = tempdir(CLEANUP => 1);
	system('cp', 'configure', "$other/configure") == 0 or die "cp: $?";
	run('configure -DA', $^X, "$other/configure", '-q', "-DA=$src", '-DB=build-da');
	like(slurp("$src/build-da/MY/config.mk"), qr/^A=\t\Q$src\E$/m, 'absolute -DA is recorded as is');
	ok(!-e "$other/MY" && !-e "$other/build-da", '-DA: nothing made next to that configure');
	run('elsewhere/configure', $^X, "$other/configure", '-q', '-DB=build-cwd');
	ok(-f "$src/build-cwd/MY/config.mk", 'default A is the current directory');
	ok(!-e "$other/build-cwd", '... not where configure is');
	chdir $other or die;
	run('configure -DA relative', $^X, './configure', '-q', '-DA=' . File::Spec->abs2rel($src), '-DB=build-rel');
	chdir $src or die;
	ok(-f "$src/build-rel/MY/config.mk", 'relative -DA is seen from the current directory');
	like(slurp("$src/build-rel/MY/config.mk"), qr/^A=\t\.\.$/m, '... and recorded as seen from build');
	my $abs = tempdir(CLEANUP => 1);
	run('configure -DB absolute', $^X, './configure', '-q', "-DA=$src", "-DB=$abs");
	like(slurp("$abs/MY/config.mk"), qr/^B=\t\Q$abs\E$/m, 'absolute -DB is recorded as is');
	like(slurp("$abs/MY/config.mk"), qr/^A=\t\Q$src\E$/m, '... and so is absolute -DA');
}

my $err = run('siteconf -g', $^X, $script, qw( -g -G make -B build ));
like($err, qr/WANTs `extra\/index\.html', but cannot be made/, 'WANT with a missing need is dropped');
like($err, qr/WANTs `ghost\.html', but cannot be made/, 'WANT without a rule is dropped');
like(slurp('build/MY/MANIFEST.all'), qr/\A.*^MAKE all\n\tNEED index\.html\n\tNEED sub\/index\.html\n\tNEED robots\.txt\n/ms,
	'MY/MANIFEST.all');
like(slurp('build/MY/MANIFEST.basic'), qr/NEED sub\/index\.html/, 'WANT that can be had is kept');
unlike($err = run('siteconf make (alias)', $^X, $script, qw( make -B build )),
	qr/Writing|Updating/, 'regenerating changes nothing');

run('make basic', $make, '-C', 'build', 'basic');
ok(-f 'build/site/sub/index.html', 'basic: sub built');
ok(!-e 'build/site/robots.txt', 'basic: only the subset');
ok(-f 'build/site/style.css', 'basic: and what index.html needs from ${b}');
like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'location');
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

# a NEED that cannot be had is fatal
open my $fh, '>>', 'MANIFEST' or die;
print $fh "MAKE broken\n\tNEED ghost.html\n\tNEED extra/index.html\n";
close $fh;
my $bad = `$^X $script -g -q -B build 2>&1`;
isnt($?, 0, 'NEED of the missing is fatal');
like($bad, qr/goal `broken' NEEDs `ghost\.html'.*\n(?:.*\n)*?.*goal `broken' NEEDs `extra\/index\.html'.*\n(?:.*\n)*?.*2 problems/,
	'all problems are reported at once');

# b = `.': the build dir is the target tree, the root is above it, and
# MY goes in the build dir and nowhere else
{
# <top>/etc/nginx is the root (A) with sites-maker/ in it, where we are;
# the build dir (B) is sites-available/, and sites/ (a) is made into it (b = .)
my $top = tempdir(CLEANUP => 1);
my $A = "$top/etc/nginx";
my @conf = qw( ubuntu/www.conf ubuntu/ns1.conf rpi/default.conf );
make_path("$A/sites-maker", "$A/sites-available", map { "$A/sites/" . s{/[^/]*\z}{}r } @conf);
sub put
{
	my ($file, $text) = @_;
	open my $fh, '>', $file or die "$file: $!";
	print $fh $text;
	close $fh or die;
}
put("$A/sites/$_", lines(HAVE => ["\${A}/\${a}/$_"], NEED => ['${A}/render']) . "server $_\n") for @conf;
put("$A/render", <<'EOF');
open my $in, '<', "sites/$ARGV[0]" or die "$ARGV[0]: $!";
open my $out, '>', $ARGV[1] or die "$ARGV[1]: $!";
print $out "rendered: $_" while <$in>;
EOF
put("$A/sites-maker/MANIFEST", "MAKE all\n" . join '', map { "\tNEED $_\n" } @conf);
put("$A/sites-maker/Makefile.in", join(' ', @conf) . ": \${A}/render\n"
	. "\tcd \${A:Q} && \${^X:Q} render \${\@:Q} \${B:Q}/\${b:Q}/\${\@:Q}\n");
chdir "$A/sites-maker" or die;

run('siteconf -i', $^X, $script, qw( -i -q -SA=.. -SB=sites-available -Sa=sites -Sb=. ));
run('./configure', $^X, './configure', '-q');
run('siteconf -g', $^X, $script, qw( -g -q -G make -B ../sites-available ));

like(slurp("$A/sites-available/MY/config.mk"), qr/^b=\t\.$/m, 'b is the build dir');
my @my;
find({ wanted => sub { push @my, $File::Find::name if -d && m{/MY\z} }, no_chdir => 1 }, $top);
is_deeply(\@my, ["$A/sites-available/MY"], 'MY is made in the build dir and nowhere else');
ok(!-e "$A/MY" && !-e "$top/etc/MY" && !-e "$A/sites-maker/MY", '... not above it, not here');

run('make', $make, '-C', "$A/sites-available");
for my $f (@conf) {
	like(slurp("$A/sites-available/$f"), qr/^rendered: server \Q$f\E$/m, "b = `.': $f made");
}
my $nothing = run('make again', $make, '-C', "$A/sites-available");
unlike($nothing, qr/\brender\b|\bcp\b|\bmkdir\b/, '... and not made again');
}

E2E::done();
