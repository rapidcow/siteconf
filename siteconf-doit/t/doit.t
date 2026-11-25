#!perl
use strict;
use warnings;
use Test::More tests => 11;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use RdKw::WwW::SiteConf::Builder::Doit;

my $backend = 'RdKw::WwW::SiteConf::Builder::Doit';
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
is(RdKw::WwW::SiteConf::Builder::Doit::_literal("\a\b\t\n\x0b\f\r\x1b\\n"),
	q{'\a\b\t\n\v\f\r\x1b\\\\n'}, 'short escapes and literal backslash');
unlike($file->[1], qr/^options = /m, 'no footer without options');
for my $case (
	[{clean => '', mode => 'cmdline', arg_prefix => undef, no_chdir => undef, purge => undef},
	 '-Smode=cmdline -Sarg_prefix=arg -Sno_chdir=1 -Sclean=clean -Spurge=purge'],
	[{mode => 'cmdline', arg_prefix => '', no_chdir => '0'},
	 '-Smode=cmdline -Sarg_prefix= -Sno_chdir=0'],
) {
	my ($configured) = $backend->emit({%$plan, opt => $case->[0]}, 'dodo.py');
	like($configured->[1], qr/^options = '\Q$case->[1]\E'\n\z/m, 'normalized options at EOF');
}
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
