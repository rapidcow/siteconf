#!perl
#
# t/graph.t - header paths, and edges to what we make ourselves

use strict;
use warnings;
use Test::More tests => 51;
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
		A => '.', B => '.', a => 'html', b => 'site',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok', %D }, 'test');
	$f->{x} = '' ;
	open my $fh, '>', "$dir/x" or die; close $fh;
	$dir;
}
sub plan_of {
	my ($dir, $B) = @_;
	RdKw::WwW::SiteConf->new(B => $B || $dir, quiet => 1)->plan;
}
# Right now read_deps is kind of dumb: we have
# to pad it with "something" before or it won't
# see the declaration line. 6_6
#
# (I've been too spoiled by scripting languages,
# so sorry....)
sub html5_lines
{
	my $what = "HAVE";
	'<!DOCTYPE html>' . "\n" .
	"<!--\n" .
	join ("", map { my @s = defined ? (" # $what: $_\n") : (); $what = "NEED"; @s } @_) .
	"  -->\n";
}
sub css_lines
{
	my $what = "HAVE";
	'@charset "UTF-8";' . "\n" .
	"/*\n" .
	join ("", map { my @s = defined ? (" * $what: $_\n") : (); $what = "NEED"; @s } @_) .
	" */\n";
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
		'html/a.html' => html5_lines( qw[ ${A}/${a}/a.html ${B}/${b}/b.css ] ),
		'html/b.css' => css_lines( qw[ ${A}/${a}/b.css ${B}/${b}/c.css ] ),
		'html/c.css' => css_lines( qw[ $A/$a/c.css ] ),
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
		'html/b.css' => css_lines( undef, qw[ ${B}/${b}/c.css ] ),
		'html/c.css' => css_lines( undef, qw[ ${B}/${b}/b.css ] ),
	});
	ok(!eval { plan_of($dir); 1 }, 'cycle: dies');
	like($@, qr/dependency cycle: b\.css -> c\.css -> b\.css/, '... showing it');
}

# --- an edge to something that cannot be made
{
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED a.html\n\tWANT b.css\n",
		'html/a.html' => html5_lines( undef, qw[ ${B}/${b}/c.css ] ),
		'html/b.css' => "# WANT: \${B}/\${b}/c.css\n",
		# no html/c.css
	});
	ok(!eval { plan_of($dir); 1 }, 'NEED of the unmakeable: dies');
	like($@, qr/needs `site\/c\.css', which cannot be made: source `html\/c\.css' is missing/,
		'... and why');

	$dir = project({
		MANIFEST => "MAKE all\n\tNEED b.css\n\tWANT a.html\n",
		'html/b.css' => "",
		'html/a.html' => html5_lines( undef, qw[ ${B}/${b}/c.css ] ),
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
bad(html5_lines( qw[ a.html ] ), qr/You have a\.html .* but I have html\/a\.html/, 'HAVE is the path from the root');
bad(html5_lines( qw[ ${A}/${a}/b.html ] ), qr/but I have html\/a\.html/, 'HAVE of another file');
bad(html5_lines( undef, qw[ ${b}/b.css ] ), qr/\$\{b\} is relative to \$\{B\}/, 'bare ${b}');
bad(html5_lines( undef, qw[ $b/b.css ] ), qr/\$\{b\} is relative to \$\{B\}/, 'bare $b');
bad(html5_lines( undef, qw[ ${z}/b.css ] ), qr/no such variable \$\{z\}/, 'no such variable');
bad(html5_lines( undef, qw[ x$/y ] ), qr/stray \$/, 'stray dollar');
bad(html5_lines( undef, qw[ MY/option.mk ] ), qr/\(is it \$\{B\}\/MY\/option\.mk\?\)/, 'the old MY/');

{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => html5_lines( qw[ $A/$a/a.html ${A}/x ${B}/MY/config.mk x ] ),
	});
	ok(eval { plan_of($dir); 1 }, '${A}, ${B}/MY, and plain names are fine') or diag $@;
}

# --- out of tree: the root is not where the build is
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => html5_lines( qw[ ${A}/${a}/a.html ${B}/${b}/b.css x ${B}/MY/config.mk ] ),
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
		'html/a.html' => html5_lines( qw[ ${A}/${a}/a.html ${B}/${b}/b.css ${B}/MY/config.mk ] ),
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
		'a.html' => html5_lines( qw[ ${A}/${a}/a.html ${B}/${b}/b.css ] ),
		'b.css' => '',
	}, a => '.');
	my $plan = eval { plan_of($dir) };
	ok($plan, 'a = `.\': plans') or diag $@;
	is($plan->{node}{'a.html'}{apath}, 'a.html', 'a = `.\': apath') if $plan;
	is_deeply($plan->{node}{'a.html'}{kids}, ['b.css'], 'a = `.\': HAVE agrees, and edges') if $plan;
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
