#!perl
#
# t/e2e-ninja.t - siteconf -i, ./configure, siteconf -g -G ninja, ninja; on t/fixture/web

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E;

my $script = E2E::setup();
my $ninja = $ENV{NINJA} || 'ninja';
system("$ninja --version >/dev/null 2>&1") == 0 or plan skip_all => "no ninja";
plan tests => 13;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
       -MRdKw::WwW::GenLib=0 ));
run('./configure', $^X, './configure', '-q');

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

E2E::done();
