#!perl
#
# t/graph.t - header paths, and edges to what we make ourselves

use strict;
use warnings;
use Test::More tests => 99;
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E qw( lines );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;

# A project in a directory of its own.  %f is name => contents.
sub project {
	my ($f, %D) = @_;
	my $dir = tempdir(CLEANUP => 1);
	$f->{'Makefile.in'} = "a.html b.css c.css: \${A}/x\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n"
		unless exists $f->{'Makefile.in'};
	for my $name (keys %$f) {
		(my $d = "$dir/$name") =~ s!/[^/]*\z!!;
		make_path($d);
		open my $fh, '>', "$dir/$name" or die "$name: $!";
		print $fh $f->{$name};
		close $fh or die;
	}
	make_path("$dir/" . ($D{B} || '.') . "/MY");
	write_make("$dir/" . ($D{B} || '.') . "/MY/config.mk", {
		A => '.', B => '.', a => 'html', b => 'site', c => $D{c} || $D{b} || 'site',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok', %D }, 'test');
	$f->{x} = '' ;
	open my $fh, '>', "$dir/x" or die; close $fh;
	$dir;
}
sub plan_of {
	my ($dir, $B) = @_;
	RdKw::WwW::SiteConf->new(B => $B || $dir, quiet => 1)->plan;
}
my $manifest = "MAKE all\n\tNEED a.html\n";

# --- continued target and dependency lists (including tab indentation)
{
	my $recipe = "\tcp \${a}/\${\@} \\\n\t  \${B}/\${b}/\${\@}\n";
	my $dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "# rules\n\na.html \\\n\t b.css \\\n  c.css: \\\n\t\${A}/x \\\n  \${A}/y\n" . $recipe,
		'html/a.html' => '', y => '',
	});
	my $sc = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1);
	my $rules = $sc->_read_rules;
	is_deeply([sort keys %$rules], [qw(a.html b.css c.css)], 'continued target list');
	is_deeply($rules->{'b.css'}{deps}, [qw(x y)], 'continued dependencies and substitution');
	is($rules->{'c.css'}{line}, 3, 'rule records its first physical line');
	is($rules->{'a.html'}{recipe}, "\tcp html/a.html \\\n\t  site/a.html\n",
		'recipe continuations are preserved');
	my $plan = $sc->plan;
	is_deeply($plan->{node}{'a.html'}{deps}, [qw(html/a.html x y site/.ok)],
		'continued rule participates in the build graph');

	# comment lines between the pieces of a header are skipped
	$dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html \\\n  # one\n b.css \\\n\t: \\\n# two\n    # three\n\t\${A}/x\n" . $recipe,
		'html/a.html' => '',
	});
	$rules = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->_read_rules;
	is_deeply([sort keys %$rules], [qw(a.html b.css)], 'comments inside a continued target list');
	is_deeply($rules->{'b.css'}{deps}, ['x'], 'comments before the dependencies');

	for my $case (
		["# rules\na.html \\\n  b.css: \${missing}\n", qr/line 2: undefined variable/],
		["# rules\na.html: \\\n", qr/line 2: unfinished line continuation/],
	) {
		my $bad = project({ MANIFEST => $manifest, 'Makefile.in' => $case->[0] });
		eval { plan_of($bad) };
		like($@, $case->[1], 'continued-rule error identifies the starting line');
	}
}

# --- an edge to what we make: it is made, and first
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${B}/${b}/b.css ]] ),
		'html/b.css' => lines( HAVE => [qw[ ${A}/${a}/b.css ]], NEED => [qw[ ${B}/${b}/c.css ]] ),
		'html/c.css' => lines( HAVE => [qw[ $A/$a/c.css ]] ),
	});
	my $plan = plan_of($dir);
	is_deeply($plan->{order}, [qw( c.css b.css a.html )],
		'what is needed is made first');
	is_deeply($plan->{goals}[0]{files}, ['a.html'], 'but the goal is what it says');
	is_deeply($plan->{node}{'a.html'}{deps}, [qw( html/a.html x site/b.css site/.ok )],
		'a.html needs site/b.css') or diag explain $plan->{node}{'a.html'}{deps};
	is_deeply($plan->{node}{'b.css'}{deps}[2], 'site/c.css', 'and so on');
	ok(!grep({ /^MY\// } @{ $plan->{node}{'a.html'}{deps} }), 'no MY/ in it');
}

# --- a cycle
{
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED b.css\n",
		'html/b.css' => lines( NEED => [qw[ ${B}/${b}/c.css ]] ),
		'html/c.css' => lines( NEED => [qw[ ${B}/${b}/b.css ]] ),
	});
	ok(!eval { plan_of($dir); 1 }, 'cycle: dies');
	like($@, qr/dependency cycle: b\.css -> c\.css -> b\.css/, '... showing it');
}

# --- an edge to something that cannot be made
{
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED a.html\n\tWANT b.css\n",
		'html/a.html' => lines( NEED => [qw[ ${B}/${b}/c.css ]] ),
		'html/b.css' => lines( WANT => [qw[ ${B}/${b}/c.css ]] ),
		# no html/c.css
	});
	ok(!eval { plan_of($dir); 1 }, 'NEED of the unmakeable: dies');
	like($@, qr/goal `all' NEEDs `a\.html', but cannot be made:\nE: {3}NEEDs `site\/c\.css' \(in header of `html\/a\.html'\), but cannot be made:\nE: {5}Source `html\/c\.css' is missing \(rule at \S*Makefile\.in line 1\)/,
		'... and why, a cause per line, deeper as it goes');

	$dir = project({
		MANIFEST => "MAKE all\n\tNEED b.css\n\tWANT a.html\n",
		'html/b.css' => "",
		'html/a.html' => lines( NEED => [qw[ ${B}/${b}/c.css ]] ),
	});
	my $plan = plan_of($dir);
	is_deeply($plan->{goals}[0]{files}, ['b.css'], 'WANT of what needs the unmakeable: dropped');
}

# --- what a header may say
sub bad {
	my ($header, $re, $what) = @_;
	my $dir = project({ MANIFEST => $manifest, 'html/a.html' => $header });
	ok(!eval { plan_of($dir); 1 }, "$what: dies");
	like($@, $re, "$what: says why");
}
bad(lines( HAVE => [qw[ a.html ]] ), qr/You HAVE `a\.html'.*\nE: but I need `html\/a\.html'/, 'HAVE is the path from the root');
bad(lines( HAVE => [qw[ ${A}/${a}/b.html ]] ), qr/but I need `html\/a\.html'/, 'HAVE of another file');
bad(lines( NEED => [qw[ ${b}/b.css ]] ), qr/\$\{b\} is relative to \$\{B\}/, 'bare ${b}');
bad(lines( NEED => [qw[ $b/b.css ]] ), qr/\$\{b\} is relative to \$\{B\}/, 'bare $b');
bad(lines( NEED => [qw[ ${z}/b.css ]] ), qr/no such variable \$\{z\}/, 'no such variable');
bad(lines( NEED => [qw[ x$/y ]] ), qr/stray \$/, 'stray dollar');
bad(lines( NEED => [qw[ MY/option.mk ]] ), qr/\(is it \$\{B\}\/MY\/option\.mk\?\)/, 'the old MY/');

{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( HAVE => [qw[ $A/$a/a.html ]], NEED => [qw[ ${A}/x ${B}/MY/config.mk x ]] ),
	});
	ok(eval { plan_of($dir); 1 }, '${A}, ${B}/MY, and plain names are fine') or diag $@;
}

# --- out of tree: the root is not where the build is
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${B}/${b}/b.css x ${B}/MY/config.mk ]] ),
		'html/b.css' => "",
	}, A => '..', B => 'build');
	my $plan = plan_of($dir, "$dir/build");
	is($plan->{node}{'a.html'}{apath}, '../html/a.html', 'apath is seen from the build dir');
	is_deeply($plan->{node}{'a.html'}{deps},
		[qw( ../html/a.html ../x site/b.css MY/config.mk site/.ok )],
		'and so are the rest') or diag explain $plan->{node}{'a.html'}{deps};
}

# --- b is the build dir itself (-Db=.)
{
	my $dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html b.css: \${A}/x\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n",
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${B}/${b}/b.css ${B}/MY/config.mk ]] ),
		'html/b.css' => '',
	}, b => '.');
	my $plan = eval { plan_of($dir) };
	ok($plan, 'b = `.\': plans') or diag $@;
	is_deeply($plan->{node}{'a.html'}{kids}, ['b.css'],
		'b = `.\': what we make is an edge') if $plan;
	ok(!$plan->{node}{'MY/config.mk'}, 'b = `.\': MY/config.mk is not ours to make') if $plan;
}

# --- a is the root itself (-Da=.)
{
	my $dir = project({
		MANIFEST => $manifest,
		'a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${B}/${b}/b.css ]] ),
		'b.css' => '',
	}, a => '.');
	my $plan = eval { plan_of($dir) };
	ok($plan, 'a = `.\': plans') or diag $@;
	is($plan->{node}{'a.html'}{apath}, 'a.html', 'a = `.\': apath') if $plan;
	is_deeply($plan->{node}{'a.html'}{kids}, ['b.css'], 'a = `.\': HAVE agrees, and edges') if $plan;
}

# --- what the rule's prerequisites (tools) say in their headers
{
	my $rules = "a.html: \${A}/gen/tool \${A}/plain\n\tgen/tool \${a}/\${\@} \${B}/\${b}/\${\@}\n";
	my %f = (
		MANIFEST => $manifest,
		'Makefile.in' => $rules,
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]] ),
		'gen/tool' => lines( HAVE => [qw[ gen/tool ]], NEED => [qw[ gen/lib/Mod.pm ${B}/MY/option.mk ]],
			WANT => [qw[ gen/maybe ]] ) . "print 1;\n",
		'gen/lib/Mod.pm' => "1;\n",
		'MY/option.mk' => '',
		plain => "no header here\n",
	);
	my $dir = project({ %f });
	my $plan = eval { plan_of($dir) };
	ok($plan, 'tools: plans') or diag $@;
	is_deeply($plan->{node}{'a.html'}{deps},
		[qw( html/a.html gen/tool plain gen/lib/Mod.pm MY/option.mk site/.ok )],
		'tools: a header NEED is an edge, a missing WANT is not, no header is fine') if $plan;

	my %g = %f;
	delete $g{'gen/lib/Mod.pm'};
	$dir = project(\%g);
	eval { plan_of($dir) };
	like($@, qr/NEEDs `gen\/lib\/Mod\.pm' \(in header of `gen\/tool'\), which we don't seem to have/, 'tools: a missing NEED is fatal');

	$dir = project({ %f, 'gen/tool' => lines( HAVE => [qw[ gen/other ]] ) });
	eval { plan_of($dir) };
	like($@, qr/gen\/tool: You HAVE `gen\/other'.*\nE: but I need `gen\/tool' \(for the rule for `a\.html', \S*Makefile\.in line 1\)\?/, 'tools: HAVE must agree');

	$dir = project({ %f, 'gen/tool' => "\x00\x01\x02# NEED: nowhere\n" x 4 });
	$plan = eval { plan_of($dir) };
	ok($plan && !grep({ $_ eq 'nowhere' } @{ $plan->{node}{'a.html'}{deps} }),
		'tools: a binary is not read') or diag $@;
}

# --- with or without ${A}, absolute or not: the same file
{
	my %f = (
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${A}/gen/tool\n\tgen/tool\n",
		'gen/tool' => '',
	);
	for my $A ('..', 'abs') {
		for my $have ('gen/tool', '${A}/gen/tool', '$A/./gen//tool') {
			my $dir = project({ %f, 'gen/tool' => lines( HAVE => [ $have ] ),
				'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]] ) }, B => 'build');
			write_make("$dir/build/MY/config.mk", {
				A => $A eq 'abs' ? $dir : $A, B => 'build', a => 'html', b => 'site', c => 'site',
				R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, 'test');
			my $plan = eval { plan_of($dir, "$dir/build") };
			ok($plan, "A = $A: tool HAVE $have") or diag $@;
		}
	}

	# Absolute A, logically: a symlink under the root (say, to an annex)
	# is not followed, and neither is a root reached through one.
SKIP:	{
		eval { symlink("",""); 1 } or skip "No symlink", 2;

		my $ext = tempdir(CLEANUP => 1);
		my $link = tempdir(CLEANUP => 1) . '/root';
		my $dir = project({ %f, 'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]] ) },
			B => 'build');
		unlink "$dir/gen/tool"; rmdir "$dir/gen" or die "rmdir: $!";
		open my $fh, '>', "$ext/tool" or die;
		print $fh lines( HAVE => [qw[ gen/tool ]] );
		close $fh or die;
		symlink($ext, "$dir/gen") && symlink($dir, $link) or die "symlink: $!";
		for my $A ($dir, $link) {
			write_make("$dir/build/MY/config.mk", {
				A => $A, B => 'build', a => 'html', b => 'site', c => 'site',
				R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, 'test');
			my $plan = eval { plan_of($dir, "$dir/build") };
			ok($plan, ($A eq $dir ? 'absolute A' : 'A through a symlink')
				. ': symlinked gen/ is not resolved') or diag $@;
		}
	}

	# a is absolute (out of tree): ${A}/${a} is still ${a}
	my $src = tempdir(CLEANUP => 1);
	for my $f ('a.html', 'b.css') {
		open my $fh, '>', "$src/$f" or die;
		print $fh lines( HAVE => [ $f eq 'a.html' ? '${A}/${a}/a.html' : '${a}/b.css' ],
			NEED => $f eq 'a.html' ? [qw[ ${A}/${a}/b.css ]] : [] );
		close $fh or die;
	}
	my $dir = project({ MANIFEST => $manifest, 'Makefile.in' => "a.html:\n\tcp\n" }, a => $src);
	my $plan = eval { plan_of($dir) };
	ok($plan, 'absolute a: HAVE with or without ${A}') or diag $@;
	ok($plan && grep({ $_ eq "$src/b.css" } @{ $plan->{node}{'a.html'}{deps} }),
		'absolute a: ${A}/${a}/x NEEDs the right file') or diag explain $plan->{node}{'a.html'}{deps};
}

# --- _target, by b
{
	my $sc = sub { bless { D => { b => $_[0] }, rules => { x => 1, 'd/x' => 1 } }, 'RdKw::WwW::SiteConf' };
	my $dot = $sc->('.');
	is($dot->_target('x'), 'x', 'b = `.\': a file');
	is($dot->_target('d/x'), 'd/x', 'b = `.\': a file in a directory');
	ok(!defined $dot->_target('y'), 'b = `.\': no rule, not ours');
	ok(!defined $dot->_target($_), "b = `.': `$_' is not ours") for '.', '..', '../x', '/x', 'MY/config.mk', 'MY/option.mk';
	is($sc->('site')->_target('site/x'), 'x', 'b = site: a file');
	ok(!defined $sc->('site')->_target('x'), 'b = site: outside');
}

# --- the first prerequisite, if in ${a}, is the source: nothing is implied
{
	my @form = ('${A}/${a}/${@:R}', '${a}/${@:R}', '$A/$a/${@:R}', '$a/${@:R}');
	for my $form (@form) {
		my $dir = project({
			MANIFEST => "MAKE all\n\tNEED p/x.md.html\n",
			'Makefile.in' => "p/x.md.html: $form \${A}/x\n\tconv \${<} \${.IMPSRC} \${\@}\n",
			'html/p/x.md' => '',
		});
		my $plan = plan_of($dir);
		is_deeply($plan->{node}{'p/x.md.html'}{deps}, [qw(html/p/x.md x site/p/.ok)],
			"source named first: $form (no html/p/x.md.html needed)");
		is($plan->{node}{'p/x.md.html'}{recipe}, "\tconv p/x.md p/x.md p/x.md.html\n",
			'${<} is the source, relative to ${a}') if $form eq $form[0];
	}

	# not first: an ordinary prerequisite, and the implied source stays
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED a.html\n",
		'Makefile.in' => "a.html: \${A}/x \${a}/b.css\n\ttrue\n",
		'html/a.html' => '', 'html/b.css' => '',
	});
	is_deeply(plan_of($dir)->{node}{'a.html'}{deps}, [qw(html/a.html x html/b.css site/.ok)],
		'a source that is not first is a prerequisite');

	# ${a}/${@} is the implied source, spelled out
	$dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${a}/\${\@} \${A}/x\n\ttrue\n",
		'html/a.html' => '',
	});
	is_deeply(plan_of($dir)->{node}{'a.html'}{deps}, [qw(html/a.html x site/.ok)],
		'${a}/${@} is the implied source');

	# its header HAVE is checked against the source it has
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED s.css\n",
		'Makefile.in' => "s.css: \${a}/s.scss\n\ttrue\n",
		'html/s.scss' => lines( HAVE => [qw[ ${A}/${a}/s.scss ]] ),
	});
	is_deeply(plan_of($dir)->{node}{'s.css'}{deps}, [qw(html/s.scss site/.ok)],
		'a HAVE of the source it has');
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED s.css\n",
		'Makefile.in' => "s.css: \${a}/s.scss\n\ttrue\n",
		'html/s.scss' => lines( HAVE => [qw[ ${A}/${a}/s.css ]] ),
	});
	eval { plan_of($dir) };
	like($@, qr/You HAVE .*s\.css.*need `html\/s\.scss'/s, 'a HAVE of another');

	# the source is missing
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED s.css\n",
		'Makefile.in' => "s.css: \${a}/s.scss\n\ttrue\n",
	});
	eval { plan_of($dir) };
	like($@, qr/Source `html\/s\.scss' is missing/, 'missing source is named');

	# ${<} cannot be in a prerequisite
	$dir = project({ MANIFEST => $manifest, 'Makefile.in' => "a.html: \${<}\n\ttrue\n" });
	eval { plan_of($dir) };
	like($@, qr/line 1: \$\{<\} is not known here/, '${<} in prerequisites');
}

# --- the cache: ${c}
{
	my $rules = "\${c}/x.md.html: \${a}/\${\@:R}\n\tpandoc -o \${B}/\${c}/\${\@} \${<}\n"
		. "x.html: \${B}/\${c}/x.md.html\n\tcp \${B}/\${c}/x.md.html \${B}/\${b}/\${\@}\n";
	my %f = (
		MANIFEST => "MAKE all\n\tNEED x.html\n",
		'Makefile.in' => $rules,
		'html/x.md' => '',
		'html/x.html' => lines( NEED => [qw[ ${B}/${c}/x.md.html ]] ),
	);
	my $dir = project({%f}, c => 'cache/deep');
	my $plan = plan_of($dir);
	is_deeply($plan->{order}, ['${c}/x.md.html', 'x.html'], 'the cache is made first');
	my $c = $plan->{node}{'${c}/x.md.html'};
	is($c->{bpath}, 'cache/deep/x.md.html', 'cache target is in ${c}');
	is_deeply($c->{deps}, [qw(html/x.md cache/deep/.ok)], 'no implied html/x.md.html');
	is($c->{recipe}, "\tpandoc -o cache/deep/x.md.html x.md\n"
		=> '${@} is the name after ${c}/; ${B}/${c} too');
	is_deeply($plan->{node}{'x.html'}{kids}, ['${c}/x.md.html'], 'the site depends on the cache');
	is($plan->{node}{'x.html'}{bpath}, 'site/x.html', 'and is still in ${b}');
	is_deeply([map { $_->{dir} } @{ $plan->{dirs} }], [qw(cache cache/deep site)],
		'all of ${c} gets a marker, the parents first');
	is_deeply($plan->{goals}[0]{files}, ['x.html'], 'only the site is a goal');
	is_deeply($plan->{clean}[0]{files}, ['cache/deep/x.md.html', 'site/x.html'],
		'clean takes the cache too');

	# c defaults to b: then ${c}/x is x, the same node
	$dir = project({%f});
	$plan = plan_of($dir);
	is_deeply($plan->{order}, [qw(x.md.html x.html)], 'with no ${c}, it is ${b}');
	is($plan->{node}{'x.md.html'}{bpath}, 'site/x.md.html', 'in the site');

	# ${b}/ is a spelling of the default
	$dir = project({ MANIFEST => $manifest,
		'Makefile.in' => "\${b}/a.html: \${A}/x\n\ttrue\n", 'html/a.html' => '' });
	is_deeply(plan_of($dir)->{node}{'a.html'}{deps}, [qw(html/a.html x site/.ok)], '${b}/ target');

	# nowhere else under ${B}
	for my $bad ('${B}/other/a.html', 'other/${@}', '${a}/a.html') {
		$dir = project({ MANIFEST => $manifest, 'Makefile.in' => "$bad: \${A}/x\n\ttrue\n" });
		eval { plan_of($dir) };
		like($@, qr/nowhere else|bad file name/, "target $bad is refused");
	}

	# the manifest cannot name what is in the cache alone
	$dir = project({ MANIFEST => "MAKE all\n\tNEED x.md.html\n",
		'Makefile.in' => $rules, 'html/x.md' => '', 'html/x.html' => '' }, c => 'cache');
	eval { plan_of($dir) };
	like($@, qr/NEEDs `x\.md\.html', but cannot be made:\nE: {3}No rule to make it/, 'cache files are not goals');

	$dir = project({%f}, c => '/abs');
	eval { plan_of($dir) };
	like($@, qr/`c' prefix must be a relative path/, 'c is relative');
}

# --- c is always configured
{
	my $dir = project({ MANIFEST => $manifest, 'html/a.html' => '' });
	open my $fh, '<', "$dir/MY/config.mk" or die;
	my $t = do { local $/; <$fh> }; close $fh;
	$t =~ s/^c=.*\n//m;
	open $fh, '>', "$dir/MY/config.mk" or die; print $fh $t; close $fh;
	eval { plan_of($dir) };
	like($@, qr/config\.mk: `c' is missing\.  Try reconfiguring/, 'no c, no plan');
}

# --- a WANT that is missing: said once, with where it was said
{
	my $warn = sub {
		my ($dir) = @_;
		my $err = '';
		open my $save, '>&', \*STDERR or die;
		close STDERR; open STDERR, '>', \$err or die;
		eval { RdKw::WwW::SiteConf->new(B => $dir)->plan };
		close STDERR; open STDERR, '>&', $save or die;
		$err;
	};
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( WANT => [qw[ ${B}/${b}/c.css ]] ),
	});
	is($warn->($dir), "W: `a.html' WANTs `site/c.css' (in header of `html/a.html'), but it is missing; going on without it :(\n",
		'a missing WANT in a source header');

	$dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${A}/tool\n\ttrue\n",
		'html/a.html' => '',
		'tool' => lines( WANT => [qw[ gen/Mod.pm ]] ),
	});
	is($warn->($dir), "W: `a.html' WANTs `gen/Mod.pm' (in header of `tool'), but it is missing; going on without it :(\n",
		'... and in the header of a tool');
}
