#!perl
#
# t/file2uri.t - file2uri and uri2file

use 5.006;
use strict;
use warnings;
use Test::More tests => 23;

use RdKw::WwW::GenLib qw( file2uri uri2file relapath );

my $resume = "r\x{e9}sum\x{e9}.html";
my $resume_uri = 'r%C3%A9sum%C3%A9.html';

# file2uri: characters are UTF-8, however Perl stores them
is (file2uri($resume), $resume_uri, 'e-acute is UTF-8');
my $upgraded = $resume;
utf8::upgrade($upgraded);
is (file2uri($upgraded), $resume_uri, '... stored as UTF-8 too');
is (file2uri("r\x{100}"), 'r%C4%80', 'U+0100');
is (file2uri("\x{4e2d}/\x{1f600}"), '%E4%B8%AD/%F0%9F%98%80', 'CJK and astral');
is (file2uri("doc/$resume"), "doc/$resume_uri", 'slash separates');
is (file2uri('a/b c/%#?;x.html'), 'a/b%20c/%25%23%3F%3Bx.html', 'URI characters are escaped');
is (file2uri('a/b/'), 'a/b/', 'trailing slash is kept');
is (file2uri(''), '', 'empty is empty');
is (file2uri("a\\r\x{e9}", os => 'MSWin32'), 'a/r%C3%A9', 'os: backslash separates on MSWin32');
ok (!eval { file2uri("\x{d800}"); 1; }, 'a lone surrogate dies');
like ($@, qr/\Afile2uri: cannot encode file name "\\x\{d800\}" in UTF-8: .+\n\z/,
	'... saying what, and why');
ok (!eval { file2uri("\x{d800}", prog => 'E'); 1; }, '... prog');
like ($@, qr/\AE: cannot encode /, '... says who');

# uri2file: escapes are UTF-8, in either case
is (uri2file($resume_uri), $resume, 'UTF-8 escapes');
is (uri2file('r%c3%a9sum%c3%a9.html'), $resume, '... in lower case');
is (uri2file("doc/$resume_uri"), "doc/$resume", 'slash separates');
is (uri2file('a/r%C3%A9', os => 'MSWin32'), "a\\r\x{e9}", 'os: backslash on MSWin32');
ok (!eval { uri2file('a%2Fb/c'); 1; }, 'no file has a slash in its name');
like ($@, qr/\Auri2file: `a%2Fb\/c': URI not representable in /, '... saying so');
ok (!eval { uri2file('r%E9'); 1; }, 'Latin-1 escape dies');
like ($@, qr/\Auri2file: cannot decode file name "r\\x\{e9\}" in UTF-8: .+\n\z/,
	'... saying what, and why');
is (uri2file(file2uri("\x{4e2d}/$resume")), "\x{4e2d}/$resume", 'round trip');

# What relapath compares is the URI.
is (relapath(file2uri("\x{4e2d}/"), file2uri("\x{4e2d}/$resume")), '.',
	'relapath of file2uri');
