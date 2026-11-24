#!perl
#
# t/e2e-bmake.t - siteconf -i, ./configure,
# siteconf -g -G bmake, bmake; on t/fixture/web

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use E2E;
use Tools qw( bmake_cmd );

my $script = E2E::setup();
my $bmake = bmake_cmd();
system("$bmake -V MAKE_VERSION >/dev/null 2>&1") == 0 or plan skip_all => "no bmake";
plan tests => 14;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
	-MRdKw::WwW::GenLib=0 ));
mkdir 'build' or die "mkdir: $!";
run('./configure', $^X, './configure', '-q');

my $out = run('siteconf -g -G bmake', $^X, $script, qw( -g -G bmake -B build -t all -t basic -Sclean ));
like($out, qr/To build, run: bmake -C build all$/m, 'says what to run');
run('bmake basic', $bmake, '-C', 'build', 'basic');
ok(-f 'build/site/sub/index.html' && !-e 'build/site/robots.txt', 'bmake basic: the subset');
is(run(q(bmake -n), $bmake, qw( -C build -n basic )), q(), q(bmake: up to date));
my $t = time + 10;
utime $t, $t, q(html/index.html) or die $!;
like(run(q(bmake -n, a source newer), $bmake, qw( -C build -n basic )), qr/render/, q(... and out of date));
run('bmake (default goal)', $bmake, '-C', 'build');
ok(-f 'build/site/robots.txt', 'bmake all');
run('bmake clean', $bmake, '-C', 'build', 'clean');
ok(!-e 'build/site/index.html', 'bmake clean');

E2E::done();
