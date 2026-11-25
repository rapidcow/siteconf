#!perl
#
# t/names.t - Task builds files with names that YAML, Go templates, the
# shell or a glob would read as something else, and only when needed

use utf8;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
# Pin LANGUAGE to C so gettext does not translate the messages matched below.
BEGIN { $ENV{LANGUAGE} = 'C' }
use File::Temp qw( tempdir );
use RdKw::I18N::CodeSets;
use RdKw::WwW::SiteConf::Builder::Task;
use Tools qw( task_cmd );

my $task = task_cmd();
system("$task --version >/dev/null 2>&1") == 0 or plan skip_all => "no task";
local $ENV{T_CODESETS} = 'filesys:UTF-8,argv:UTF-8';
RdKw::I18N::CodeSets->locale->parse_from_env('T_CODESETS', prog => 't');

my @name = ('a b', '$HOME', 'x*', '{{y}}', 'NULL', "caf\x{e9}", q(q'u"o\\te), 'p[1]?', '~t',
	'(&;|<>`)', "t\tab", '!bang', '#hash', 'd e/f', 'a.b', 'a-b', ']', '-n', '!', '=');
my $i = 0;
my (%node, @order);
for my $src (@name) {
	my $out = "out/$src";
	my $key = 'n' . ++$i;
	(my $mark = $out) =~ s{[^/]*\z}{.ok};
	$node{$key} = { bpath => $out, deps => [ $src, $mark ],
		recipe => [ [ text => "\tcp -- ", $key ], [ word => $src, $key ], [ text => ' ', $key ],
			[ word => $out, $key ], [ text => "\n", $key ] ] };
	push @order, $key;
}
plan tests => 9 + @name;

my $plan = {
	prog => 'test', args => [], D => { e => '.ok' }, clean => [], opt => {},
	dirs => [ { dir => 'out', marker => 'out/.ok', deps => [] },
		{ dir => 'out/d e', marker => 'out/d e/.ok', deps => [ 'out/.ok' ] } ],
	goals => [ { name => 'all', files => [ @order ] } ], order => \@order, node => \%node,
};
my $dir = tempdir(CLEANUP => 1);
sub fs { my $s = $_[0]; utf8::encode($s); "$dir/$s" }
sub put { mkdir fs($_[0] =~ m{(.*)/} ? $1 : '.'); open my $fh, '>', fs($_[0]) or die "$_[0]: $!"; print $fh $_[1]; close $fh }
put($_, "1 $_") for @name;
put('Taskfile.yml', RdKw::WwW::SiteConf::Builder::Task->_text($plan));

sub run_task { my $out = `cd '$dir' && $task 2>&1`; $? == 0 or diag $out; diag $out if $ENV{T_SHOW}; $out }
run_task();
is(scalar(() = run_task() =~ /up to date/g), @name + 2, 'built, then up to date (the markers too)')
	or diag `cat '$dir/Taskfile.yml'`;
for (@name) {
	open my $fh, '<', fs("out/$_") or do { fail("out/$_: $!"); next };
	is(scalar(<$fh>), "1 $_", "built: " . join(' ', map { /[!-~]/ ? $_ : sprintf 'U+%04X', ord } split //, $_));
}
sleep 1;
put('{{y}}', 'new');
my $out = run_task();
is(scalar(() = $out =~ /up to date/g), $#name + 2, 'one source is newer: the others are up to date');
like($out, qr/^task: \[file:out\/%7b%7by%7d%7d\]/m, '... and that one is not');
open my $fh, '<', fs('out/{{y}}') or die;
is(scalar(<$fh>), 'new', '... and is made again');

# -Smkpath=1: each task makes its directory
$plan->{opt} = { mkpath => 1 };
put('Taskfile.yml', RdKw::WwW::SiteConf::Builder::Task->_text($plan));
system('rm', '-rf', "$dir/out") == 0 or die;
run_task();
is(scalar(grep { -f fs("out/$_") } @name), scalar(@name), '-Smkpath=1: all built');
ok(!-e fs('out/.ok'), '... with no marker');
$plan->{opt} = {};

# A recipe that failed runs again, as make would run it
$plan->{goals} = [ { name => 'all', files => ['z'] } ];
$plan->{order} = ['z'];
$plan->{node} = { z => { bpath => 'z', deps => ['zin'],
	recipe => [ [ text => "\ttest ! -e fail\n\tcp -- zin z\n", 'z' ] ] } };
put('zin', 'old');
put('Taskfile.yml', RdKw::WwW::SiteConf::Builder::Task->_text($plan));
run_task();
sleep 1;
put('zin', 'new');
put('fail', '');
`cd '$dir' && $task 2>&1`;
ok($? != 0, 'a recipe fails');
unlink fs('fail');
like(run_task(), qr/^task: \[file:z\]/m, '... and runs again');
open $fh, '<', fs('z') or die;
is(scalar(<$fh>), 'new', '... to the end');
