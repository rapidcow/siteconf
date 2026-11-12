#!perl
#
# t/general.t - the tem preset: Template Toolkit, and nothing else

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( project_root script_path perl5lib );
use File::Path qw( make_path );
use File::Temp qw( tempdir );

eval { require Template; 1 } or plan skip_all => 'Template is not installed';
my $script = script_path();
plan tests => 21;
# The preset comes from the built share
local $ENV{PERL5LIB} = join ':', project_root() . '/blib/lib', perl5lib();

my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;
make_path('html');

sub run
{
	open my $fh, '-|' or do {
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, @_;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	($? >> 8, $out);
}
sub slurp { open my $fh, '<:encoding(UTF-8)', $_[0] or return ''; local $/; <$fh> }
sub spew
{
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', $name or die "$name: $!";
	print $fh $text;
	close $fh or die;
}

my ($status, $out) = run($script, 'init', '-q', '-P', 'tem');
is($status, 0, 'init -P tem') or diag $out;
my $configure = slurp('configure');
unlike($configure, qr/"RdKw::WwW::GenLib"/, 'configure needs no GenLib');
like($configure, qr/\[ "RdKw::WwW::GenGenLib", "0\.0100" \]/, '... but GenGenLib 0.0100');
my $render = slurp('render');
unlike($render, qr/\$target|locate|location/, 'render has no location to speak of');
like($render, qr/^use RdKw::WwW::GenGenLib 0\.0100 /m, '... and uses the GenGenLib it needs');

for my $pin ('0', '0.0003') {
	my ($st, $o) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', '/dev/null',
		"-MRdKw::WwW::GenGenLib=$pin");
	like($o, qr/-P tem needs RdKw::WwW::GenGenLib 0\.0100/, "no tem for GenGenLib $pin");
}

# -M-module drops what the preset asked for; a later -Mmodule is back
($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', 'configure:configure.m',
	'-o', 'render:/dev/null', '-M-Template');
unlike($status ? $out : slurp('configure.m'), qr/"Template"/, '-M-Template: dropped');
($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', 'configure:configure.m',
	'-o', 'render:/dev/null', '-M-Template', '-MTemplate=2');
like($status ? $out : slurp('configure.m'), qr/\[ "Template", (?:2|"2") \]/, '... -MTemplate=2 after it: back');
($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', '/dev/null',
	'-M-RdKw::I18N::CodeSets');
like($out, qr/-M-RdKw::I18N::CodeSets: configure always needs it/, '... but not CodeSets');
($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', '/dev/null', '-M-Template=2');
like($out, qr/-M-Template=2: no version for what is dropped/, '... nor with a version');
($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', '/dev/null', '-M-');
like($out, qr/-M-: bad module name/, '... nor nothing');

($status, $out) = run('configure', '-q', '-DB=build', '-Ogreeting=hello');
is($status, 0, 'configure, with no site_url') or diag $out;

spew('html/a.txt', "[% O.greeting %], [% D.b %]!\n");
($status, $out) = run('render', '-B', 'build', '--', 'html/a.txt', 'out.txt');
is($status ? $out : slurp('out.txt'), "hello, site!\n", 'render: D and O');

spew('html/inc.txt', "included\n");
spew('html/b.txt', "[% INCLUDE inc.txt %]");
($status, $out) = run('render', '-B', 'build', '--', 'html/b.txt', 'out.txt');
is($status ? $out : slurp('out.txt'), "included\n", '... and what it INCLUDEs, declared or not');

# Out of the tree: what is made is named absolutely, which Template
# would not have (ABSOLUTE)
($status, $out) = run('configure', '-q', "-DB=$tmp/out");
is($status, 0, 'configure, out of the tree') or diag $out;
spew("$tmp/out/gen.txt", "made\n");
spew('html/c.txt', "[%# NEED: \${B}/gen.txt -%]\n[% INCLUDE \"$tmp/out/gen.txt\" %]");
($status, $out) = run('render', '-B', "$tmp/out", '--', 'html/c.txt', 'out.txt');
like($out, qr/absolute paths are not allowed/, 'by its absolute name, not even what is declared');

SKIP: {
	eval { require RdKw::WwW::GenGenLib::Template::Provider; 1 }
		or skip 'RdKw::WwW::GenGenLib::Template::Provider is not installed', 4;
	($status, $out) = run($script, 'init', '-q', '-f', '-P', 'tem', '-o', 'configure:/dev/null',
		'-MRdKw::WwW::GenGenLib::Template::Provider');
	is($status, 0, 'init -P tem, with the provider') or diag $out;
	($status, $out) = run('render', '-B', "$tmp/out", '--', 'html/c.txt', 'out.txt');
	is($status ? $out : slurp('out.txt'), "made\n", 'what is declared is loaded, by any name');
	spew('html/c.txt', "[% INCLUDE \"$tmp/out/gen.txt\" %]");
	($status, $out) = run('render', '-B', "$tmp/out", '--', 'html/c.txt', 'out.txt');
	like($out, qr/absolute paths are not allowed/, '... and what is not, as Template would');
	($status, $out) = run('render', '-B', "$tmp/out", '--', 'html/b.txt', 'out.txt');
	is($status ? $out : slurp('out.txt'), "included\n", '... which is to say, by default');
}

chdir '/';
