#!perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Temp qw(tempdir);
use Test::More;
use RdKw::WwW::SiteConf::Backend::Doit;
my $backend = 'RdKw::WwW::SiteConf::Backend::Doit';
my @recipe = ([text => "cd -- "], [word => '.'], [text => ' && cd sub && cp '],
	[word => 'source $'], [text => ' '], [word => '../target']);
my $plan = { prog => 'test', dirs => [], order => ['target'],
	goals => [{ name => 'all', files => ['target'] }],
	node => { target => { bpath => 'target', deps => [], recipe => \@recipe } },
	clean => [{ name => 'sweep', files => [qw(missing sub target)] }] };
my $cwd = getcwd();
chdir tempdir(CLEANUP => 1) or die $!;
mkdir 'sub' or die $!;
open my $src, '>', 'sub/source $' or die $!;
print $src "data";
close $src or die $!;
my $installed = system('doit --version >/dev/null 2>&1') == 0;
for my $mode (qw(exec cmdline prefix)) {
	$plan->{opt} = $mode eq 'prefix' ? { mode => 'cmdline', arg_prefix => 'saved' } : { mode => $mode };
	$recipe[2][1] = ' && cd sub && set -- changed; cp ' if $mode eq 'prefix';
	my ($file) = $backend->emit($plan, "$mode.py");
	my $text = $file->[1];
	if ($mode eq 'exec') {
		like($text, qr/\['cp', 'source \$', '\.\.\/target'\], '\.\/sub'/, 'direct argv and cwd');
	} elsif ($mode eq 'prefix') {
		like($text, qr/saved2=\$\{2\}; shift 2; set -- changed; cp "\$\{saved1\}"/, 'save arguments and shift');
	} else {
		like($text, qr/cp "\$\{1\}" "\$\{2\}".*'sh', 'source \$'.*'\.\/sub'/,
			'shell positional args and argv zero');
	}
	SKIP: {
		skip 'no doit', 2 unless $installed;
		open my $fh, '>', $file->[0] or die $!;
		print $fh $text;
		close $fh or die $!;
		is(system('doit', '-f', $file->[0]), 0, "build in $mode");
		is(-s 'target', 4, 'copied');
		unlink 'target' or die $! unless $mode eq 'prefix';
	}
}
SKIP: {
	skip 'no doit', 3 unless $installed;
	my $out = `doit run -f prefix.py sweep 2>&1`;
	isnt($?, 0, 'sweep fails for a directory');
	like($out, qr/W: 'sub':/, 'warning names failed path');
	ok(!-e 'target', 'sweep continued after error');
}
@recipe = ([text => 'cat '], [word => 'input file'], [text => ' > target']);
$plan->{opt} = { mode => 'exec' };
my ($fallback) = $backend->emit($plan, 'dodo.py');
like($fallback->[1], qr{\['/bin/sh', '-c', .* > target', 'sh'\]}, 'exec fallback keeps textual quoting');
@recipe = ([text => 'cd -- '], [word => 'space dir'], [text => '/sub && cat input > target']);
for my $mode (qw(shell exec cmdline)) {
	$plan->{opt} = {mode => $mode};
	my ($out) = $backend->emit($plan, 'dodo.py');
	like($out->[1], qr/'cat input > target', 'sh'\], 'space dir\/sub'/, "cwd for redirection in $mode");
	$plan->{opt}{no_chdir} = undef;
	($out) = $backend->emit($plan, 'dodo.py');
	like($out->[1], qr/'-c', '.*cd -- .*cat input > target'.*\], None/, "explicit cd in $mode");
}
@recipe = ([text => 'set -- changed; cat '], [word => 'source $']);
for my $opt ({}, {arg_prefix => undef}) {
	$plan->{opt} = {mode => 'cmdline', %$opt};
	my ($out) = $backend->emit($plan, 'dodo.py');
	like($out->[1], qr/arg1=\$\{1\}; shift 1; set -- changed; cat "\$\{arg1\}"/,
		'default prefix survives set --');
}
$plan->{opt} = {mode => 'cmdline', arg_prefix => ''};
my ($unsaved) = $backend->emit($plan, 'dodo.py');
like($unsaved->[1], qr/'-c', 'set -- changed; cat "\$\{1\}"', 'sh', 'source \$'/,
	'explicit empty prefix leaves arguments positional, without saving or shifting');
chdir $cwd or die $!;
done_testing();
