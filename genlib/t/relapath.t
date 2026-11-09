#!perl
#
# t/relapath.t - relapath, and relative locate

use 5.006;
use strict;
use warnings;
use Test::More tests => 32;

use RdKw::WwW::GenLib qw( locate relapath );

# From cooper-www, gen/t/02-url.t
# relapath
is (relapath('snake.html', 'index.html'), 'snake.html',
	'index.html => snake');
is (relapath('snake.html', ''), 'snake.html',
	'(root) => snake');
is (relapath('snake.html', 'art/index.html'), '../snake.html',
	'art/index.html => snake');
# Example by code
is (relapath('foo/path/', 'foo/base'), 'path/',
	'foo/base as a file');
is (relapath('foo/path', 'foo/base/'), '../path',
	'foo/base as a directory');

# Exact match: $path and $base run out together, so nothing
# should be swallowed by the strict-prefix correction below.
is (relapath('a/b/c', 'a/b/c'), '',
	'exact match is empty');

# (regression tests by Anthropic Claude)
# $path is a strict prefix of $base's directory chain (i.e. we
# are linking to an ancestor of the current directory).  This
# used to lose $path's own trailing component, since the
# comparison loop ran off the end of @path -- without a
# genuine mismatch -- while @base still had more left, and
# that overrun got miscounted as a shared component.
is (relapath('a/b', 'a/b/c/d'), '../../b',
	'path is an ancestor of base (shallow)');
is (relapath('a', 'a/b/c'), '../../a',
	'path is an ancestor of base (root)');

# $base is a strict prefix of $path's directory chain (the
# mirror image: $base's own dropped filename got miscounted as
# matching a real directory in $path).
is (relapath('a/b/c/d', 'a/b'), 'b/c/d',
	'base is an ancestor of path');

# Directory-like results: `..' is already a directory, so the first
# trailing slash after it is omitted.  Every further slash is kept
# verbatim (as is every slash after a name), and a `.' is just a name.
my $deep = 'trivnote/libexpr/index.html';
is (relapath('trivnote', $deep), '../../trivnote', 'file namespace');
is (relapath('trivnote/', $deep), '..', 'dir: one slash omitted');
is (relapath('trivnote//', $deep), '../', 'dir: second slash kept');
is (relapath('trivnote///', $deep), '..//', 'dir: third slash kept');
is (relapath('', $deep), '../..', 'root, empty');
is (relapath('.', $deep), '../../.', 'dot is a name');
is (relapath('./', $deep), '../.././', 'dot slash');
is (relapath('.//', $deep), '../.././/', 'dot double slash');
is (relapath('./.', $deep), '../.././.', 'dots are names');
is (relapath('./trivnote/', $deep), '../.././trivnote/', 'dot is not redundant');
is (relapath('a/./b', 'x/y/z'), '../../a/./b', 'inner dots are kept');
is (relapath('.x', $deep), '../../.x', 'a dotfile is not a dot');
is (relapath('archive/', $deep), '../../archive/', 'sibling dir keeps slash');
is (relapath('archive//', $deep), '../../archive//', 'extra slash after a name');
is (relapath('archive///', $deep), '../../archive///', 'many slashes after a name');
is (relapath('a//b/', $deep), '../../a//b/', 'inner empty segment is kept');

# --- locate
{
	my %O = ( base_url => '/', site_url => 'https://example.test' );
	my $L = 'a/b.html';
	is(locate(\%O, $L, 'c.html'), '../c.html', 'locate, relative');
	is(locate(\%O, $L, '/c.html'), '/c.html', 'locate, host-relative');
	is(locate(\%O, $L, '//c.html'), 'https://example.test/c.html', 'locate, absolute');
	is(locate(\%O, $L, 'c/'), '../c/', 'nothing is done to the spec');
	is(locate(\%O, $L, './c.html'), 'c.html', 'manual "./" relative path');
	is(locate(\%O, $L, './%2E/c.html'), '%2E/c.html', 'a literal dot is spelled %2E');
	is(locate(\%O, $L, '../c.html'), '../c.html', 'manual "../" relative path');
}
