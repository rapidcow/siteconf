#!perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E;

my $script = E2E::setup();
system('doit --version >/dev/null 2>&1') == 0 or plan skip_all => 'no doit';
run('siteconf -i', $^X, $script, qw(-i -P web -Osite_url=https://example.test
	-SB=build -q -MRdKw::WwW::GenLib=0));
mkdir 'build' or die $!;
run('./configure', $^X, './configure', '-q');
run('generate', $^X, $script, qw(-g -q -G doit -B build -t all -t basic -o custom.py));
chdir 'build' or die $!;
run('subset', qw(doit run -f custom.py basic));
ok(-f 'site/sub/index.html', 'nested target built');
ok(!-e 'site/robots.txt', 'only the subset');
unlike(run('incremental', qw(doit run -f custom.py basic)), qr/^\.  /m, 'no action reran');
run('default', qw(doit -f custom.py));
ok(-f 'site/robots.txt', 'default builds all');
run('clean', qw(doit clean -f custom.py));
ok(!-e 'site/index.html', 'cleaned target');
E2E::done();
