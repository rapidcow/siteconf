#!perl
#
# t/unicode.t - names that are not ASCII, from the command line to make,
# and what we say about them where the locale cannot say them

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use Encode ();
use Encode::Locale ();
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( read_deps read_make subs_dep );

eval { require File::ShareDir; 1 }
	or plan skip_all => 'File::ShareDir required, as by siteconf';
sub spell
{
	my ($enc, $s) = @_;
	Encode::encode($enc => $s, Encode::FB_CROAK() | Encode::LEAVE_SRC());
}
sub fs { spell(locale_fs => $_[0]) }
sub unfs
{
	my $s = eval { Encode::decode(locale_fs => $_[0],
		Encode::FB_CROAK() | Encode::LEAVE_SRC()) };
	defined $s or plan skip_all => "locale_fs ($Encode::Locale::ENCODING_LOCALE_FS)"
		. " cannot read `$_[0]'";
	$s;
}

my $script = unfs(script_path());
my $tmp = tempdir(CLEANUP => 1);
my $utmp = unfs($tmp);
my $P = "$utmp/プロジェクト";
my $Bdir = "$utmp/外/ビルド";

# What we name things, and what we tell our children (all of it); if
# the locale cannot spell them, there is nothing for us to test.
my @files = ( $P, $Bdir, 'résumé.html', 'ないもの.html', "no\x{a0}break.html" );
my @args = ( $script, "-DB=$Bdir", $Bdir, 'html/résumé.html', 'résumé.out.html',
	"render:no\x{a0}render" );
for (@files) {
	eval { spell(locale_fs => $_); 1 }
		or plan skip_all => "locale_fs ($Encode::Locale::ENCODING_LOCALE_FS)"
			. " cannot spell our file names";
}
for (@args) {
	eval { spell(locale => $_); 1 }
		or plan skip_all => "the locale ($Encode::Locale::ENCODING_LOCALE)"
			. " cannot spell our arguments";
}
plan tests => 28;

local $ENV{PERL5LIB} = perl5lib();

# Run perl on @cmd in `dir' (a name, in characters), with %env;
# returns (status, what it said, undecoded)
sub run
{
	my ($dir, $env, @cmd) = @_;
	my @argv = map { spell(locale => $_) } @cmd;
	open my $fh, '-|' or do {
		chdir fs($dir) or die "chdir: $!";
		@ENV{keys %$env} = values %$env;
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, @argv;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	($? >> 8, $out);
}
sub spew
{
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', fs($name) or die "$name: $!";
	print $fh $text;
	close $fh or die;
}
sub slurp
{
	open my $fh, '<:encoding(UTF-8)', fs($_[0]) or return '';
	local $/; <$fh>;
}

# --- a project in a directory not named in ASCII, built somewhere else
# that is not either: what configure finds (A) and what it is told (B)
# go into MY/config.mk as they are, once.
mkdir fs($_) or die "$_: $!" for $P, "$P/html", "$utmp/外";
spew("$P/html/résumé.html", "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n");
spew("$P/html/no\x{a0}break.html", "# NEED: \${A}/\${a}/résumé.html\n");
# (a no-break space is not white space: not to make, nor to us)
spew("$P/Makefile.in", "résumé.html no\x{a0}break.html:\n\t"
	. 'cp ${A:Q}/${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}' . "\n");
spew("$P/MANIFEST", "MAKE all\n\tNEED résumé.html\n\tNEED no\x{a0}break.html\n");

my ($status, $out) = run($P, {}, $script, 'init', '-q');
is($status, 0, 'init') or diag $out;
($status, $out) = run($P, {}, 'configure', '-q', "-DB=$Bdir");
is($status, 0, 'configure, told a B of any name') or diag $out;
my $mk = slurp("$Bdir/MY/config.mk");
like($mk, qr/^B=\t\Q$Bdir\E$/m, 'B, as it was told');
like($mk, qr/^A=\t\.\.\/\.\.\/プロジェクト$/m, 'A, as it was found');

($status, $out) = run($P, {}, $script, '-g', '-q', '-B', $Bdir);
is($status, 0, 'siteconf -g') or diag $out;
like(slurp("$Bdir/Makefile"), qr/^site\/résumé\.html: /m, 'the Makefile names it (in UTF-8)');
like(slurp("$Bdir/Makefile"), qr/^site\/no\x{a0}break\.html: [^ ]*html\/no\x{a0}break\.html [^ ]*html\/résumé\.html /m,
	'... and a no-break space is part of a name, in headers too');
ok(-f fs("$Bdir/MY/MANIFEST.all"), '... and its manifest');

SKIP: {
	my $make = $ENV{MAKE} || 'make';
	system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0
		or skip 'no make', 2;
	$Encode::Locale::ENCODING_LOCALE_FS =~ /\Autf-?8\z/i
		or skip 'make finds what the Makefile names only in UTF-8', 2;
	($status, $out) = run($Bdir, {}, '-e', 'exec @ARGV', $make, '-s');
	is(slurp("$Bdir/site/résumé.html"), "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n",
		'make makes it') or diag $out;
	ok(-f fs("$Bdir/site/no\x{a0}break.html"), '... all of it');
}

# --- render: arguments as the locale says, files as the file system does
SKIP: {
	for my $m (qw( Template RdKw::WwW::GenLib )) {
		eval "require $m; 1" or skip "$m is not installed", 2;
	}
	($status, $out) = run($P, {}, $script, 'init', '-q', '-P', 'web', '-o', '/dev/null');
	is($status, 0, 'init -P web') or diag $out;
	($status, $out) = run($P, {}, 'render', '-B', $Bdir, '--',
		'html/résumé.html', 'résumé.out.html');
	like(slurp("$P/résumé.out.html"), qr/^résumé$/m, 'render renders it') or diag $out;
}

# --- a render named with a no-break space, which is no white space to
# init, nor to read_deps: it is one name, and the one it HAVEs (though
# it says so by code point, which no one mistakes for a blank)
{
	($status, $out) = run($P, {}, $script, 'init', '-q', '-P', 'web',
		'-o', 'configure:/dev/null', '-o', "render:no\x{a0}r\x{e9}nder");
	is($status, 0, 'init: a render name with a no-break space') or diag $out;
	my %I = eval { read_deps("$P/no\x{a0}r\x{e9}nder") };
	is($I{HAVE}, "no\${U+00A0}r\x{e9}nder", '... HAVEs just that, the space by code point') or diag $@;
	is(subs_dep(undef, $I{HAVE}), "no\x{a0}r\x{e9}nder", '... which is the name');
}

# --- where the locale cannot say it: \x{...}, and the arguments it
# cannot read are not guessed at
my $C = "$utmp/c";
mkdir fs($C) or die $!;
spew("$C/Makefile.in", "ないもの.html:\n");
spew("$C/MANIFEST", "MAKE all\n\tNEED ないもの.html\n");
run($C, {}, $script, 'init', '-q');
run($C, {}, 'configure', '-q', '-DB=build', '-Da=.');
($status, $out) = run($C, { LC_ALL => 'C' }, $script, '-g', '-B', 'build');
isnt($status, 0, 'a missing source is still missing');
like($out, qr/\\x\{306a\}\\x\{3044\}\\x\{3082\}\\x\{306e\}\.html/,
	'... and says so as \\x{...} where the locale cannot say it');
unlike($out, qr/[^\x00-\x7f]/, '... in nothing but ASCII');

# (bytes, as a UTF-8 locale would have said `-Sa=é')
($status, $out) = run($C, { LC_ALL => 'C' }, $script, 'init', '-o', '/dev/null',
	Encode::decode('ISO-8859-1', Encode::encode('UTF-8', '-Sa=é')));
like($out, qr/: cannot decode argv 4: /, 'unreadable arguments are an error');

# --- SITECONF_CODESETS, and -C, say otherwise than the locale
($status, $out) = run($C, { SITECONF_CODESETS => 'console:ascii' }, $script, '-g', '-B', 'build');
like($out, qr/\\x\{306a\}\\x\{3044\}\\x\{3082\}\\x\{306e\}\.html/,
	'SITECONF_CODESETS=console:ascii: \\x{...}');
($status, $out) = run($C, { SITECONF_CODESETS => 'nope' }, $script, '-V');
like($out, qr/SITECONF_CODESETS: unknown category or encoding "nope"/, '... which is checked');
($status, $out) = run($C, { LC_ALL => 'C' }, $script, '-C', 'argv:UTF-8', 'init', '-o', '/dev/null',
	Encode::decode('ISO-8859-1', Encode::encode('UTF-8', '-Sa=é')));
is($status, 0, 'siteconf -C argv:UTF-8: reads them') or diag $out;
($status, $out) = run($C, { SITECONF_CODESETS => 'argv:ascii' }, $script, 'init', '-o', '/dev/null', '-Sa=é');
like($out, qr/: cannot decode argv 4: /, 'SITECONF_CODESETS=argv:ascii: cannot read them');
($status, $out) = run($C, { SITECONF_CODESETS => 'argv:ascii' }, $script, 'init', '-o', '/dev/null', '-Sa=é', '-C1');
is($status, 0, '... but -C1, after it, overrides it (and where it is does not matter)') or diag $out;
($status, $out) = run($C, {}, $script, '-C', 'nope', '-V');
like($out, qr/-C: unknown category or encoding "nope"/, '-C is checked too');
($status, $out) = run($C, { LC_ALL => 'C' }, 'configure', '-q', '-DB=build', '-Dx=é');
like($out, qr/: cannot decode argv 3: /, 'configure: unreadable arguments are an error');
($status, $out) = run($C, { LC_ALL => 'C' }, 'configure', '-q', '-C', 'argv:UTF-8', '-DB=build', '-Dx=é');
is($status, 0, 'configure -C argv:UTF-8: reads them') or diag $out;
is({ read_make("$C/build/MY/config.mk") }->{x}, 'é', '... as it says');
