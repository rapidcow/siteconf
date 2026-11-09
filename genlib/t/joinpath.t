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
# directory of the page.  Once the run ends, every `.' and `..' is
# kept symbolically, and %2F passes through untouched.
#
# Cases wrapped in TODO currently fail; see the notes beside them.

use 5.006;
use strict;
use warnings;
use Test::More tests => 47;

use RdKw::WwW::GenLib qw( locate joinpath );

# --- joinpath
is (joinpath('a/b/c', 'd'), 'a/b/d', 'sibling of a file');
is (joinpath('a/b/', 'd'), 'a/b/d', 'child of a directory');
is (joinpath('', 'x'), 'x', 'from root');
is (joinpath('a/b/c', '.'), 'a/b/', 'dot is the directory');
is (joinpath('a/b/c', '..'), 'a/', 'dotdot is the parent');
is (joinpath('a/b/c', '..', 'x'), 'a/x', 'dotdot in its own spec');
is (joinpath('a/b/c', 'x/./y'), 'a/b/x/./y', 'inner dot is kept');
is (joinpath('a/b/c', 'x/../y'), 'a/b/x/../y', 'inner dotdot is kept');
is (joinpath('a/b/c', 'x/%2F/y'), 'a/b/x/%2F/y', '%2F passes through');
is (joinpath('a/b/c', '..%2F'), 'a/b/..%2F', '..%2F is not dotdot');
is (joinpath('a/b/c', './.'), 'a/b/.', 'only the first dot is special');

is (joinpath('a/b/c', './x'), 'a/b/x', 'leading dot');
is (joinpath('a/b/c', '../x'), 'a/x', 'leading dotdot');
is (joinpath('a/b/c', '../../x'), 'x', 'leading dotdot chain');
is (joinpath('a/b/c', '../x/../y'), 'a/x/../y', 'run ends at x');
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

	# The dot
	is (locate(\%O, $L, '//.'), $D, 'dot is the directory');
	is (locate(\%O, $L, '//././'), $D . './', 'second dot is literal');
	is (locate(\%O, $L, '//.//'), $D . '/', 'extra slash is kept');
	is (locate(\%O, $L, '//./x/./y'), $D . 'x/./y', 'inner dots are kept');

	# The dotdot
	is (locate(\%O, $L, '//..'), $P . 'cs300/', 'dotdot');
	is (locate(\%O, $L, '//../..'), $P, 'dotdot chain');
	is (locate(\%O, $L, '//../../..'), 'https://pages.cs.wisc.edu/',
		'dotdot chain leaves base_url');
	is (locate(\%O, $L, '/..'), '/~emeng/cs300/', 'site-relative dotdot');

	# After the run
	is (locate(\%O, $L, '//x/../y'), $P . 'x/../y', 'no run, dotdot kept');

	# %2F is not a slash, and %2E is not a dot
	is (locate(\%O, $L, '//./%2F'), $D . '%2F', '%2F after the dot');
	is (locate(\%O, $L, '//x/%2F/y'), $P . 'x/%2F/y', '%2F inside');
	is (locate(\%O, $L, '//..%2F'), $P . '..%2F', '..%2F starts no run');
	is (locate(\%O, $L, '//.%2F/x'), $P . '.%2F/x', '.%2F starts no run');

	# (`//.' gives the directory but `//./' gives feed.html itself)
	is (locate(\%O, $L, '//./'), $D, 'dot slash is the directory');
	is (locate(\%O, $L, '//./.'), $D . '.', 'dot after the dot');
	is (locate(\%O, $L, '//../'), $P . 'cs300/', 'dotdot slash');
	is (locate(\%O, $L, '//..//'), $P . 'cs300//', 'dotdot extra slash');
	is (locate(\%O, $L, '//../x'), $P . 'cs300/x', 'dotdot then name');
	is (locate(\%O, $L, '//../../x'), $P . 'x', 'dotdot chain then name');
	is (locate(\%O, $L, '//../.'), $P . 'cs300/.', 'dot after dotdot');
	is (locate(\%O, $L, '//../x/../y'), $P . 'cs300/x/../y',
		'run ends at x');
	is (locate(\%O, $L, '//./..'), $D . '..', 'dotdot after the dot');
	is (locate(\%O, $L, '/../x'), '/~emeng/cs300/x', 'site-relative, dotdot then name');

	# base_url need not end in a slash: parse_base accepts `/~emeng'.
	local $TODO = 'joinpath takes the last segment of base_url for a file';
	my %N = ( base_url => '/~emeng', site_url => $O{site_url} );
	is (locate(\%N, $L, '//x'), $P . 'x', 'base_url without a slash');
	is (locate(\%N, $L, '/x'), '/~emeng/x', 'same, site-relative');
}
