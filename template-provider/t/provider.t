#!perl
#
# t/provider.t - what is declared, what may be, and what is loaded

use 5.008;
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use Cwd qw( getcwd abs_path );

eval { require Template; 1 } or plan skip_all => 'Template is not installed';
require RdKw::WwW::GenGenLib::Template::Provider;
Template::Constants->import(qw( STATUS_ERROR STATUS_DECLINED ));
my $P = 'RdKw::WwW::GenGenLib::Template::Provider';

my $cwd = getcwd();
my $top = abs_path(tempdir(CLEANUP => 1));
# The project is in $top/w; next to it is what is out of the tree
mkdir "$top/$_" or die $! for qw( w up out out/public );
chdir "$top/w" or die $!;
mkdir $_ or die $! for qw( site include B B/public );

sub spew
{
	my ($path, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', $path or die "$path: $!";
	print $fh $text;
	close $fh or die $!;
}

my %D = ( A => '../..', B => 'B', a => 'site', b => 'public', c => 'public', inc => 'include' );
sub provider
{
	$P->new({ SOURCE => 'entry', INCLUDE_PATH => [qw( site include )],
		DEFINITION => \%D, ENCODING => 'UTF-8', @_ });
}

# Process site/entry, with these header lines and this body
sub render
{
	my ($headers, $body, $vars, @opt) = @_;
	spew('site/entry', "[%#\n# HAVE: \${a}/entry\n$headers-%]\n$body");
	my $p = eval { provider(@opt) } or return (undef, undef, $@);
	my $tt = Template->new({ LOAD_TEMPLATES => [ $p ] });
	my $out = '';
	my $ok = $tt->process('entry', $vars || {}, \$out);
	($ok, $out, $ok ? undef : $tt->error());
}
my @strict = (undef, CHECK_DEPS => 1);

spew('include/allowed', 'allowed');
spew('include/secret', 'secret');

# --- by default: what is declared is allowed, and what is not is as
# Template::Provider would have it
my ($ok, $out, $err) = render('', '[% INCLUDE secret %]');
is($out, 'secret', 'by default, what is not declared is loaded') or diag $err;
spew("$top/out/public/gen.html", 'made');
($ok, $out, $err) = render('', "[% INCLUDE $top/out/public/gen.html %]");
like("$err", qr/absolute paths are not allowed \(ABSOLUTE is unset\)/,
	'... as Template::Provider would (ABSOLUTE)');
($ok, $out, $err) = render('', "[% INCLUDE $top/out/public/gen.html %]", {}, ABSOLUTE => 1);
is($out, 'made', '... and does, with ABSOLUTE') or diag $err;
{
	local $D{B} = "$top/out";
	($ok, $out, $err) = render("# NEED: \${B}/\${b}/gen.html\n",
		"[% INCLUDE $top/out/public/gen.html %]");
	is($out, 'made', 'a declared dependency is loaded by its absolute name (ALLOW_DEPS)')
		or diag $err;
	($ok, $out, $err) = render("# NEED: \${B}/\${b}/gen.html\n",
		"[% INCLUDE $top/out/public/gen.html %]", {}, ALLOW_DEPS => 0);
	like("$err", qr/absolute paths are not allowed/, '... but not without ALLOW_DEPS');
}
spew('../up/secret', 'up');
($ok, $out, $err) = render('', q{[% INCLUDE '../up/secret' %]});
like("$err", qr/relative paths are not allowed \(RELATIVE is unset\)/, '... nor RELATIVE');

# --- CHECK_DEPS: only what is declared, by any spelling
($ok, $out, $err) = render("# NEED: \${inc}/allowed\n", '[% INCLUDE allowed %]', @strict);
ok($ok, 'declared INCLUDE works') or diag $err;
is($out, 'allowed', 'the header is not output');
($ok, $out) = render("# NEED: include/allowed\n", '[% INCLUDE allowed %]', @strict);
ok($ok, 'declared by any spelling (here, literally)');

for my $directive (qw( INCLUDE PROCESS WRAPPER INSERT )) {
	my $body = "[% $directive secret %]";
	$body .= '[% END %]' if $directive eq 'WRAPPER';
	($ok, $out, $err) = render('', $body, @strict);
	ok(!$ok, "$directive: an undeclared file is refused");
	like("$err", qr/undeclared dependency: `include\/secret'/, '... by name');
}

($ok, $out) = render('', '[% BLOCK local %]local[% END %][% INCLUDE local %]', @strict);
is($out, 'local', 'a local BLOCK needs no declaration');

($ok, $out) = render("# NEED: \${inc}/allowed\n", '[% INCLUDE $x %]', { x => 'allowed' }, CHECK_DEPS => 1);
is($out, 'allowed', 'nor does a name chosen when processing, if it is declared');
($ok, $out, $err) = render('', '[% INCLUDE $x %]', { x => 'secret' }, CHECK_DEPS => 1);
ok(!$ok, '... and it is refused if not');

($ok, $out, $err) = render("# WANT: \${inc}/absent\n", 'fine', @strict);
is($out, 'fine', 'a WANT that is not there is fine, unused');
($ok, $out, $err) = render("# NEED: \${inc}/absent\n", 'fine', @strict);
is($out, 'fine', '... and so is a NEED: it is a declaration');
($ok, $out, $err) = render("# WANT: \${inc}/absent\n", '[% INCLUDE absent %]', @strict);
like("$err", qr/absent: not found/, '... and not found, used');

# what is wrong is said, and not how to fix it (it may be the INCLUDE),
# and by no ./ that INCLUDE_PATH found it by
{
	spew('site/entry', "[%#\n# HAVE: \${a}/entry\n-%]\n[% INCLUDE include/secret %]");
	my $tt = Template->new({ LOAD_TEMPLATES => [ provider(SOURCE => 'site/entry',
		INCLUDE_PATH => [ '.' ], CHECK_DEPS => 1) ] });
	$tt->process('site/entry', {}, \my $o);
	like($tt->error, qr/: undeclared dependency: `include\/secret'$/, 'just what is wrong');
}

# PREFIXES: what a file is also known as, as a header would say it
{
	my $p = provider(DEFINITION => { %D, B => '.', b => 'public', c => 'public', tem => 'site/t',
		x => '.', deep => 'site/t/deep' },
		PREFIXES => [ qw( ${a} ${B}/${b}/ ${B}/${c} ${tem}/ ${A}/${B}/${b} ${x} ${deep} ${nope} ) ]);
	my %alias = (
		'site/x' => '${a}/x',
		'site/t/x' => '${tem}/x',                     # the longest expansion
		'site/t/deep/x' => '${deep}/x',
		'public/x' => '${B}/${b}/x',                  # then the first
		'include/x' => '${x}/include/x',              # `.' is under everything
		'site' => '${a}',
		'/abs/x' => undef, '../x' => undef,
		'site/a b' => '${a}/a${U+0020}b',             # (as a header would)
	);
	for my $path (sort keys %alias) {
		is($p->_alias($path), $alias{$path}, "PREFIXES: $path");
	}
	is(provider(DEFINITION => { %D, B => '.' }, PREFIXES => [ qw( ${B}/${c} ${B}/${b} ) ])
		->_alias('public/x'), '${B}/${c}/x', '... in the order given');
	is(provider(PREFIXES => [ qw( ${A} ${a} ) ])->_alias('site/x'), '${a}/x',
		'... and ${A}, if it is given, only if nothing else is');
	is(provider()->_alias('B/public/x'), '${B}/${b}/x', 'by default, ${a} ${B}/${b} ${B}/${c}');
	is($P->new({ SOURCE => 'site/entry' })->_alias('site/x'), undef,
		'... and none, without the variables');
}

# deep: what the declared declare is declared, too
spew('include/outer', "[%# NEED: \${inc}/secret -%]\n[% INCLUDE secret %]");
($ok, $out, $err) = render("# NEED: \${inc}/outer\n", '[% INCLUDE outer %]', @strict);
is($out, 'secret', 'what an INCLUDE declares, it may INCLUDE') or diag $err;
spew('include/outer', '[% INCLUDE secret %]');
($ok, $out, $err) = render("# NEED: \${inc}/outer\n", '[% INCLUDE outer %]', @strict);
like("$err", qr/undeclared dependency: `include\/secret'/, '... but nothing else');
($ok, $out, $err) = render("# NEED: \${inc}/outer \${inc}/secret\n", '[% INCLUDE outer %]', @strict);
is($out, 'secret', 'the source may declare it for it');

# what is built is declared, but not followed
mkdir 'B/public/gen' or die;
spew('B/public/gen/x', "[%# NEED: \${inc}/secret -%]\n");
spew('site/entry', "[%#\n# NEED: \${B}/\${b}/gen/x\n-%]\n");
my $p = provider();
ok($p->{DECLARED}{'B/public/gen/x'} && !$p->{DECLARED}{'include/secret'},
	'what is built is declared, and not followed');

# --- what may be declared (RELATIVE_DEPS, ABSOLUTE_DEPS)
spew('site/entry', <<'TT');
[%
 # HAVE: ${a}/my/file.html
 # NEED: ../../../etc/passwd
 # NEED: ${A}/../../../etc/passwd
 # NEED: ${a}/../../../etc/passwd
 # NEED: ${A}//etc/passwd
 # NEED: /etc/group
 # NEED: ${a}/////etc/hosts
 # NEED: ${B}/${b}/../../x
-%]
TT
$p = provider();
is_deeply($p->{REFUSED}, {
	'../../../etc/passwd' => 'RELATIVE_DEPS',
	'site/../../../etc/passwd' => 'RELATIVE_DEPS',
	'/etc/passwd' => 'ABSOLUTE_DEPS',
	'/etc/group' => 'ABSOLUTE_DEPS',
	'B/public/../../x' => 'RELATIVE_DEPS',
}, 'what leaves its root may not be declared');
ok($p->{DECLARED}{'site/etc/hosts'}, '... and ${a}/////x is just under ${a}');
$p = provider(RELATIVE_DEPS => 1, ABSOLUTE_DEPS => 1);
is_deeply($p->{REFUSED}, {}, '... unless the options say so');
{
	local $D{x} = '../..';
	spew('site/entry', "[%#\n# NEED: \${a}/z/\${x}/y\n# NEED: \${a}/\${x}/w\n-%]\n");
	$p = provider();
	is_deeply($p->{REFUSED}, { 'site/z/../../y' => 'RELATIVE_DEPS' },
		'... however the variables after the root spell it');
	ok($p->{DECLARED}{'site/../../w'}, '... but the root itself is as configured');
}
# (a climb spelled by code point is a climb all the same)
spew('site/entry', "[%#\n# NEED: \${a}/\${U+002E}\${U+002E}/\${u+2e}./etc/passwd\n# NEED: \${U+002F}etc/group\n-%]\n");
$p = provider();
is_deeply($p->{REFUSED}, { 'site/../../etc/passwd' => 'RELATIVE_DEPS', '/etc/group' => 'ABSOLUTE_DEPS' },
	'... or the characters they are made of');

($ok, $out, $err) = render("# NEED: ../up/secret\n", q{[% INCLUDE '../up/secret' %]}, @strict);
like("$err", qr/`\.\.\/up\/secret' is declared, but forbidden because RELATIVE_DEPS is unset/,
	'CHECK_DEPS: what may not be declared is said so');
($ok, $out, $err) = render("# NEED: ../up/secret\n", q{[% INCLUDE '../up/secret' %]});
like("$err", qr/relative paths are not allowed/, '... and without it, it is just not declared');
($ok, $out, $err) = render("# NEED: ../up/secret\n", q{[% INCLUDE '../up/secret' %]},
	{}, RELATIVE_DEPS => 1, CHECK_DEPS => 1);
is($out, 'up', 'RELATIVE_DEPS: declared, and so loaded') or diag $err;
($ok, $out, $err) = render("# NEED: \${A}/../up/secret\n", q{[% INCLUDE '../up/secret' %]},
	{}, RELATIVE_DEPS => 1);
is($out, 'up', '... by any spelling') or diag $err;

# --- ALLOW_PREFIXES: the roots a declaration may have
spew('include/outer', "[%# NEED: \${inc}/secret -%]\n");
spew('site/entry', <<'TT');
[%
 # NEED: ${a}/x
 # NEED: $a//y
 # NEED: ${B}/${b}/z
 # NEED: ${B}/w
 # NEED: ${inc}/outer
 # NEED: plain
-%]
TT
$p = provider(ALLOW_PREFIXES => [ qw( $a/ ${B}/${b} ) ]);
is_deeply($p->{REFUSED}, { 'B/w' => 'ALLOW_PREFIXES', 'include/outer' => 'ALLOW_PREFIXES',
	'plain' => 'ALLOW_PREFIXES' }, 'ALLOW_PREFIXES: only these roots, and only whole');
ok($p->{DECLARED}{'site/x'} && $p->{DECLARED}{'site/y'} && $p->{DECLARED}{'B/public/z'},
	'... by any spelling');
ok(!exists $p->{DECLARED}{"include/secret"}, '... and what the rest declare is not followed');
$p = provider(ALLOW_PREFIXES => [ '', '${inc}' ]);
ok($p->{DECLARED}{plain} && $p->{DECLARED}{"include/secret"} && !$p->{DECLARED}{'site/x'},
	'... and no root is a root too');
is_deeply(provider()->{REFUSED}, {}, '... by default, any');
ok(!eval { provider(ALLOW_PREFIXES => [ '${a}/x' ]) }, '... and a root is all it may be');
($ok, $out, $err) = render("# NEED: \${inc}/secret\n", '[% INCLUDE secret %]',
	{}, ALLOW_PREFIXES => [ '${a}' ], CHECK_DEPS => 1);
like("$err", qr/`include\/secret' is declared, but forbidden because ALLOW_PREFIXES does not permit its root/,
	'... and CHECK_DEPS says so');

# --- no header, unless an option asks
spew('site/entry', "[%#\n# HAVE: elsewhere\n# NEED: \${nope}/x\n-%]\n");
ok(eval { provider(ALLOW_DEPS => 0) }, 'no option, no header') or diag $@;
($ok, $out, $err) = render('', '[% INCLUDE secret %]', {}, ALLOW_DEPS => 0);
is($out, 'secret', '... and it is a Template::Provider') or diag $err;

# --- what a header may say
spew('site/entry', "[%#\n# HAVE: elsewhere\n-%]\n");
ok(eval { provider() }, 'HAVE is not ours to check') or diag $@;
ok(!eval { provider(CHECK_HAVE => 1) }, '... unless CHECK_HAVE');
like($@, qr/HAVE `elsewhere', but it is `site\/entry' \(\$\{a\}\/entry\)$/, '... which says so (and as a header would)');
ok(!eval { provider(CHECK_HAVE => 1, ALLOW_DEPS => 0) }, '... with nothing else, too');
spew('site/entry', "[%#\n# HAVE: \${A}/site/entry\n-%]\n");
ok(eval { provider(CHECK_HAVE => 1) }, '... by any spelling') or diag $@;
spew('site/entry', "x\n");
ok(!eval { provider(CHECK_HAVE => 1) }, '... and a HAVE there must be');
spew('site/entry', "[%#\n# NEED: \${nope}/x\n-%]\n");
ok(!eval { provider() }, 'an undefined variable is an error');
like($@, qr/no such variable \$\{nope\}/, '... and says so');
spew('include/hidden', "[%# NEED: \${nope}/x -%]\n");
spew('site/entry', "[%#\n# NEED: \${inc}/hidden\n-%]\n");
ok(!eval { provider() }, '... further down, too');
ok(!eval { $P->new({ SOURCE => 'entry', COMPILE_DIR => 'c' }) }, 'COMPILE_DIR is refused');
ok(!eval { $P->new({ INCLUDE_PATH => ['site'] }) }, 'SOURCE is required');
ok(!eval { $P->new({ SOURCE => 'nowhere', INCLUDE_PATH => ['site'] }) }, 'and must be found');

# --- names, and the cache
spew('site/entry', "[%#\n# NEED: \${inc}/allowed\n-%]\n");
$p = provider(CHECK_DEPS => 1);
my ($data, $status) = $p->fetch('allowed');
ok(!$status, 'fetch') or diag $data;
delete $p->{DECLARED}{'include/allowed'};
($data, $status) = $p->fetch('allowed');
is($status, STATUS_ERROR(), 'a cached template is still checked');
($data, $status) = $p->fetch('ghost');
is($status, STATUS_DECLINED(), 'what is not there is declined');

spew('site/allowed', 'shadow');
$p = provider(CHECK_DEPS => 1);
($data, $status) = $p->fetch('allowed');
is($status, STATUS_ERROR(), 'an undeclared namesake earlier in the path is not skipped');
like($data, qr/undeclared dependency: `site\/allowed' \(\$\{a\}\/allowed\)$/,
	'... and named (and as a header would name it)');
spew('site/a b$', 'x');
($data, $status) = $p->fetch('a b$');
like($data, qr/`site\/a b\$' \(\$\{a\}\/a\$\{U\+0020\}b\$\{\$\}\)$/, '... escaped, so that it is one name there');
unlink 'site/a b$';
unlink 'site/allowed';

# --- ENCODING reaches the provider (Template's own does not)
spew('include/allowed', "caf\x{e9}");
($ok, $out) = render('', '[% INCLUDE allowed %]');
is($out, "caf\x{e9}", 'decoded as UTF-8');

chdir $cwd or die $!;
done_testing;
