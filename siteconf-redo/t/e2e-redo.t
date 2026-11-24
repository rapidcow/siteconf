#!perl
#
# t/e2e-redo.t - siteconf -i, ./configure,
# siteconf -g -G redo, redo; on siteconf's t/fixture/web

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use E2E;

my $script = E2E::setup();
my $redo = $ENV{REDO} || 'redo';
system("$redo --version >/dev/null 2>&1") == 0 or plan skip_all => "no redo";
plan tests => 14;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
	-MRdKw::WwW::GenLib=0 ));
mkdir 'build' or die "mkdir: $!";
run('./configure', $^X, './configure', '-q');

my $out = run('siteconf -g -G redo', $^X, $script, qw( -g -G redo -B build -t all -t basic ));
like($out, qr{To build, run: \( cd build && redo all \)$}m, 'says what to run');
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

E2E::done();
