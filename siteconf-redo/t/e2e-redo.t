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

my $script = E2E::setup();
my $redo = $ENV{REDO} || 'redo';
# Not --version: a redo may not have it, or not say its name in it.
# What we need of redo is that it builds a file from its .do (in a
# directory of its own, for redo keeps its state there).
sub redo_builds
{
	my $dir = tempdir(CLEANUP => 1);
	open my $fh, '>', "$dir/probe.do" or die "probe.do: $!";
	print $fh <<\probe;
#!/bin/sh
echo ok >"$3";
probe
	close $fh or die "probe.do: $!";
	chmod 0777 & ~umask, "$dir/probe.do" or die "probe.do: $!";
	(my $q = $dir) =~ s/'/'\\''/g;
	system("cd '$q' && $redo probe >/dev/null 2>&1") == 0 or return 0;
	open $fh, '<', "$dir/probe" or return 0;
	my $line = <$fh>;
	defined $line && $line eq "ok\n";
}
redo_builds() or plan skip_all => "no redo that can build a file";
plan tests => 29;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
	-MRdKw::WwW::GenLib=0 ));
mkdir 'build' or die "mkdir: $!";
run('./configure', $^X, './configure', '-q');

my $out = run('siteconf -g -G redo', $^X, $script, qw( -g -G redo -B build -t all -t basic ));
like($out, qr{To build, run: \( cd build && redo all \)$}m, 'says what to run');
ok(!grep({ !-x } 'build/basic.do', 'build/all.do', glob('build/site/*.do')), 'the .do files are executable');
chmod 0644, 'build/basic.do' or die "chmod: $!";
run('siteconf -g -G redo, again', $^X, $script, qw( -g -q -G redo -B build -t all -t basic ));
ok(-x 'build/basic.do', '... even one that was there, and is the same');
run('redo basic', $redo, 'build/basic');
ok(-f 'build/site/sub/index.html', 'redo basic: sub built');
ok(!-e 'build/site/robots.txt', 'redo basic: only the subset');
like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'redo: O.location');
unlike(run('redo-ifchange again', "$redo-ifchange", 'build/basic'), qr/site\/index\.html/, 'redo: incremental');
my $t = time + 10;
utime $t, $t, 'html/index.html' or die $!;
like(run('redo-ifchange, a source newer', "$redo-ifchange", 'build/basic'), qr/site\/index\.html/, '... and out of date');
run('redo all', $redo, 'build/all');
ok(-f 'build/site/robots.txt', 'redo all');

# Other goals: the same rules, so the targets' .do files are left alone;
# and the default goal (-t ,: all, the first of the manifest) is all.do,
# which was the goal all's
$out = run(q(siteconf -g -G redo -t , -t basic), $^X, $script, qw( -g -G redo -B build -t ), q(,), qw( -t basic ));
unlike($out, qr{site/}, q(... and only the goals are written)) or diag $out;
like($out, qr{^Updating all\.do$}m, q(... all.do, now the default goal's));
like(slurp(q(build/all.do)), qr/^# options: -t ,$/m, q(... as its header says));
like($out, qr{To build, run: \( cd build && redo all \)$}m, q(... which is what to run));
run(q(redo, for all.do), $redo, q(build/all));

# -o: the default goal's .do; /dev/null, none
$out = run(q(siteconf -g -G redo -t ,basic -o top.do), $^X, $script, qw( -g -G redo -B build -t ), q(,basic), qw( -o top.do ));
like($out, qr{^Writing top\.do$}m, q(-t ,basic -o top.do: the default goal is top.do));
like($out, qr{To build, run: \( cd build && redo top \)$}m, q(... which is what to run));
run(q(redo top), $redo, q(build/top));
$out = run(q(siteconf -g -G redo -o /dev/null), $^X, $script, qw( -g -G redo -B build -t ), q(,), qw( -o /dev/null ));
unlike($out, qr{\.do}, q(-t , -o /dev/null: no .do at all, as the targets' are as they were)) or diag $out;

E2E::done();
