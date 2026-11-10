#!perl
#
# t/deps.t - dependency graph

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 128;
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw( read_deps norm_dep norm_deps subs_deps subs_dep
	escape_dep escape_deps split_dep enroot );

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

# --- read_deps: other people's fields, and what a name is
{
	my $f = spew('use', "# HAVE: a\n# USE: Template\n# NEED-ONLY: x\n# vim: ft=perl\n# NEED: b\nbody\n");
	is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => ['b'] },
		'fields not ours do not end the header');
	$f = spew('copy', "# Copyright: me\n\n# HAVE: a\n");
	is_deeply({ read_deps($f) }, { HAVE => 'a' }, '... nor do they begin it');
	$f = spew('case', "# Have: a\n# need: b\n# NEED: c\n");
	is_deeply({ read_deps($f) }, { NEED => ['c'] }, 'our fields are in capitals');
	$f = spew('blank', "#\tHAVE\t:\ta\n#   NEED :b\tc  d\n");
	is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => [qw( b c d )] },
		'blanks: any number, either kind, before and after the colon');
	$f = spew('nbsp', "# HAVE: non\x{a0}break\n# NEED: ideo\x{3000}graphic x\x{c}y\n");
	is_deeply({ read_deps($f) }, { HAVE => "non\x{a0}break",
		NEED => [ "ideo\x{3000}graphic", "x\x{c}y" ] },
		'names split at blanks only');
	$f = spew('crlf', "# HAVE: a\r\n# NEED: b c\r\n");
	is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => [qw( b c )] }, 'CRLF');
	$f = spew('later', "x = 1  # NEED: a.html  -- why: b\n");
	is_deeply({ read_deps($f) }, { NEED => [qw( a.html -- why: b )] },
		'the first comment that works is the one');
	$f = spew('theorem', "theorem NEED: a\n");
	is_deeply({ read_deps($f) }, {}, 'REM, still a word after anything');
	$f = spew('nospace', "#HAVE: a\n");
	is_deeply({ read_deps($f) }, {}, 'a blank is still necessary');
	$f = spew('far', ("# x: y\n" x 40) . "# HAVE: a\n");
	is_deeply({ read_deps($f) }, {}, 'no peeking far down past fields either');
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

# --- norm_deps: pass-through
{
	for my $spec ('a$', '${a/b', 'a${}b', 'a$}b', 'x$.y', '$@') {
		is(norm_deps($spec, { pass_thru => 1 }), $spec,
			"pass through $spec");
		is(norm_deps($spec, { strict => 0, pass_thru => 1 }), $spec,
			"explicitly lenient pass through $spec");
		for my $pass_thru (0, 1) {
			ok(!eval { norm_deps($spec, { strict => 1, pass_thru => $pass_thru }); 1 },
				"strict rejects $spec with pass_thru=$pass_thru");
		}
	}
	is(norm_deps('$@', { pass_thru => 0 }), '${$}@', 'disabled pass-through escapes');
	is(norm_deps('$A/$@/$b/$$/${unknown}', { pass_thru => 1 }),
		'$@/${b}/${$}/${unknown}', 'recognized syntax still normalized');
	is(norm_deps('$a', { strict => 1, pass_thru => 1 }), '${a}',
		'valid input accepts both options');
	is_deeply([norm_deps('$@', '$A/$b', 'a$', { pass_thru => 1 })],
		['$@', '${b}', 'a$'], 'pass-through in list context');
	is(scalar norm_deps('$@', '$b', { pass_thru => 1 }), '$@',
		'scalar context still returns first spec');
	is(norm_dep('$@/$a', pass_thru => 1), '$@/${a}', 'singular wrapper forwards option');
	is(norm_deps(norm_deps('$@/$a/$$/a$', { pass_thru => 1 }), { pass_thru => 1 }),
		'$@/${a}/${$}/a$', 'pass-through normalization is idempotent');
	is(subs_deps({ a => 'v' }, '$@/$a/a$', { pass_thru => 1 }), '$@/v/a$',
		'substitution continues after preserved syntax');
	is(subs_deps({ a => '.' }, '$@/$a/x', { pass_thru => 1 }), '$@/x',
		'substitution tracks path segments after preserved syntax');
	is(subs_deps({ a => 'v' }, '${}/$a/$}', { pass_thru => 1 }), '${}/v/$}',
		'substitution continues after empty braces');
}

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

# --- escape_dep: a literal name, read as that name and nothing else
{
	is(escape_dep('a$b'), 'a${$}b', 'escape_dep: a $ is ${$}');
	is_deeply([ escape_deps('$x', 'y') ], [ '${$}x', 'y' ], 'escape_deps: each');
	my @bad;
	for my $name ('$', '$$', '${a}/x', '$a/x', '${A}/x', '$A', '${', '}$', 'x/${$}/y', '${B}/${b}/z') {
		my $spec = escape_dep($name);
		my $back = subs_dep({ a => 'NO', A => 'NO', B => 'NO', b => 'NO' }, $spec, strict => 1);
		my ($root) = split_dep($spec);
		push @bad, "$name: $back, root `$root'" if $back ne $name or length $root;
	}
	is_deeply(\@bad, [], '... whatever the definitions, with no root');
	is(subs_dep(undef, escape_dep('a$b/$c')), 'a$b/$c', 'subs_dep without definitions undoes it');
	is(subs_dep(undef, '${x}/y'), 'y', '... and a variable is empty, as ever');
	is(escape_dep('plain/name'), 'plain/name', 'nothing to escape, nothing escaped');
}

# --- ${U+hex}: a character by its code point, and what escape_dep
# spells with it
{
	is(escape_dep("a b\tc"), 'a${U+0020}b${U+0009}c', 'a blank is its code point');
	is(escape_dep("r\x{e9}sum\x{e9}"), 'r${U+00E9}sum${U+00E9}', '... and so is what is not ASCII');
	is(escape_dep("\x{1F600}"), '${U+1F600}', '... of as many digits as it takes');
	is(escape_dep('{}!~'), '{}!~', 'printable ASCII is as it is');
	is(escape_dep("r\x{e9}\x{1F600}", unicode => 1), "r\x{e9}\x{1F600}", 'unicode => 1: as it is');
	is(escape_dep("\x{7f}\x{85}\x{d800}\x{2028}\x{2029}", unicode => 1),
		'${U+007F}${U+0085}${U+D800}${U+2028}${U+2029}',
		'... but for controls, surrogates and line breaks');
	is(escape_dep("\x{a0}\x{3000}", unicode => 1), '${U+00A0}${U+3000}', '... and white space');
	is(escape_dep("\x{a0}\x{3000}\x{2028} \t", unicode => 1, unicode_space => 1),
		"\x{a0}\x{3000}" . '${U+2028}${U+0020}${U+0009}',
		'unicode_space => 1: white space too, but no blank or line break');
	is_deeply([ escape_deps("\x{e9}", "\x{a0}", { unicode => 1 }) ], [ "\x{e9}", '${U+00A0}' ],
		'escape_deps: options last');

	is(norm_dep('${u+e9}${U+0000041}'), '${U+00E9}${U+0041}', 'norm_dep: in capitals, of 4 digits or more');
	is(subs_dep(undef, '${U+0024}{a}${u+20}'), '${a} ', 'subs_dep: the character, and only that');
	is(subs_dep({ a => 's' }, '${U+002E}${U+002E}/${a}/x'), '../s/x', '${U+002E}${U+002E}/ is ../');
	is(subs_dep({ a => 's' }, '${U+002F}${a}/x'), '/s/x', '${U+002F} is a slash, before a directory too');
	is_deeply([ split_dep('${U+0041}/x') ], [ '', '${U+0041}/x' ], 'split_dep: no root');
	is_deeply([ split_dep('${a}/${U+0041}/x') ], [ '${a}', '${U+0041}/x' ], '... after one either');
	for my $bad ('${U+110000}', '${U+}', '${U+123456789}', '${U+x}', '${u+-1}') {
		ok(!defined eval { norm_dep("x$bad", strict => 1) } && $@ =~ /is no code point/,
			"strict: no code point: $bad");
	}
	(my $lit = '${U+110000}') =~ s/\A\$/\${\$}/;
	is(norm_dep('${U+110000}'), $lit, 'not strict: a literal $');
	is(norm_dep('${U+110000}', pass_thru => 1), '${U+110000}', 'pass_thru: as it is');
	is(subs_dep(undef, '${U+110000}'), '${U+110000}', '... and so subs_dep gives it back');
	require RdKw::WwW::GenGenLib;
	ok(!RdKw::WwW::GenGenLib::follow_ok({ a => 's' }, '${a}/${U+002E}${U+002E}/${U+002E}${U+002E}/etc'),
		'follow_ok: a climb by code point is a climb');
	ok(!RdKw::WwW::GenGenLib::follow_ok({}, '${U+002F}etc'), '... and so is the root');

	# Through a header, which is split at blanks: what is escaped is
	# one name, and that name
	my @c = (' ', "\t", "\x{a0}", "\x{2028}", "\x{85}", "\x{1F600}", "\x{e9}",
		'{', '}', '$', '/', 'a', '${a}', "\x{7f}", "\x{3000}", 'U+', '#');
	my @bad;
	srand 42;
	for (1 .. 2000) {
		my $name = join '', map { $c[rand @c] } 0 .. rand 6;
		for my $opt ({}, { unicode => 1 }, { unicode => 1, unicode_space => 1 }) {
			spew('esc', "# NEED: " . escape_dep($name, %$opt) . "\n");
			my %I = read_deps("$dir/esc");
			my @n = @{ $I{NEED} || [] };
			my $back = @n == 1 && subs_dep({ a => 'NO' }, $n[0], strict => 1);
			push @bad, sprintf('%vX', $name) if !defined $back || $back ne $name;
		}
	}
	is_deeply(\@bad, [], 'escape_dep, read_deps, subs_dep: the name, whatever is in it');
}
