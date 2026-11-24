#!perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use RdKw::WwW::SiteConf::Backend::Doit;

my $backend = 'RdKw::WwW::SiteConf::Backend::Doit';
my $name = "out/\x{8336} \x{1f40d} %'\$\$\n";
my $plan = {
	prog => 'test', dirs => [], order => ['x'],
	goals => [ { name => 'all', files => ['x'] } ],
	node => { x => { bpath => $name, deps => ['input'], recipe => [
		[ text => "\t-false\n\tcd /\n\tcat input > " ], [ word => $name ],
	] } },
};
my ($file) = $backend->emit($plan, 'dodo.py');
like($file->[1], qr/\A# -\*- coding: utf-8 -\*-\n/, 'coding cookie');
unlike($file->[1], qr/[^\x00-\x7f]/, 'ASCII only');
like($file->[1], qr/\\u8336.*\\U0001f40d/, 'code point escapes');
SKIP: {
	system('doit --version >/dev/null 2>&1') == 0 or skip 'no doit', 4;
	my $cwd = getcwd();
	chdir tempdir(CLEANUP => 1) or die $!;
	open my $py, '>', 'dodo.py' or die $!;
	print $py $file->[1];
	close $py or die $!;
	open my $in, '>', 'input' or die $!;
	print $in "first\n";
	close $in or die $!;
	is(system('doit'), 0, 'run Unicode recipe');
	utf8::encode($name);
	ok(-f $name, 'shell wrote the declared target');
	open $in, '>>', 'input' or die $!;
	print $in "second\n";
	close $in or die $!;
	is(system('doit'), 0, 'rebuild changed input');
	is(-s $name, -s 'input', 'updated output');
	chdir $cwd or die $!;
}
done_testing();
