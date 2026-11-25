#!perl
#
# t/e2e-task.t - siteconf -i, ./configure,
# siteconf -g -G task, task; on siteconf's t/fixture/web

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use E2E;
use Tools qw( task_cmd );

my $script = E2E::setup();
my $task = task_cmd();
system("$task --version >/dev/null 2>&1") == 0 or plan skip_all => "no task";
plan tests => 13;

run('siteconf -i', $^X, $script, qw( -i -P web -Osite_url=https://example.test -SB=build -q
	-MRdKw::WwW::GenLib=0 ));
mkdir 'build' or die "mkdir: $!";
run('./configure', $^X, './configure', '-q');

run('siteconf -g -G task', $^X, $script, qw( -g -q -G task -Sclean -B build -t all -t basic ));
run('task basic', $task, '-d', 'build', 'basic');
ok(-f 'build/site/sub/index.html', 'task basic: sub built');
ok(!-e 'build/site/robots.txt', 'task basic: only the subset');
like(slurp('build/site/sub/index.html'), qr/location=sub\/index\.html/, 'task: O.location');
unlike(run('task again', $task, '-d', 'build', 'basic'), qr/^task: \[/m, 'task: incremental');
run('task (default goal)', $task, '-d', 'build');
ok(-f 'build/site/robots.txt', 'task all');
run('task clean', $task, '-d', 'build', 'clean');
ok(!-e 'build/site/index.html', 'task clean');

E2E::done();
