#!perl
#
# t/graph.t - header paths, and edges to what we make ourselves

use strict;
use warnings;
use Test::More tests => 27;
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
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok', %D }, 'test');
	$f->{x} = '' ;
	open my $fh, '>', "$dir/x" or die; close $fh;
	$dir;
}
sub plan_of {
	my ($dir, $B) = @_;
	RdKw::WwW::SiteConf->new(B => $B || $dir, quiet => 1)->plan;
}

my $manifest = "MAKE all\n\tNEED a.html\n";

# --- an edge to what we make: it is made, and first
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => "# HAVE: \${A}/\${a}/a.html\n# NEED: \${B}/\${b}/b.css\n",
		'html/b.css' => "/*\n * HAVE: \${A}/\${a}/b.css\n * NEED: \${B}/\${b}/c.css\n */\n",
		'html/c.css' => "/* HAVE: \$A/\$a/c.css */\n",
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
		'html/b.css' => "# NEED: \${B}/\${b}/c.css\n",
		'html/c.css' => "# NEED: \${B}/\${b}/b.css\n",
	});
	ok(!eval { plan_of($dir); 1 }, 'cycle: dies');
	like($@, qr/dependency cycle: b\.css -> c\.css -> b\.css/, '... showing it');
}

# --- an edge to something that cannot be made
{
	my $dir = project({
		MANIFEST => "MAKE all\n\tNEED a.html\n\tWANT b.css\n",
		'html/a.html' => "# NEED: \${B}/\${b}/c.css\n",
		'html/b.css' => "# WANT: \${B}/\${b}/c.css\n",
		# no html/c.css
	});
	ok(!eval { plan_of($dir); 1 }, 'NEED of the unmakeable: dies');
	like($@, qr/needs `site\/c\.css', which cannot be made: source `html\/c\.css' is missing/,
		'... and why');

	$dir = project({
		MANIFEST => "MAKE all\n\tNEED b.css\n\tWANT a.html\n",
		'html/b.css' => "",
		'html/a.html' => "# NEED: \${B}/\${b}/c.css\n",
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
bad("# HAVE: a.html\n", qr/You have a\.html .* but I have html\/a\.html/, 'HAVE is the path from the root');
bad("# HAVE: \${A}/\${a}/b.html\n", qr/but I have html\/a\.html/, 'HAVE of another file');
bad("# NEED: \${b}/b.css\n", qr/\$\{b\} is relative to \$\{B\}/, 'bare ${b}');
bad("# NEED: \$b/b.css\n", qr/\$\{b\} is relative to \$\{B\}/, 'bare $b');
bad("# NEED: \${z}/b.css\n", qr/no such variable \$\{z\}/, 'no such variable');
bad("# NEED: x\$/y\n", qr/stray \$/, 'stray dollar');
bad("# NEED: MY/option.mk\n", qr/\(is it \$\{B\}\/MY\/option\.mk\?\)/, 'the old MY/');

{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => "# HAVE: \$A/\$a/a.html\n# NEED: \${A}/x\n# NEED: \${B}/MY/config.mk\n# NEED: x\n",
	});
	ok(eval { plan_of($dir); 1 }, '${A}, ${B}/MY, and plain names are fine') or diag $@;
}

# --- out of tree: the root is not where the build is
{
	my $dir = project({
		MANIFEST => $manifest,
		'html/a.html' => "# HAVE: \${A}/\${a}/a.html\n# NEED: \${B}/\${b}/b.css\n# NEED: x\n# NEED: \${B}/MY/config.mk\n",
		'html/b.css' => "",
	}, A => '..', B => 'build');
	my $plan = plan_of($dir, "$dir/build");
	is($plan->{node}{'a.html'}{apath}, '../html/a.html', 'apath is seen from the build dir');
	is_deeply($plan->{node}{'a.html'}{deps},
		[qw( ../html/a.html ../x site/b.css MY/config.mk site/.ok )],
		'and so are the rest') or diag explain $plan->{node}{'a.html'}{deps};
}
