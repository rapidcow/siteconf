#!perl
#
# t/string.t - string literals: ${"..."}

use utf8;
use 5.008;
use strict;
use warnings;
use Test::More tests => 25;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

use RdKw::WwW::GenGenLib qw( scan_string unescape_var norm_dep subs_dep );

is_deeply([ scan_string('"a b" rest') ], [ 'a b', ' rest' ], 'a string and what follows');
is_deeply([ scan_string('"\a\b\t\n\v\f\r\e\s\\\\\""') ],
	[ "\a\b\t\n\cK\f\r\e \\\"", '' ], 'the escapes');
is_deeply([ scan_string('"\x{8868}\x{1F600}\x{3b1}"x') ],
	[ "\x{8868}\x{1F600}\x{3b1}", 'x' ], '\x{...}');
is((scan_string('"$}{"'))[0], '$}{', 'nothing else is special');
is_deeply([ scan_string('abc') ], [], 'not a string: nothing');
is_deeply([ scan_string('""') ], [ '', '' ], 'an empty string');
for my $bad ('"abc', '"\q"', '"\x{110000}"', '"\x{}"', '"a\\"') {
	ok(!eval { scan_string($bad); 1 }, "scan_string: $bad is an error");
	like($@, qr/\Ascan_string: /, '... said by name');
}

is(unescape_var('a${"\s"}b${"表"}${""}'), "a b表", 'unescape_var: a string');
is(unescape_var('a${"\q"}b'), 'a${"\q"}b', '... a bad one is left alone');

is(norm_dep('x/${"a b"}'), 'x/a${U+0020}b', 'norm_dep: what is safe is kept');
is(subs_dep(undef, 'x/${"a\sb}"}y', on_missing => 'croak'), 'x/a b}y', 'subs_dep: braces in it');
is(subs_dep({ a => 'A' }, '${a}/${"\s"}'), 'A/ ', 'next to a variable');
is(norm_dep('${""}'), '', 'an empty string is nothing');
ok(!eval { norm_dep('${"\q"}', strict => 1); 1 }, 'strict: bad escape is an error');
ok(!eval { norm_dep('${"abc', strict => 1); 1 }, 'strict: not closed is an error');
like(norm_dep('${"abc'), qr/\A\$\{\$\}\{"abc\z/, 'not strict: spelled out');

done_testing;
