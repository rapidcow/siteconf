#!perl
#
# t/ninja.t - Makefile.in recipes in ninja syntax

use strict;
use warnings;
use Test::More tests => 14;
# Pin LANGUAGE to C so gettext does not translate the messages matched below.
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::SiteConf::Builder::Ninja;

sub cmd { RdKw::WwW::SiteConf::Builder::Ninja::_command($_[0]) }

is(cmd("\tcp a b\n"), '( cp a b )', 'one line');
is(cmd("\tcd x\n\tls\n"), '( cd x ) && ( ls )',
	'lines are commands of their own: cd does not carry over');
is(cmd("\t\@echo hi\n"), '( echo hi )', '@ is dropped');
is(cmd("\t-rm x\n\ttrue\n"), '( ( rm x ) || true ) && ( true )',
	'- ignores failure, and only of that line');
is(cmd("\tsed 's:a:b:' \\\n\t\ta > b\n"), "( sed 's:a:b:' \ta > b )",
	'a backslash joins lines (make drops one tab)');
is(cmd("\tsed 's:\$\$:x:' a\n"), q{( sed 's:$$:x:' a )}, '$$ is $ for the shell and for ninja');
is(cmd(""), '', 'nothing');
is(cmd("\n\t\n"), '', 'blank lines');

my $plan = {
	prog => 'test', D => { e => '.ok' },
	goals => [ { name => 'all', files => ['x'] } ],
	order => ['x'], dirs => [],
	node => { x => { bpath => 'site/x', recipe => [], deps => ['in/x'] } },
};
ok(!eval { RdKw::WwW::SiteConf::Builder::Ninja->_text($plan); 1 }, 'no recipe, no build');
like($@, qr/no recipe/, '... says so');

$plan->{node}{x}{recipe} = [ [ text => "\tcp \$< \$\@\n", 'x' ] ];
$plan->{node}{x}{deps} = [ 'in/x', 'a b', 'site/.ok' ];
$plan->{dirs} = [ { dir => 'site', marker => 'site/.ok', deps => [] } ];
my $text = RdKw::WwW::SiteConf::Builder::Ninja->_text($plan);
like($text, qr/^build site\/x: rule1 in\/x \| a\$ b \|\| site\/\.ok$/m,
	'input, implicit (escaped), order-only');
like($text, qr/^default all$/m, 'default goal');
like($text, qr/^build all: phony site\/x$/m, 'goal');

$plan->{node}{x}{nosrc} = 1;
$plan->{node}{x}{deps} = [ 'a b', 'site/.ok' ];
$text = RdKw::WwW::SiteConf::Builder::Ninja->_text($plan);
like($text, qr/^build site\/x: rule1 \| a\$ b \|\| site\/\.ok$/m,
	'no source, no input: the first dependency is not one');
