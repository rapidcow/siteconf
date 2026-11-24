#!perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E;
use Tools qw( doit_cmd );

my $script = E2E::setup();
my $doit = doit_cmd();
system("$doit --version >/dev/null 2>&1") == 0 or plan skip_all => 'no doit';
run('siteconf -i', $^X, $script, qw(-i -P web -Osite_url=https://example.test
	-SB=build -q -MRdKw::WwW::GenLib=0));
mkdir 'build' or die $!;
run('./configure', $^X, './configure', '-q');
run('generate', $^X, $script, qw(-g -q -G doit -B build -t all -t basic -o custom.py -Smode=exec -Spurge), "'-Sclean=clean-&'");
chdir 'build' or die $!;
run('subset', $doit, qw(run -f custom.py basic));
ok(-f 'site/sub/index.html', 'nested target built');
ok(!-e 'site/robots.txt', 'only the subset');
unlike(run('incremental', $doit, qw(run -f custom.py basic)), qr/^\.  /m, 'no action reran');
run('default', $doit, qw(-f custom.py));
ok(-f 'site/robots.txt', 'default builds all');
run('clean selected goal', $doit, qw(run -f custom.py clean-basic));
ok(!-e 'site/sub/index.html' && -f 'site/robots.txt', 'clean-basic keeps other goals');
run('purge', $doit, qw(run -f custom.py purge));
ok(!-e 'site/robots.txt', 'purged');
run('purge absent targets', $doit, qw(run -f custom.py purge));
run('rebuild', $doit, qw(-f custom.py));
run('clean', $doit, qw(clean -f custom.py));
ok(!-e 'site/index.html', 'cleaned target');
E2E::done();
