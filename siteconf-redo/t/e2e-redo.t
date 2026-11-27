#!perl
#
# t/e2e-redo.t - siteconf -i, ./configure,
# siteconf -g -G redo, redo; on siteconf's t/fixture/web

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw( tempdir );
use lib "$FindBin::Bin/lib";

use E2E;
use Tools qw( redo_bin redo_sh shq );

my $script = E2E::setup();
# redo and redo-ifchange, first in $PATH (see t/lib/Tools.pm)
my ($redo, $why) = redo_bin();
defined $redo or plan skip_all => $why;
$redo = shq($redo);	# (run says it to sh)
# What runs a .do, if $REDO_SH says (as on Termux, with no /bin/sh)
my $sh = redo_sh();
my @Ssh = defined $sh ? shq("-Ssh=$sh") : ();
# Not --version: a redo may not have it, or not say its name in it.
# What we need of redo is that it builds a file from its .do (in a
# directory of its own, for redo keeps its state there).  Returns
# undef if it does, or else why not; and diag says what redo said.
sub redo_builds
{
	my $dir = tempdir(CLEANUP => 1);
	my $shebang = "#!" . (defined $sh ? $sh : q(/bin/sh));
	open my $fh, '>', "$dir/probe.do" or die "probe.do: $!";
	print $fh $shebang, "\n", <<\probe;
echo ok >"$3";
probe
	close $fh or die "probe.do: $!";
	chmod 0777 & ~umask, "$dir/probe.do" or die "probe.do: $!";
	(my $q = $dir) =~ s/'/'\\''/g;
	my $err = `cd '$q' && $redo probe 2>&1 >/dev/null`;
	my $status = $?;
	my $why = "redo could not build probe.do ($shebang)";
	if ($status != 0) {
		diag("redo probe: $_") for grep { /\S/ } split /\n/, $err;
		return sprintf '%s: exit %d', $why, $status >> 8;
	}
	open $fh, '<', "$dir/probe" or return "$why: no probe";
	my $line = <$fh>;
	defined $line && $line eq "ok\n" ? undef : "$why: probe is not ok";
}
if (defined(my $why = redo_builds())) { plan skip_all => $why; }
plan tests => 49;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
	-MRdKw::WwW::GenLib=0 ));
mkdir 'build' or die "mkdir: $!";
run('./configure', $^X, './configure', '-q');

my $out = run('siteconf -g -G redo', $^X, $script, qw( -g -G redo -B build -t all -t basic ), @Ssh);
like($out, qr{To build, run: \( cd build && redo all \)$}m, 'says what to run');
ok(!grep({ !-x; } 'build/basic.do', 'build/all.do', glob('build/site/*.do')), 'the .do files are executable');
chmod 0644, 'build/basic.do' or die "chmod: $!";
run('siteconf -g -G redo, again', $^X, $script, qw( -g -q -G redo -B build -t all -t basic ), @Ssh);
ok(-x 'build/basic.do', '... even one that was there, and is the same');
run('redo basic', $redo, 'build/basic');
ok(-f 'build/site/sub/index.html', 'redo basic: sub built');
like(slurp('build/site/sub/index.html.do'), qr{^O=sub/\$\{3##\*/\}\n(?:.*\n)*.* build/site/\$O \)\n\z}m,
	'the recipe writes $3, and there is no mv');
ok(!grep({ !-f && -s _; } map { "build/site/$_" } qw( index.html sub/index.html )), '... and redo makes the target of it');
ok(!-e 'build/site/robots.txt', 'redo basic: only the subset');
like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'redo: O.location');
# (redo, and not redo-ifchange: JdeBP's runs only in a .do.  A goal is
# made every time, and makes what it needs only if that is out of date)
unlike(run('redo basic again', $redo, 'build/basic'), qr/site\/index\.html/, 'redo: incremental');
# (what it says and when: a redo may look at what is in a file only if
# its time is not the second that it was seen in, as JdeBP's does with
# the mtime, and redo-c with the ctime, which utime cannot move; so the
# change is in a second after the build's)
next_second();
open my $fh, '>>', 'html/index.html' or die "html/index.html: $!";
print $fh "<!-- newer -->\n";
close $fh or die "html/index.html: $!";
like(run('redo basic, a source changed', $redo, 'build/basic'), qr/site\/index\.html/, '... and out of date');
run('redo all', $redo, 'build/all');
ok(-f 'build/site/robots.txt', 'redo all');

# Other goals: the same rules, so the targets' .do files are left alone;
# and the default goal (-t ,: all, the first of the manifest) is all.do,
# which was the goal all's
$out = run(q(siteconf -g -G redo -t , -t basic), $^X, $script, qw( -g -G redo -B build -t ), q(,), qw( -t basic ), @Ssh);
unlike($out, qr{site/}, q(... and only the goals are written)) or diag $out;
like($out, qr{^Updating all\.do$}m, q(... all.do, now the default goal's));
like(slurp(q(build/all.do)), qr/^# options: -t ,(?: \S*-Ssh=.*)?$/m, q(... as its header says));
like($out, qr{To build, run: \( cd build && redo all \)$}m, q(... which is what to run));
run(q(redo, for all.do), $redo, q(build/all));

# -o: the default goal's .do; /dev/null, none
$out = run(q(siteconf -g -G redo -t ,basic -o top.do), $^X, $script, qw( -g -G redo -B build -t ), q(,basic), qw( -o top.do ), @Ssh);
like($out, qr{^Writing top\.do$}m, q(-t ,basic -o top.do: the default goal is top.do));
like($out, qr{To build, run: \( cd build && redo top \)$}m, q(... which is what to run));
run(q(redo top), $redo, q(build/top));
$out = run(q(siteconf -g -G redo -o /dev/null), $^X, $script, qw( -g -G redo -B build -t ), q(,), qw( -o /dev/null ), @Ssh);
unlike($out, qr{\.do}, q(-t , -o /dev/null: no .do at all, as the targets' are as they were)) or diag $out;

# -Sclean: clean.do removes what all makes, and redo makes it again
# (-Sarg_prefix: the .do files work by other names too)
$out = run(q(siteconf -g -G redo -Sclean -Spurge -Sarg_prefix=sc_), $^X, $script,
	qw( -g -G redo -B build -t all -Sclean -Spurge -Sarg_prefix=sc_ -Sarg_max=40 ), @Ssh);
ok(-x 'build/clean.do' && -x 'build/purge.do', q(-Sclean -Spurge: clean.do and purge.do));
like(slurp('build/site/robots.txt.do'), qr/^sc_O=\$\{3##\*\/\}\n.*^rm -f -- "\$3"\n.* build\/site\/\$sc_O \)\n\z/ms, q(-Sarg_prefix=sc_: $sc_O));
run('redo all', $redo, 'build/all');
ok(-f 'build/site/robots.txt', '... redo all');
run('redo clean', $redo, 'build/clean');
ok(!-e 'build/site/robots.txt' && !-e 'build/site/sub/index.html', 'redo clean: the files are gone');
run('redo all, after clean', $redo, 'build/all');
ok(-f 'build/site/robots.txt' && -f 'build/site/sub/index.html', '... and redo all makes them again');
$out = run(q(siteconf -g -G redo, without -Sclean -Spurge -Sarg_max), $^X, $script,
	qw( -g -G redo -B build -t all -Sarg_prefix=sc_ ), @Ssh);
unlike($out, qr{site/}, q(... the targets' .do files are left alone)) or diag $out;
$out = run(q(siteconf -g -G redo, with them again), $^X, $script,
	qw( -g -G redo -B build -t all -Sclean -Spurge -Sarg_prefix=sc_ -Sarg_max=40 ), @Ssh);
run('redo purge', $redo, 'build/purge');
ok(!-e 'build/site/robots.txt', 'redo purge: gone too');

# -Sliteral_target=1: the recipe writes the target, which goes to $3
$out = run(q(siteconf -g -G redo -Sliteral_target=1), $^X, $script,
	qw( -g -G redo -B build -t all -Sliteral_target=1 ), @Ssh);
like(slurp('build/site/robots.txt.do'), qr{^\( cd -- \.\. && cp html/robots\.txt build/site/robots\.txt \)\nmv -f -- site/robots\.txt "\$o"$}m,
	'-Sliteral_target=1: the recipe writes the target');
run('redo all, -Sliteral_target=1', $redo, 'build/all');
ok(-f 'build/site/robots.txt' && -f 'build/site/sub/index.html', '... and redo all makes it');

E2E::done();

# Wait for the clock to be in the next second (a file's times are in
# whole seconds, to a redo that reads only st_mtime or st_ctime)
sub next_second
{
	my $t = time;
	select undef, undef, undef, 0.05 while time <= $t;
}
