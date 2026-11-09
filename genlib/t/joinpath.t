#!perl
#
# t/joinpath.t - joinpath, and the relative forms of // and / in locate
#
# The locate tests are written against csl-web's configuration
# (MY/option.mk) and its page source/html/cs300/pair/feed.*, which
# uses locate('//./feed.xml') and locate('//./feed.html').
#
# Rules under test: in the spec that follows `/' or `//', a leading
# run -- a single `.' or a chain of `..' -- is resolved against the
# directory of the page (so `' and `.' are the only spellings of THIS
# directory).  Every other `.' and `..' is internal and is written as
# %2E and %2E%2E.  Slashes are kept verbatim: `..' is the directory with
# its trailing slash, `../' the directory followed by one more slash,
# and `../file' the directory followed by a file.  %2F passes through.

use 5.006;
use strict;
use warnings;
use Test::More tests => 60;

use RdKw::WwW::GenLib qw( locate joinpath );

# --- joinpath
is (joinpath('a/b/c', 'd'), 'a/b/d', 'sibling of a file');
is (joinpath('a/b/', 'd'), 'a/b/d', 'child of a directory');
is (joinpath('', 'x'), 'x', 'from root');
is (joinpath('a/b/c', '.'), 'a/b/', 'dot is the directory');
is (joinpath('a/b/c', '..'), 'a/', 'dotdot is the parent');
is (joinpath('a/b/c', '..', 'x'), 'a/x', 'dotdot in its own spec');
is (joinpath('a/b/c', 'x/./y'), 'a/b/x/y', 'inner dot is resolved');
is (joinpath('a/b/c', 'x/../y'), 'a/b/y', 'inner dotdot is resolved');
is (joinpath('a/b/c', 'x/%2F/y'), 'a/b/x/%2F/y', '%2F passes through');
is (joinpath('a/b/c', '..%2F'), 'a/b/..%2F', '..%2F is not dotdot');
is (joinpath('a/b/c', './.'), 'a/b/', 'two dots are the directory');

is (joinpath('a/b/c', './x'), 'a/b/x', 'leading dot');
is (joinpath('a/b/c', '../x'), 'a/x', 'leading dotdot');
is (joinpath('a/b/c', '../../x'), 'x', 'leading dotdot chain');
is (joinpath('a/b/c', '../x/../y'), 'a/y', 'dotdot after a name');
is (joinpath('a/b/c', 'd/e', '../f'), 'a/b/f', 'one spec after another');

# --- locate, csl-web style
{
	# MY/option.mk of csl-web, and where feed.* lives
	my %O = ( base_url => '/~emeng/', site_url => 'https://pages.cs.wisc.edu' );
	my $L = 'cs300/pair/feed.html';
	my $P = 'https://pages.cs.wisc.edu/~emeng/';
	my $D = $P . 'cs300/pair/';

	# feed.html and feed.xml, verbatim
	is (locate(\%O, $L, '//./feed.xml'), $D . 'feed.xml', 'feed.html: alternate link');
	is (locate(\%O, $L, '//./feed.html'), $D . 'feed.html', 'feed.xml: channel link');

	is (locate(\%O, $L, '/./feed.xml'), '/~emeng/cs300/pair/feed.xml',
		'site-relative form');
	is (locate(\%O, $L, '//'), $P, 'site root');
	is (locate(\%O, $L, '//x'), $P . 'x', 'absolute, no run');
	is (locate(\%O, $L, '/x/'), '/~emeng/x/', 'site-relative, no run');

	# The dot: THIS directory, with as many slashes as were asked for
	is (locate(\%O, $L, '//.'), $D, 'dot is the directory');
	is (locate(\%O, $L, '//./'), $D . '/', 'dot slash: one more slash');
	is (locate(\%O, $L, '//.//'), $D . '//', 'dot, two slashes');
	is (locate(\%O, $L, '/.'), '/~emeng/cs300/pair/', 'site-relative dot');

	# The dotdot: the parent directory, same story
	is (locate(\%O, $L, '//..'), $P . 'cs300/', 'dotdot is the directory');
	is (locate(\%O, $L, '//../'), $P . 'cs300//', 'dotdot slash: two slashes');
	is (locate(\%O, $L, '//..//'), $P . 'cs300///', 'dotdot, three slashes');
	is (locate(\%O, $L, '//../x'), $P . 'cs300/x', 'dotdot then a file');
	is (locate(\%O, $L, '//../x/'), $P . 'cs300/x/', 'dotdot then a directory');
	is (locate(\%O, $L, '//../x//'), $P . 'cs300/x//', 'dotdot then two slashes');
	is (locate(\%O, $L, '//../..'), $P, 'dotdot chain');
	is (locate(\%O, $L, '//../../'), $P . '/', 'dotdot chain, two slashes');
	is (locate(\%O, $L, '//../../x'), $P . 'x', 'dotdot chain then a file');
	is (locate(\%O, $L, '//../../..'), $P, 'dotdot chain stops at base_url');
	is (locate(\%O, $L, '//../../../x'), $P . 'x', '...and keeps going down');
	is (locate(\%O, $L, '/..'), '/~emeng/cs300/', 'site-relative dotdot');
	is (locate(\%O, $L, '/../x'), '/~emeng/cs300/x', 'site-relative dotdot, file');

	# No run: slashes are verbatim here too
	is (locate(\%O, $L, '//x/'), $P . 'x/', 'one slash');
	is (locate(\%O, $L, '//x//'), $P . 'x//', 'two slashes');
	is (locate(\%O, $L, '//x///'), $P . 'x///', 'three slashes');

	# Internal dots are escaped, wherever they are
	is (locate(\%O, $L, '//x/./y'), $P . 'x/%2E/y', 'internal dot');
	is (locate(\%O, $L, '//x/../y'), $P . 'x/%2E%2E/y', 'internal dotdot');
	is (locate(\%O, $L, '//x/.'), $P . 'x/%2E', 'trailing internal dot');
	is (locate(\%O, $L, '//x/..'), $P . 'x/%2E%2E', 'trailing internal dotdot');
	is (locate(\%O, $L, '//./x/./y'), $D . 'x/%2E/y', 'after the dot');
	is (locate(\%O, $L, '//../x/../y'), $P . 'cs300/x/%2E%2E/y', 'after the dotdot');
	is (locate(\%O, $L, '//././'), $D . '%2E/', 'only the first dot is the run');
	is (locate(\%O, $L, '//./.'), $D . '%2E', 'dot after the dot');
	is (locate(\%O, $L, '//./..'), $D . '%2E%2E', 'dotdot after the dot');
	is (locate(\%O, $L, '//../.'), $P . 'cs300/%2E', 'dot after the dotdot');

	# %2F is not a slash, and %2E is not a dot (it is just what dots become)
	is (locate(\%O, $L, '//./%2F'), $D . '%2F', '%2F after the dot');
	is (locate(\%O, $L, '//x/%2F/y'), $P . 'x/%2F/y', '%2F inside');
	is (locate(\%O, $L, '//./%2E%2E'), $D . '%2E%2E', '%2E%2E passes through');
	is (locate(\%O, $L, '//..%2F'), $P . '..%2F', '..%2F starts no run');
	is (locate(\%O, $L, '//.%2F/x'), $P . '.%2F/x', '.%2F starts no run');

	# base_url need not end in a slash: parse_base accepts `/~emeng',
	# but then its last segment is taken for a file and truncated.
	my %N = ( base_url => '/~emeng', site_url => $O{site_url} );
	is (locate(\%N, $L, '//x'), 'https://pages.cs.wisc.edu/x',
		'base_url without a slash is truncated');
	is (locate(\%N, $L, '/x'), '/x', 'same, site-relative');
	is (locate(\%N, $L, '//.'), 'https://pages.cs.wisc.edu/cs300/pair/',
		'same, relative to the page');
}
