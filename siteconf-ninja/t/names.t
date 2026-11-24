#!perl
#
# t/names.t - what ninja can name, and how

use strict;
use warnings;
use Test::More tests => 5;
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( escape_dep );
use RdKw::WwW::SiteConf::Backend::Ninja;

for my $name ("a\nb", "a\rb", "a\x{2028}b") {
	ok(!defined eval { RdKw::WwW::SiteConf::Backend::Ninja::_path($name) }
		&& $@ =~ /\AE: ninja cannot name/, "ninja cannot: `" . escape_dep($name) . "'");
}
is(RdKw::WwW::SiteConf::Backend::Ninja::_path("a b:c\$d\te#f|g"), "a\$ b\$:c\$\$d\te#f\${pipe}g", 'escaped');
is(RdKw::WwW::SiteConf::Backend::Ninja::_path(q(a%b\\c<d>"e'f`g&h(i){j})), q(a%b\\c<d>"e'f`g&h(i){j}),
	'the rest as they are');
