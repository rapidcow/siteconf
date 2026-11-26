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
# Pin LANGUAGE to C so gettext does not translate the messages matched below.
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;

my %D = ( A => '.', B => '.', a => 'html', b => 'site', c => 'site', X => 'a.b/c.tar.gz d e.', W => 'aa ba', Z => 'a&b', Ya => 'xa$', Yb => 'xa$$', Yc => 'xa', md => '.md', html => '.html', F => 'b.md.md', G => 'c.mdx', Sp => 'my dir/sub dir', Empty => '' );
my $sc = bless { D => \%D }, 'RdKw::WwW::SiteConf';
# (what a recipe says of it, as bytes: a :Q is quoted last, by the backend)
sub s_
{
	my @runs;
	$sc->_subst($_[0], $_[1], 'test', $_[2], \@runs);
	RdKw::WwW::SiteConf::recipe_bytes(\@runs);
}

my @ok = (
	# name modifiers: a value is one name, blanks and all
	['${X:E}',          ''],
	['${X:H}',          'a.b'],
	['${X:R}',          'a.b/c.tar.gz d e'],
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
	# ... also with spaces before and after the slash
	['${@:T}',          'my page.html', 'blog x/my page.html'],
	['${@:H}',          'blog x', 'blog x/my page.html'],
	['${@:R}',          'blog x/my page', 'blog x/my page.html'],
	['${@:E}',          'html', 'blog x/my page.html'],
	['${@:H}/${@:T}',   'blog x/my page.html', 'blog x/my page.html'],
	['${@:T:Q}',        "'my page.html'", 'blog x/my page.html'],
	['${<:T}',          'my page.txt', 'x', 'blog x/my page.txt'],
	['${Sp:H}',         'my dir', ],
	['${Sp:T}',         'sub dir'],
	['${Empty:T}${Empty:E}${Empty:S/a/b/}', ''],
	['${A:Q}/${@}',     'x', 'x'],
	['${Z:Q}',          "'a&b'"],
	['${X:T:Q}',        "'c.tar.gz d e.'"],
	# :S, on the value as a whole
	['${W:S/a/X/}',     'Xa ba'],
	['${W:S/a/X/g}',    'XX bX'],
	['${W:S/a/X/1}',    'Xa ba'],
	['${W:S/a/X/1g}',   'XX bX'],
	['${W:S/a/X/W}',    'Xa ba'],
	['${W:S/a/X/W1g}',  'XX bX'],
	['${W:S/a b/_/W}',  'a_a'],
	['${W:S/a b/_/}',   'a_a'],
	['${W:S/^a/X/}',    'Xa ba'],
	['${W:S/a$/X/}',    'aa bX'],
	['${W:S/^aa$/X/}',  'aa ba'],
	['${W:S/^aa ba$/X/}', 'X'],
	['${W:S/^b$/X/}',   'aa ba'],
	['${W:S/^/pre-/}',  'pre-aa ba'],
	['${W:S/$/.bak/}',  'aa ba.bak'],
	['${W:S//X/g}',     'aa ba'],
	['${W:S/a/&&/g}',   'aaaa baa'],
	['${W:S/a/\&/}',    '&a ba'],
	['${@:S/.html$//}', 'x/y.md', 'x/y.md.html'],
	['${@:S/^x\///}',  'y.md.html', 'x/y.md.html'],
	['${@:S/ /_/g}',    'blog_x/my_page.html', 'blog x/my page.html'],
	['${F:S/${md}$/${html}/}', 'b.md.html'],
	['${F:S/${md}/${html}/}',  'b.html.md'],
	['${G:S/${md}$/${html}/}', 'c.mdx'],
	['${G:S/${md}/${html}/}',  'c.htmlx'],
	['${W:S/a/b/:S/b/c/g}', 'ca ca'],
	['${W:S,a,/,}',     '/a ba'],
	['${W:S/a/\//}',    '/a ba'],
	['${W:S|a|\||}',    '|a ba'],
	['${W:S/\^a/X/}',   'aa ba'],
	['${Z:S/\&/+/}',    'a+b'],
	['${Z:S/b/\$/}',    'a&$'],
	['${W:S/a/${Z}/}',  'a&ba ba'],
	['${W:S/${Z:S,&b,,}/X/}', 'Xa ba'],
	['${W:S/^a/${A}/}', '.a ba'],
	['${W:S/a/X/:R}',   'Xa ba'],
	['${W:S/a/X/:Q}',   "'Xa ba'"],
	['${W:S/a/X\}/}',   'X}a ba'],
	['$$ ${A:Q}/b $',   '$ b $'],
);

# dollars: `$$' is a `$', and only a lone one before the delimiter anchors
# (Ya, Yb, Yc are `xa$', `xa$$' and `xa')
for my $c (
	['S/a$$//',        qw( x   x$    xa )],
	['S/a$$$//',       qw( x   xa$$  xa )],
	['S/a\$$//',       qw( x   xa$$  xa )],
	['S/a$$$$//',      qw( xa$ x     xa )],
	['S/a$$$$$/X/',    qw( xa$ xX    xa )],
	['S/a$//',         qw( xa$ xa$$  x  )],
	['S/a/$$/',        qw( x$$ x$$$  x$ )],
	['S/a/&$/',        qw( xa$$ xa$$$ xa$ )],
) {
	my ($mod, @want) = @$c;
	push @ok, map { ['${Y' . (qw( a b c ))[$_] . ":$mod}", $want[$_]] } 0 .. 2;
}

# :Q alone, of what a shell would make something else of
my %Q = ( sp => 'sp ace', tab => "ta\tb", pipe => 'a|b', colon => 'c:d', quote => "it's",
	semi => 'a;b', amp => 'a&&b', redir => '<in >out', glob => '*.html ?[ab]', tilde => '~x',
	hash => '#x', bang => '!x', sub => '`x` $(x)', dollar => '$x ${x}', back => 'a\\b',
	dq => '"x"', nl => "a\nb", paren => '(x)', brace => '{a,b}', eq => 'a=b', empty => '',
	lead => '-n', mix => "  'a b'\t| \"c\" ; \\ \$ " );
@D{ map { "Q_$_" } keys %Q } = values %Q;
push @ok, (
	# escapes in :S, as in a string
	['${W:S/\s/_/}',    'aa_ba'],
	['${W:S/a/\x{41}/g}', 'AA bA'],
	['${W:S/ /\t\n/}',  "aa\t\nba"],
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
plan tests => @ok + 15 + 1 + 3 + keys(%Q) + 1 + 1 + 1 + 7 + 2;

for my $c (@ok) {
	my ($in, $want, $node, $src) = @$c;
	is(eval { s_($in, $node, $src) }, $want, $in) or diag $@;
}

# ... and the shell reads each back as it was: run `line', with these
# commands only saying what they were given (each word, then a NUL)
sub sh_args
{
	my ($line, @cmd) = @_;
	$line =~ s/\$\$/\$/g;	# (make reads $$ as $)
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

eval { $sc->_subst_name('${W:Q}', undef, 'test') };
like($@, qr/:Q \(shell quote\) is not valid in a prerequisite/, ':Q in a prerequisite is an error');

for my $c (
	['${W:Z}',         qr/test: unknown modifier `:Z'/],
	['${W:R:Z:Q}',     qr/unknown modifier `:Z'/],
	['${W:Q:R}',       qr/:Q \(shell quote\) must be the last modifier/],
	['${W:S/a/${X:Q}/}', qr/:Q \(shell quote\) is not valid in a nested expansion/],
	['${W:S/\q/x/}',   qr/bad escape `\\q' in :S/],
	['${W:RQ}',        qr/unknown modifier `:RQ'/],
	['${W:R:}',        qr/empty modifier/],
	['${W:}',          qr/empty modifier/],
	['${W:S/a/b}',     qr/unterminated :S/],
	['${W:S/a}',       qr/unterminated :S/],
	['${W:S/a/b/x}',   qr/unknown flag `x'/],
	['${W:S}',         qr/unterminated :S/],
	['${W:S:a:b:}',    qr/bad delimiter/],
	['${W:S/a/b/',     qr/unterminated `\$\{W/],
	['${Ya:S/a/b$}',   qr/unterminated :S/],
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
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, prog => 'test');
	my $plan = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->plan;
	is_deeply($plan->{node}{'blog/b.md.html'}{deps}, ['html/blog/b.md', 'site/blog/.ok'], 'a first prerequisite spelled with ${@:R} is the source')
		or diag explain $plan->{node}{'blog/b.md.html'}{deps};
	like(rb($plan->{node}{'blog/a.md.html'}{recipe}), qr!conv html/blog/a\.md -o site/blog/a\.md\.html!, 'recipe for the first');
	like(rb($plan->{node}{'blog/b.md.html'}{recipe}), qr!conv html/blog/b\.md -o site/blog/b\.md\.html!, 'recipe for the second');
}

# A recipe (runs) as bytes
sub rb { RdKw::WwW::SiteConf::recipe_bytes($_[0]) }

# --- a recipe is in make's words: what :Q made is the shell's, and its
# `$' is $$; one from a variable is make's
{
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html", "$dir/MY");
	open my $fh, '>', "$dir/html/a" or die; close $fh;
	open $fh, '>', "$dir/Makefile.in" or die;
	print $fh "a:\n\tx \${X:Q} \${X} \${W:S/a/\${X}/:Q} \${\@:Q}\n";
	close $fh or die;
	open $fh, '>', "$dir/MANIFEST" or die;
	print $fh "MAKE all\n\tNEED a\n";
	close $fh or die;
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		X => 'd$l $(x)', W => 'a',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, prog => 'test');
	my $plan = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->plan;
	is(rb($plan->{node}{a}{recipe}), "\tx 'd\$\$l \$\$(x)' d\$l \$(x) 'd\$\$l \$\$(x)' a\n",
		'what :Q made has $$, and only that (once, however deep)');
	# A :Q is not done yet: it is a word, which the backend quotes
	# once it has spelled it in bytes.
	is_deeply([ map { [ @$_[0, 1] ] } @{ $plan->{node}{a}{recipe} } ], [
		[ text => "\tx " ], [ word => 'd$l $(x)' ], [ text => ' d$l $(x) ' ],
		[ word => 'd$l $(x)' ], [ text => ' ' ], [ word => 'a' ], [ text => "\n" ],
	], 'a recipe is runs of text and words');
}

# --- recipe_target: a backend may say ${@} and ${@:Q} (and ${.TARGET})
# itself in a recipe; with any other modifier, or out of a recipe, it
# is the target's own name
{
	local $sc->{recipe_target} = 1;
	local $sc->{rule_now} = {};
	my @runs;
	$sc->_subst('x ${@}/${.TARGET:Q} ${@:R}', 'x/y.md', 'test', undef, \@runs);
	is_deeply([ map { [ @$_[0, 1], @$_[3 .. $#$_] ] } @runs ], [
		[ text => 'x ' ], [ target => 'x/y.md', 0 ], [ text => '/' ],
		[ target => 'x/y.md', 1 ], [ text => ' x/y' ],
	], 'recipe_target: ${@} and ${@:Q} are runs of their own');
	ok($sc->{rule_now}{recipe_target}, '... and the rule says that it has them');
	is(RdKw::WwW::SiteConf::recipe_bytes(\@runs, target => sub { "<$_[0]," . ($_[1] ? 'q' : 'u') . '>' }),
		'x <x/y.md,u>/<x/y.md,q> x/y', '... which the backend spells');
	@runs = ([ target => 'a b', 'test', 1 ], [ text => ' ' ], [ target => 'c', 'test', 0 ]);
	is(RdKw::WwW::SiteConf::recipe_bytes(\@runs), "'a b' c", '... or, if not, the name, as ${@} would be');
	local $sc->{rule_now} = {};
	is(s_('${@:R} ${@:T:Q} ${@:S/y/z/} ${a}/${@:H}', 'x/y.md'),
		"x/y y.md x/z.md html/x",
		'... any other modifier: the target\'s own name');
	ok(!exists $sc->{rule_now}{recipe_target}, '... which is not a run of its own');
	is($sc->_subst('${@}', 'x/y.md', 'test'), 'x/y.md', '... and out of a recipe (a prerequisite), too');
}

# ... and in a plan, the node says that its recipe has them
{
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html/d", "$dir/MY");
	for (qw( a d/b )) { open my $fh, '>', "$dir/html/$_" or die; close $fh }
	open my $fh, '>', "$dir/Makefile.in" or die;
	print $fh "a:\n\tcp \${a}/\${<} \${B:Q}/\${b:Q}/\${\@:Q}\nd/b: \${a}/d/b\n\tcp \${a}/\${\@:T} \${b}/\${\@:R}\n";
	close $fh or die;
	open $fh, '>', "$dir/MANIFEST" or die;
	print $fh "MAKE all\n\tNEED a d/b\n";
	close $fh or die;
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, prog => 'test');
	my $p = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1);
	$p->{recipe_target} = 1;
	my $plan = $p->plan;
	is_deeply([ map { $plan->{node}{$_}{recipe_target} } qw( a d/b ) ], [ 1, undef ],
		'recipe_target: the node of a recipe that has them');
	is(rb($plan->{node}{a}{recipe}), "\tcp html/a site/a\n", '... which is the name, if the backend does not say');
}
