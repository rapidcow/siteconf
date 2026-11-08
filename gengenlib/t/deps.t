#!perl
#
# t/deps.t - dependency graph

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 52;
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw( read_deps norm_deps subs_deps enroot );

my $dir = tempdir(CLEANUP => 1);
sub spew {
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
	print $fh $text;
	close $fh or die;
	"$dir/$name";
}

# --- read_deps
{
	my $f = spew('a.html', <<'HTML');
[%
# HAVE: index.html
# NEED: skel/HTML skel/FOOT
# WANT: data/x
# NEED: more
-%]
# NEED: ignored, this is body text
HTML
	is_deeply({ read_deps($f) }, {
		HAVE => 'index.html',
		NEED => [qw( skel/HTML skel/FOOT more )],
		WANT => [qw( data/x )],
	}, 'TT2 header');

	$f = spew('b.css', "/*\n * HAVE: b.css\n * NEED: c.css\n */\n");
	is_deeply({ read_deps($f) }, { HAVE => 'b.css', NEED => ['c.css'] },
		'C comment header (several lines)');

	$f = spew('c.bin', "binary\n" . ("x\n" x 40) . "# HAVE: too-late\n");
	is_deeply({ read_deps($f) }, {}, 'no header, no peeking far down');

	{
		open my $fh, '>:raw', "$dir/e.png" or die;
		print $fh "\x89PNG\r\n\x1a\n\0\xff\xfe\n# HAVE: nope\n" x 3;
		close $fh or die;
		my @w; local $SIG{__WARN__} = sub { push @w, @_ };
		is_deeply({ read_deps("$dir/e.png") }, {}, 'binary: no header');
		is_deeply(\@w, [], '... and no warnings');
	}

	$f = spew('d', "# HAVE: a\n# HAVE: b\n");
	ok(!eval { read_deps($f); 1 }, 'two HAVEs');
	like($@, qr/HAVE too many/, '... too many');
}

# --- read_deps: BASIC and DOS
{
	for my $head ("REM HAVE: a\nREM NEED: b\n", "rem HAVE: a\nrem NEED: b\n",
		"\@REM HAVE: a\n\@REM NEED: b\n", ":: HAVE: a\n:: NEED: b\n",
		"' HAVE: a\n' NEED: b\n") {
		my $f = spew('rem', "\@echo off\n$head\necho hi\n");
		is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => ['b'] },
			'header in ' . (split ' ', $head)[0]);
	}
	my $f = spew('remark', "REMEMBER HAVE: a\n");
	is_deeply({ read_deps($f) }, {}, 'REM is a word');
}

# --- norm_deps
is(norm_deps('$a/x'), '${a}/x', 'demarcating works');
is(norm_deps('${a}/x'), '${a}/x', 'idempotence');
is(norm_deps('${A}/${a}//x/./y'), '${a}//x/./y', '${A}/ dropped, no path normalization');
is(norm_deps('$A'), '', 'project root');
is(norm_deps('$B/$b/z'), '${B}/${b}/z', 'more than once');
is(norm_deps('$A//surprise'), '/surprise', 'lazy strip');

# --- norm_deps: malformed
ok(!eval { norm_deps('a$', { strict => 1 }); 1 }, 'trailing $ croaks');
like($@, qr/trailing/, '... says so');
ok(!eval { norm_deps('${a', { strict => 1 }); 1 }, 'unterminated ${ croaks');
like($@, qr/unterminated/, '... says so');
is(norm_deps('a$', { strict => 0 }), 'a${$}', 'trailing $ replaced');
is(norm_deps('${a/b', { strict => 0 }), '${$}{a/b', 'unterminated ${ replaced');
is(norm_deps('$$', { strict => 0 }), '${$}', '$$ is fine');
ok(!eval { norm_deps('a${}b', { strict => 1 }); 1 }, 'empty ${} croaks');
ok(!eval { norm_deps('a$}b', { strict => 1 }); 1 }, '$ before } croaks');
is(norm_deps('a${}b'), 'a${$}{}b', 'empty ${} replaced');
is(norm_deps('a$}b'), 'a${$}}b', '$ before } replaced');
is(norm_deps(norm_deps('${}$}$')), norm_deps('${}$}$'), 'replacement is idempotent');
ok(!eval { norm_deps('x$.y', { strict => 1 }); 1 }, '$ before a non-word croaks');
like($@, qr/stray/, '... says so');
is(norm_deps('${a-b}', { strict => 1 }), '${a-b}', 'anything goes inside braces');
is(norm_deps('x$.y'), 'x${$}.y', '$ before a non-word replaced');
is(norm_deps('$_/${a1}/$9', { strict => 1 }), '${_}/${a1}/${9}', 'word characters are names');

# --- subst_deps
is(subs_deps({ a => '.' }, '${a}/x'), 'x', 'useless dot dropped');
is(subs_deps({ a => '.' }, '${A}/${a}/x'), 'x', '${A} not consulted');
is(subs_deps({ a => 'site' }, '${a}/x'), 'site/x', 'not useless ${a} is expanded');
is(subs_deps({ a => 'site' }, '${a}/Main$$Inner.class'), 'site/Main$Inner.class', 'double dollar sign preserved');
is(subs_deps({ stuff => '.' }, 'good-${stuff}/times.html'), 'good-./times.html', 'dot in the middle of a segment kept');
is(subs_deps({ a => '.' }, 'x/${a}/y'), 'x/y', 'useless dot dropped mid-path');
is(subs_deps({}, 'a${}b$}c$'), 'a${}b$}c$', 'malformed is literal, not a variable');

# a whole directory is planted like enroot does; anything else is just text
is(subs_deps({ B => 'build/' }, '$B/abc'), 'build/abc', 'directory keeps one trailing slash');
is(subs_deps({ B => 'build//' }, '$B/abc'), 'build//abc', '... only one is the separator');
is(subs_deps({ R => '/' }, '${R}/x'), '/x', 'root directory');
is(subs_deps({ name => 'foo/' }, 'var-${name}/abc'), 'var-foo//abc', 'not a whole segment: plain text');
is(subs_deps({ B => 'build', p => '.' }, '$B/$p'), 'build/.', 'a dot is not special outside a directory');
is(subs_deps({ a => '.' }, '${a}'), '.', '... and not at the very end');
is(subs_deps({ a => '.' }, '${a}/${a}/z'), 'z', 'directories that are the current one vanish');
{
	my @bad;
	for my $B ('', '.', '/', 'build', 'build/', 'build//', '/abs', 'a/b', './x') {
		for my $p ('', 'x', 'x/', './x', '../x', '/x', '//x', '.', 'a b') {
			my $want = enroot($B) . $p;
			my $got = subs_deps({ B => $B, p => $p }, '${B}/${p}');
			push @bad, "B=`$B' p=`$p': $got, not $want" unless $got eq $want;
		}
	}
	is_deeply(\@bad, [], '${B}/${p} is enroot($B) . $p, no backtracking');
}
is(subs_deps({ a => 'v' }, 'x$a$'), 'xv$', 'bare letter and trailing dollar');
