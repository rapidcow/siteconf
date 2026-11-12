#!perl
#
# t/modifiers.t - ${VAR:mod} in Makefile.in

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;

my %D = ( A => '.', B => '.', a => 'html', b => 'site', c => 'site', X => 'a.b/c.tar.gz d e.', W => 'aa ba', Z => 'a&b', Y => 'xa$ xa$$ xa', md => '.md', html => '.html', F => 'a.md b.md.md c.mdx' );
my $sc = bless { D => \%D }, 'RdKw::WwW::SiteConf';
sub s_ { $sc->_subst($_[0], $_[1], 'test', $_[2]) }

my @ok = (
	# word modifiers
	['${X:E}',          'gz  '],
	['${X:H}',          'a.b . .'],
	['${X:R}',          'a.b/c.tar d e'],
	['${X:T}',          'c.tar.gz d e.'],
	['${@:R}',          'x/y.md', 'x/y.md.html'],
	['${@:H}/${@:T}',   'x/y.md.html', 'x/y.md.html'],
	['${@:R:R}',        'x/y', 'x/y.md.html'],
	['${@:E}',          'html', 'x/y.md.html'],
	['${@:E}',          '', 'noext'],
	['${@:H}',          '.', 'noext'],
	['${@:H}',          '/', '/noext'],
	['${@:H}',          'a/b', 'a/b/'],
	['${@:T}',          '', 'a/b/'],
	['${@:R}',          '', '.bashrc'],
	['${A:Q}/${@}',     'x', 'x'],
	['${Z:Q}',          "'a&b'"],
	['${X:T:Q}',        "'c.tar.gz d e.'"],
	# :S
	['${W:S/a/X/}',     'Xa bX'],
	['${W:S/a/X/g}',    'XX bX'],
	['${W:S/a/X/1}',    'Xa ba'],
	['${W:S/a/X/1g}',   'XX ba'],
	['${W:S/a/X/W}',    'Xa ba'],
	['${W:S/a b/_/W}',  'a_a'],
	['${W:S/^a/X/}',    'Xa ba'],
	['${W:S/a$/X/}',    'aX bX'],
	['${W:S/^aa$/X/}',  'X ba'],
	['${W:S/^b$/X/}',   'aa ba'],
	['${W:S/^/pre-/}',  'pre-aa pre-ba'],
	['${W:S/$/.bak/}',  'aa.bak ba.bak'],
	['${W:S//X/g}',     'aa ba'],
	['${W:S/a/&&/g}',   'aaaa baa'],
	['${W:S/a/\&/}',    '&a b&'],
	['${@:S/.html$//}', 'x/y.md', 'x/y.md.html'],
	['${@:S/^x\///}',  'y.md.html', 'x/y.md.html'],
	# dollars: `$$' is a `$', and only a lone one before the delimiter anchors
	['${Y:S/a$$//}',       'x x$ xa'],
	['${Y:S/a$$$//}',      'x xa$$ xa'],
	['${Y:S/a\$$//}',      'x xa$$ xa'],
	['${Y:S/a$$$$//}',     'xa$ x xa'],
	['${Y:S/a$$$$$/X/}',   'xa$ xX xa'],
	['${Y:S/a$//}',        'xa$ xa$$ x'],
	['${Y:S/a/$$/}',       'x$$ x$$$ x$'],
	['${Y:S/a/&$/}',       'xa$$ xa$$$ xa$'],
	['${F:S/${md}$/${html}/}', 'a.html b.md.html c.mdx'],
	['${F:S/${md}/${html}/}',  'a.html b.html.md c.htmlx'],
	['${W:S/a/b/:S/b/c/g}', 'ca cc'],
	['${W:S,a,/,}',     '/a b/'],
	['${W:S/a/\//}',    '/a b/'],
	['${W:S|a|\||}',    '|a b|'],
	['${W:S/\^a/X/}',   'aa ba'],
	['${Z:S/\&/+/}',    'a+b'],
	['${Z:S/b/\$/}',    'a&$'],
	['${W:S/a/${Z}/}',  'a&ba ba&b'],
	['${W:S/${Z:S,&b,,}/X/}', 'Xa bX'],
	['${W:S/^a/${A}/}', '.a ba'],
	['${W:S/a/X/:R}',   'Xa bX'],
	['${W:S/a/X/:Q}',   "'Xa bX'"],
	['${W:S/a/X\}/}',   'X}a bX}'],
	['$$ ${A:Q}/b $',   '$ b $'],
);

# :Q alone, of what a shell would make something else of
my %Q = ( sp => 'sp ace', tab => "ta\tb", pipe => 'a|b', colon => 'c:d', quote => "it's",
	semi => 'a;b', amp => 'a&&b', redir => '<in >out', glob => '*.html ?[ab]', tilde => '~x',
	hash => '#x', bang => '!x', sub => '`x` $(x)', dollar => '$x ${x}', back => 'a\\b',
	dq => '"x"', nl => "a\nb", paren => '(x)', brace => '{a,b}', eq => 'a=b', empty => '',
	lead => '-n', mix => "  'a b'\t| \"c\" ; \\ \$ " );
@D{ map { "Q_$_" } keys %Q } = values %Q;
push @ok, (
	['${Q_colon:Q}',    'c:d'],                        # (nothing to the shell)
	['${Q_eq:Q}',       'a=b'],
	['${Q_pipe:Q}',     "'a|b'"],
	['${Q_sp:Q}',       "'sp ace'"],
	['${Q_tab:Q}',      "'ta\tb'"],
	['${Q_quote:Q}',    q{'it'\''s'}],
	['${Q_empty:Q}',    "''"],
	['${Q_tilde:Q}',    "'~x'"],
	['${@:Q}',          "'a b|c.html'", 'a b|c.html'],
	['${<:Q}',          "'s\tc:d.md'", 'x', "s\tc:d.md"],
	['${A:Q}/${a:Q}',   'html'],                       # (${A} of . takes its slash)
);
plan tests => @ok + 12 + 3 + keys(%Q) + 1 + 1;

for my $c (@ok) {
	my ($in, $want, $node, $src) = @$c;
	is(eval { s_($in, $node, $src) }, $want, $in) or diag $@;
}

# ... and the shell reads each back as it was: run `line', with these
# commands only saying what they were given (each word, then a NUL)
sub sh_args
{
	my ($line, @cmd) = @_;
	my $fns = join '', map { "$_() { printf '$_\\0'; printf '%s\\0' \"\$@\"; }; " } @cmd;
	open my $fh, '-|', '/bin/sh', '-c', $fns . $line or die "sh: $!";
	my $out = do { local $/; <$fh> };
	close $fh;
	my @w = split /\0/, $out, -1;
	pop @w;	# (after the last NUL)
	\@w;
}
for my $k (sort keys %Q) {
	my $q = s_("\${Q_$k:Q}");
	is_deeply(sh_args("args $q", 'args'), [ 'args', $Q{$k} ], "the shell reads :Q of $k as it was: $q");
}
{
	local @D{qw( A a B b )} = ('my site', "ht\tml", 'build|x', 'pub:lic');
	my $line = s_('cd -- ${A:Q} && cp ${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}', "o u|t.html", "i n;\tput.html");
	is_deeply(sh_args($line, qw( cd cp )),
		[ 'cd', '--', 'my site', 'cp', "ht\tml/i n;\tput.html", "build|x/pub:lic/o u|t.html" ],
		'a whole recipe, as the shell reads it') or diag $line;
}

for my $c (
	['${W:Z}',         qr/test: unknown modifier `:Z'/],
	['${W:R:Z:Q}',     qr/unknown modifier `:Z'/],
	['${W:RQ}',        qr/unknown modifier `:RQ'/],
	['${W:R:}',        qr/empty modifier/],
	['${W:}',          qr/empty modifier/],
	['${W:S/a/b}',     qr/unterminated :S/],
	['${W:S/a}',       qr/unterminated :S/],
	['${W:S/a/b/x}',   qr/unknown flag `x'/],
	['${W:S}',         qr/unterminated :S/],
	['${W:S:a:b:}',    qr/bad delimiter/],
	['${W:S/a/b/',     qr/unterminated `\$\{W/],
	['${Y:S/a/b$}',    qr/unterminated :S/],
) {
	my ($in, $re) = @$c;
	eval { s_($in) };
	like($@, $re, "error: $in");
}

# --- one rule for several targets, each with a source of its own
# (no html/blog/a.md.html: naming a source first means there is no other)
{
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html/blog", "$dir/MY");
	for my $f (qw( html/blog/a.md html/blog/b.md )) {
		open my $fh, '>', "$dir/$f" or die; close $fh;
	}
	open my $fh, '>', "$dir/Makefile.in" or die;
	print $fh "blog/a.md.html \\\n blog/b.md.html: \\\n\t\${A}/\${a}/\${\@:R}\n"
		. "\tconv \${a:Q}/\${\@:R:Q} -o \${B:Q}/\${b:Q}/\${\@:Q}\n";
	close $fh or die;
	open $fh, '>', "$dir/MANIFEST" or die;
	print $fh "MAKE all\n\tNEED blog/a.md.html\n\tNEED blog/b.md.html\n";
	close $fh or die;
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, 'test');
	my $plan = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->plan;
	is_deeply($plan->{node}{'blog/b.md.html'}{deps}, ['html/blog/b.md', 'site/blog/.ok'], 'a first prerequisite spelled with ${@:R} is the source')
		or diag explain $plan->{node}{'blog/b.md.html'}{deps};
	like($plan->{node}{'blog/a.md.html'}{recipe}, qr!conv html/blog/a\.md -o site/blog/a\.md\.html!, 'recipe for the first');
	like($plan->{node}{'blog/b.md.html'}{recipe}, qr!conv html/blog/b\.md -o site/blog/b\.md\.html!, 'recipe for the second');
}

# --- a recipe is in make's words: what :Q made is the shell's, and its
# `$' is $$; one from a variable is make's
{
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html", "$dir/MY");
	open my $fh, '>', "$dir/html/a" or die; close $fh;
	open $fh, '>', "$dir/Makefile.in" or die;
	print $fh "a:\n\tx \${X:Q} \${X} \${W:S/a/\${X:Q}/:Q} \${\@:Q}\n";
	close $fh or die;
	open $fh, '>', "$dir/MANIFEST" or die;
	print $fh "MAKE all\n\tNEED a\n";
	close $fh or die;
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		X => 'd$l $(x)', W => 'a',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, 'test');
	my $plan = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->plan;
	is($plan->{node}{a}{recipe}, "\tx 'd\$\$l \$\$(x)' d\$l \$(x) ''\\''d\$\$l \$\$(x)'\\''' a\n",
		'what :Q made has $$, and only that (once, however deep)');
}
