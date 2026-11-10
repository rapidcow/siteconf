#!perl
#
# t/unicode.t - template names are characters, spelled as the locale says

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use Encode ();
use Encode::Locale ();
use File::Temp qw( tempdir );
use Cwd qw( getcwd );

eval { require Template; 1 } or plan skip_all => 'Template is not installed';
require RdKw::WwW::GenGenLib::Template::Provider;
my $P = 'RdKw::WwW::GenGenLib::Template::Provider';

# What we name files here; if the locale cannot spell them, there is
# nothing for us to test.
my @names = ( 'サイト', 'サイト/入口', 'ヘッダー.html', 'résumé' );
for my $name (@names) {
	eval { Encode::encode(locale_fs => $name,
		Encode::FB_CROAK() | Encode::LEAVE_SRC()); 1 }
		or plan skip_all => "locale_fs ($Encode::Locale::ENCODING_LOCALE_FS)"
			. " cannot spell our file names";
}
plan tests => 6;

sub fs { Encode::encode(locale_fs => $_[0]) }
sub spew
{
	my ($path, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', fs($path) or die "$path: $!";
	print $fh $text;
	close $fh or die $!;
}

my $cwd = getcwd();
my $dir = tempdir(CLEANUP => 1);
chdir $dir or die $!;
mkdir fs('サイト') or die $!;
spew('サイト/ヘッダー.html', 'résumé');
spew('サイト/秘密', 'secret');
spew('サイト/入口', "[%#\n# HAVE: \${a}/入口\n# NEED: \${a}/ヘッダー.html\n-%]\n"
	. "[% INCLUDE \$x %]");

sub run
{
	my ($x, @opt) = @_;
	my $p = $P->new({ SOURCE => '入口', INCLUDE_PATH => [ 'サイト' ],
		DEFINITION => { a => 'サイト' }, ENCODING => 'UTF-8', CHECK_DEPS => 1, @opt });
	my $tt = Template->new({ LOAD_TEMPLATES => [ $p ] });
	my $out = '';
	my $ok = eval { $tt->process('入口', { x => $x }, \$out) };
	($ok, $out, $ok ? undef : ($@ || $tt->error()));
}

my ($ok, $out, $err) = run('ヘッダー.html');
is($out, 'résumé', 'a source and an INCLUDE of any name') or diag $err;
($ok, $out, $err) = run('秘密');
like("$err", qr/undeclared dependency: `サイト\/秘密' \(aka `\$\{a\}\/秘密'\)/, 'and undeclared, of any name');
($ok, $out, $err) = run('秘密', CHECK_DEPS => 0);
is($out, 'secret', '... unchecked, all the same');

# A name we cannot spell is an error, not a guess
($ok, $out, $err) = run("x\x{D800}");
ok(!$ok, 'a name the locale cannot spell is not loaded');
like("$err", qr/\Aundef error - \S+: cannot encode "\\x\{30b5\}\\x\{30a4\}\\x\{30c8\}\/x\\x\{d800\}"/, '... and says so');
($ok, $out, $err) = run("x\x{D800}", CHECK_DEPS => 0);
like("$err", qr/\Aundef error - \S+: cannot encode "\\x\{30b5\}\\x\{30a4\}\\x\{30c8\}\/x\\x\{d800\}"/, '... unchecked, too');

chdir $cwd or die $!;
