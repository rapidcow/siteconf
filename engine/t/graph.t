#!perl
#
# t/graph.t - header paths, and edges to what we make ourselves

use strict;
use warnings;
use Test::More tests => 202;
use FindBin;
use lib "$FindBin::Bin/lib";
use E2E qw( lines );
use Cwd ();
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make escape_dep );
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

	# ... but a # that is not followed by a space is not a comment
	$dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: x \\\n  #y \\\n  # c\n  z\n" . $recipe,
	});
	$rules = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->_read_rules;
	{
		no warnings 'qw';
		is_deeply($rules->{'a.html'}{deps}, [qw(x #y z)], '#y is a word, "# c" a comment');
	}

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

# --- an absolute B: ${B}/${b}/x is still something we make
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${B}/${b}/b.css ]] ),
		'html/b.css' => lines( HAVE => [qw[ ${A}/${a}/b.css ]] ),
	}, B => 'build');
	for my $B ("$dir/build", Cwd::abs_path("$dir/build")) {
		write_make("$dir/build/MY/config.mk", {
			A => '..', B => $B, a => 'html', b => 'site', c => 'site',
			R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, 'test');
		my $plan = eval { plan_of($dir, "$dir/build") };
		ok($plan && $plan->{order} && "@{ $plan->{order} }" eq 'b.css a.html',
			"B = $B: its own files are made first") or diag $@;
	}
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
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( HAVE => [qw[ ${A}/${a}/a.html ]], NEED => [qw[ ${tem}/base/head.html ]] ),
		'temple/base/head.html' => '',
	}, tem => 'temple');
	my $plan = eval { plan_of($dir) };
	ok($plan && grep({ $_ eq 'temple/base/head.html' } @{ $plan->{node}{'a.html'}{deps} }),
		'any configured variable: ${tem}') or diag $@;
}
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

# --- ${a} alone as the first prerequisite: no source, nothing implied
{
	for my $form ('${a}', '${a}/', '${a}///', '${A}/${a}/', '$a/', '$A/$a') {
		my $dir = project({
			MANIFEST => "MAKE all\n\tNEED stamp\n",
			'Makefile.in' => "stamp: $form \${A}/x\n\ttouch \${\@}\n",
		});
		my $plan = eval { plan_of($dir) };
		ok($plan, "no source: $form") or diag $@;
		is_deeply($plan && $plan->{node}{stamp}{deps}, [qw(x site/.ok)],
			'... nothing from html/ is needed');
		ok($plan && $plan->{node}{stamp}{nosrc}, '... and the node says so');
	}

	# ${A}// is not ${A}/: the slashes may not come between the symbols,
	# so this is the absolute path /html/q.html, not a source
	my $abs = project({
		MANIFEST => "MAKE all\n\tNEED p.html\n",
		'Makefile.in' => "p.html: \${A}//\${a}/q.html\n\ttrue\n",
		'html/p.html' => '', 'html/q.html' => '',
	});
	eval { plan_of($abs) };
	like($@, qr{NEEDs `/html/q\.html'}, '${A}//${a}/ is not a source');

	# not first: the directory, as a prerequisite, like before
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED a.html\n",
		'Makefile.in' => "a.html: \${A}/x \${a}\n\ttrue\n",
		'html/a.html' => '',
	});
	is_deeply(plan_of($dir)->{node}{'a.html'}{deps}, [qw(html/a.html x html site/.ok)],
		'${a} that is not first is just a prerequisite');

	# ${<} has nothing to say
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED stamp\n",
		'Makefile.in' => "stamp: \${a}/\n\ttouch \${<}\n",
	});
	eval { plan_of($dir) };
	like($@, qr/line 2: \$\{<\}: this rule has no source/, '${<} without a source');

	# what follows ${a}/ is read as it was written, any slashes between
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED p/x.html\n",
		'Makefile.in' => "p/x.html: \${a}//\$\@ \${A}/x\n\ttrue\n",
		'html/p/x.html' => '',
	});
	is_deeply(plan_of($dir)->{node}{'p/x.html'}{deps}, [qw(html/p/x.html x site/p/.ok)],
		'${a}//$@ is the source (a bare $@ is the target)');

	# targets: every spelling, any slashes
	for my $form ('x.html', '${b}/x.html', '${B}/${b}//x.html', '$b/x.html') {
		$dir = project({
			MANIFEST => "MAKE all\n\tNEED x.html\n",
			'Makefile.in' => "$form:\n\ttrue\n",
			'html/x.html' => '',
		});
		my $plan = eval { plan_of($dir) };
		ok($plan, "target: $form") or diag $@;
	}
	$dir = project({
		MANIFEST => "MAKE all\n\tNEED x.html\n",
		'Makefile.in' => "\${A}/x.html:\n\ttrue\n",
		'html/x.html' => '',
	});
	eval { plan_of($dir) };
	like($@, qr/a target is a name/, 'a target in ${A} is still not a target');
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
	is($warn->($dir), <<MSG, 'a missing WANT in a source header');
W: target `a.html' WANTs `site/c.css'
W:   (in header of `html/a.html')
W: ... but it is missing; going on without it :(
MSG

	$dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${A}/tool\n\ttrue\n",
		'html/a.html' => '',
		'tool' => lines( WANT => [qw[ gen/Mod.pm ]] ),
	});
	is($warn->($dir), <<MSG, '... and in the header of a tool');
W: target `a.html' WANTs `gen/Mod.pm'
W:   (in header of `tool')
W: ... but it is missing; going on without it :(
MSG
		
}

# --- headers of source files we NEED are read, too (like gcc -MM);
# what we make is not: its prerequisites are for the rules to say
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( NEED => [qw[ ${A}/html/t/outer ]] ),
		'html/t/outer' => lines( NEED => [qw[ ${B}/${b}/b.css ${A}/html/t/inner ]],
			WANT => [qw[ ${A}/html/t/gone ]] ),
		'html/t/inner' => lines( NEED => [qw[ ${A}/html/t/outer ${A}/html/t/leaf ]] ),
		'html/t/leaf' => '',
		'html/b.css' => lines( NEED => [qw[ ${A}/html/bdep ]] ), 'html/bdep' => '',
	});
	my $plan = eval { plan_of($dir) };
	is($@, '', 'headers of headers: cycles and soft files are fine');
	my $deps = $plan->{node}{'a.html'}{deps};
	ok((grep { $_ eq 'html/t/leaf' } @$deps), 'a NEED of a NEED is a dependency');
	ok((grep { $_ eq 'site/b.css' } @$deps), '... including what is made');
	is_deeply($plan->{node}{'a.html'}{kids}, ['b.css'], '... and it is a kid of the page');
	ok(!(grep { $_ eq 'html/bdep' } @$deps),
		'what we make is not read: its NEEDs are none of the page\'s business');
}

# --- ... and a NEED stays a NEED however far down it is found: a file seen
# first as a WANT (of x) and later as a NEED (of w) still has hard NEEDs
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( NEED => [qw[ ${A}/html/t/x ${A}/html/t/w ]] ),
		'html/t/x' => lines( WANT => [qw[ ${A}/html/t/z ]] ),
		'html/t/w' => lines( NEED => [qw[ ${A}/html/t/z ]] ),
		'html/t/z' => lines( NEED => [qw[ ${A}/html/t/gone ]] ),
	});
	my $plan = eval { plan_of($dir) };
	like($@, qr/NEEDs `html\/t\/gone' \(in header of `html\/t\/z'\)/,
		'what a NEED of a NEED NEEDs is missing: that is a failure');
	is(scalar(() = $@ =~ /NEEDs `html\/t\/gone'/g), 1, '... said once');

	# all of it soft stays soft
	$dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( NEED => [qw[ ${A}/html/t/x ]] ),
		'html/t/x' => lines( WANT => [qw[ ${A}/html/t/z ]] ),
		'html/t/z' => lines( NEED => [qw[ ${A}/html/t/gone ]] ),
	});
	$plan = plan_of($dir);
	ok($plan->{node}{'a.html'}{ok}, 'but what a WANT NEEDs is only wanted');
}

# --- NEED: and WANT: in Makefile.in: said before anything is expanded,
# in capitals, with nothing in between; nothing else before a colon
{
	my $rule = sub {
		my ($deps, %f) = @_;
		my $dir = project({
			MANIFEST => $manifest,
			'Makefile.in' => "a.html: $deps\n\ttrue\nb.css:\n\ttrue\n",
			'html/a.html' => '', 'html/b.css' => '', y => '', %f,
		});
		my $plan = eval { plan_of($dir) };
		($plan, $@);
	};
	my ($p, $err) = $rule->('NEED:${A}/x WANT:${A}/gone WANT:${A}/y ${A}/y');
	is_deeply($p && $p->{node}{'a.html'}{deps}, [qw( html/a.html x y site/.ok )],
		'NEED: is needed, WANT: kept if there, dropped if not') or diag $err;

	($p, $err) = $rule->('WANT:${B}/${b}/b.css WANT:${B}/${b}/c.css');
	is_deeply($p && $p->{node}{'a.html'}{deps}, [qw( html/a.html site/b.css site/.ok )],
		'WANT: of what we make (or cannot)') or diag $err;
	is_deeply($p && $p->{node}{'a.html'}{kids}, ['b.css'], '... is an edge when it can be made');

	($p, $err) = $rule->('NEED:${A}/gone');
	like($err, qr/NEEDs `gone' \(prerequisite in \S*Makefile\.in line 1\), which we don't seem to have/,
		'NEED: is as firm as no prefix at all');

	($p, $err) = $rule->('NEED:NEED:', 'NEED:' => '');
	is_deeply($p && $p->{node}{'a.html'}{deps}, [ 'html/a.html', 'NEED:', 'site/.ok' ],
		'NEED:NEED: is the file NEED:') or diag $err;

	($p, $err) = $rule->('NEED:${a}/y.txt', 'html/y.txt' => '');
	is_deeply($p && $p->{node}{'a.html'}{deps}, [qw( html/a.html html/y.txt site/.ok )],
		'a first prerequisite with a prefix is not the source');

	($p, $err) = $rule->('WANT:${A}/tool', tool => lines( NEED => [qw[ gen/Mod.pm ]] ));
	is_deeply($p && $p->{node}{'a.html'}{deps}, [qw( html/a.html tool site/.ok )],
		'what a WANTed tool NEEDs is only wanted') or diag $err;

	for my $bad ('need:x', 'Want:x', 'USE:x', 'x:y', ':x', 'NEED-ONLY:x') {
		($p, $err) = $rule->($bad);
		like($err, qr/a prerequisite must either NEED: or WANT: before a colon/, "rejected: $bad");
	}
	($p, $err) = $rule->('NEED:');
	like($err, qr/`NEED:' of nothing/, 'NEED: of nothing');
	($p, $err) = $rule->('NEED: ${A}/x');
	like($err, qr/`NEED:' of nothing/, '... no space after it');
	($p, $err) = $rule->('${A}/${a:S/h/h/}/a.html NEED:${A}/${a:Q}/b.css');
	ok($p, 'a colon in ${...} is no prefix') or diag $err;
}

# --- a $ in a name, escaped in a header as GenGenLib escapes it
{
	my $dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${A}/t\$\$ool\n\ttrue\n",
		'html/a.html' => lines( NEED => [ 'd${$}/x', 'd$$/y' ] ),
		'd$/x' => '', 'd$/y' => '',
		't$ool' => "# HAVE: t\${\$}ool\n",
	});
	my $plan = eval { plan_of($dir) };
	is_deeply($plan && $plan->{node}{'a.html'}{deps}, [ 'html/a.html', 't$ool', 'd$/x', 'd$/y', 'site/.ok' ],
		'$$ and ${$} are a $, in headers too') or diag $@;
	$dir = project({ MANIFEST => $manifest, 'html/a.html' => lines( NEED => [ 'x$' ] ) });
	ok(!eval { plan_of($dir) }, 'a lone $ is still stray');
	like($@, qr/stray \$ in `x\$'/, '... and says so');
	require RdKw::WwW::SiteConf::GMake;
	my %emit = ( %{ $plan || {} }, prog => 'test', clean => [], dirs => [], goals => [] );
	like(eval { RdKw::WwW::SiteConf::GMake->_emit(\%emit) },
		qr/^site\/a\.html: html\/a\.html t\$\$ool d\$\$\/x d\$\$\/y site\/\.ok$/m,
		'... and $$ to GNU make') or diag $@;
	ok(!eval { RdKw::WwW::SiteConf::Make->_emit(\%emit) },
		'... but no $ to make (bmake reads $$ twice)');
	like($@, qr/^E: make cannot name `t\$ool' \(with `\$' in it\); GNU make can \(-G gmake\)$/,
		'... and says so, and who can');
}

# --- ${U+hex}: a character, by its code point, in headers too
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => lines( NEED => [ 'd${U+0020}x', 'd${u+23}h', '${A}/d${U+1F600}', 'd${U+002F}y' ] ),
		'd x' => '', 'd#h' => '', "d\xf0\x9f\x98\x80" => '', 'd/y' => '',
	});
	my $plan = eval { plan_of($dir) };
	is_deeply($plan && $plan->{node}{'a.html'}{deps},
		[ 'html/a.html', 'x', 'd x', 'd#h', "d\x{1F600}", 'd/y', 'site/.ok' ],
		'${U+...} is that character, in any case and of any length') or diag $@;
	for my $bad ('${U+110000}', '${U+}', '${U+-1}', '${U+123456789}', '${U+G}') {
		$dir = project({ MANIFEST => $manifest, 'html/a.html' => lines( NEED => [ "x$bad" ] ) });
		ok(!eval { plan_of($dir) } && $@ =~ /\Q$bad\E is no code point/, "no code point: $bad")
			or diag $@;
	}
	my %emit = ( %{ $plan || {} }, prog => 'test', clean => [], dirs => [], goals => [] );
	like(eval { RdKw::WwW::SiteConf::GMake->_emit(\%emit) },
		qr/^site\/a\.html: html\/a\.html x d\\ x d\\#h d\x{1F600} d\/y site\/\.ok$/m,
		'GNU make: escaped') or diag $@;
	ok(!eval { RdKw::WwW::SiteConf::Make->_emit(\%emit) }
		&& $@ =~ /make cannot name `d x' \(with U\+0020 in it\); GNU make can/,
		'make: a space cannot be') or diag $@;
	require RdKw::WwW::SiteConf::Ninja;
	like(eval { RdKw::WwW::SiteConf::Ninja->_emit(\%emit) },
		qr/^build site\/a\.html: rule1 html\/a\.html \| x d\$ x d#h d\x{1F600} d\/y \|\| site\/\.ok$/m,
		'ninja: escaped') or diag $@;
}

# --- ... and in Makefile.in, as render's own example has it
{
	my $dir = project({
		MANIFEST => $manifest,
		'Makefile.in' => "a.html: \${A}/t\${U+0023}o\${u+21}l\n\ttrue\n",
		'html/a.html' => '', 't#o!l' => "# HAVE: t\${U+0023}o!l\n",
	});
	my $plan = eval { plan_of($dir) };
	is_deeply($plan && $plan->{node}{'a.html'}{deps}, [ 'html/a.html', 't#o!l', 'site/.ok' ],
		'${U+...} in a prerequisite') or diag $@;
	$dir = project({ MANIFEST => $manifest, 'Makefile.in' => "a.html: \${U+D800000}\n\ttrue\n",
		'html/a.html' => '' });
	ok(!eval { plan_of($dir) } && $@ =~ /\$\{U\+D800000\} is no code point/,
		'... that is no code point') or diag $@;
}

# --- what each generator cannot name, it says so
{
	require RdKw::WwW::SiteConf::GMake;
	require RdKw::WwW::SiteConf::Ninja;
	my %gmake = (
		'a b' => 'a\\ b', "a\tb" => "a\\\tb", 'a#b' => 'a\\#b', 'a:b' => 'a\\:b',
		'a|b' => 'a\\|b', 'a$b' => 'a$$b', 'a*b' => 'a[*]b', 'a?b' => 'a[?]b',
		'a[b]' => 'a[[]b]', '~a' => './~a', 'a\\b' => 'a\\b', 'a\\ b' => 'a\\\\\\ b',
		'a\\*b' => 'a\\\\[*]b', 'a%b' => 'a%b', 'a(b' => 'a(b', 'a~' => 'a~',
	);
	for my $name (sort keys %gmake) {
		is(eval { RdKw::WwW::SiteConf::GMake->_name($name) }, $gmake{$name}, "GNU make: `" . escape_dep($name) . "'")
			or diag $@;
	}
	for my $name ("a\nb", "a\rb", "a\fb", "a\x{2028}b", 'a;b', 'a=b', 'a\\', 'a(b)') {
		ok(!defined eval { RdKw::WwW::SiteConf::GMake->_name($name) }
			&& $@ =~ /\AE: GNU make cannot name/, "GNU make cannot: `" . escape_dep($name) . "'");
	}
	is(RdKw::WwW::SiteConf::Make->_name("a+b,c\x{e9}\x{a0}%\\d"), "a+b,c\x{e9}\x{a0}%\\d",
		'make: what needs no escape is as it is');
	ok(!defined eval { RdKw::WwW::SiteConf::Make->_name('a;b') }
		&& $@ =~ /make cannot name `a;b' \(with `;' in it\)$/, '... and there is no -G gmake for some');
	for my $name ("a\nb", "a\rb", "a\x{2028}b", 'a|b') {
		ok(!defined eval { RdKw::WwW::SiteConf::Ninja::_path($name) }
			&& $@ =~ /\AE: ninja cannot name/, "ninja cannot: `" . escape_dep($name) . "'");
	}
	is(RdKw::WwW::SiteConf::Ninja::_path("a b:c\$d\te#f"), "a\$ b\$:c\$\$d\te#f", 'ninja: escaped');
}
