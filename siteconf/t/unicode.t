#!perl
#
# t/unicode.t - names that are not ASCII, from the command line to make,
# and what we say about them where the locale cannot say them

use utf8;
use 5.008;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Encode ();
use Encode::Locale ();
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib fs_surprise );
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
plan tests => 44;

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
# Bytes, from a path in bytes.  The build file is spelled as the
# file system spells names, and so are the files make makes.
sub slurp_raw
{
	open my $fh, '<:raw', $_[0] or return '';
	local $/; <$fh>;
}
sub spew_raw
{
	my ($path, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', $path or die "$path: $!";
	print $fh $text;
	close $fh or die;
}
sub slurp_fs { unfs(slurp_raw(fs($_[0]))) }

# --- a project in a directory not named in ASCII, built somewhere else
# that is not either: what configure finds (A) and what it is told (B)
# go into MY/config.mk as they are, once.
mkdir fs($_) or die "$_: $!" for $P, "$P/html", "$utmp/外";
spew("$P/html/résumé.html", "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n");
spew("$P/html/no\x{a0}break.html", "# NEED: \${A}/\${a}/résumé.html\n");
# (a no-break space is not white space: not to make, nor to us)
spew("$P/Makefile.in", "résumé.html no\x{a0}break.html:\n\t"
	. 'cd ${A:Q} && cp ${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}' . "\n");
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
like(slurp_fs("$Bdir/Makefile"), qr/^site\/résumé\.html: /m, 'the Makefile names it (as the file system does)');
like(slurp_fs("$Bdir/Makefile"), qr/^site\/no\x{a0}break\.html: [^ ]*html\/no\x{a0}break\.html [^ ]*html\/résumé\.html /m,
	'... and a no-break space is part of a name, in headers too');
ok(-f fs("$Bdir/MY/MANIFEST.all"), '... and its manifest');

SKIP: {
	my $make = $ENV{MAKE} || 'make';
	system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0
		or skip 'no make', 2;
	($status, $out) = run($Bdir, {}, '-e', 'exec @ARGV', $make, '-s');
	is(slurp("$Bdir/site/résumé.html"), "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n",
		'make makes it') or diag $out;
	ok(-f fs("$Bdir/site/no\x{a0}break.html"), '... all of it');
}

# Exercise a relative B even where Latin-1 file names are unavailable.
($status, $out) = run($P, {}, 'configure', '-q', '-DB=build-rel');
is($status, 0, 'configure with relative B') or diag $out;
($status, $out) = run($P, {}, $script, '-g', '-q', '-B', 'build-rel');
is($status, 0, 'generate with relative B') or diag $out;
SKIP: {
	my $make = $ENV{MAKE} || 'make';
	system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0
		or skip 'no make', 1;
	($status, $out) = run("$P/build-rel", {}, '-e', 'exec @ARGV', $make, '-s');
	is(slurp("$P/build-rel/site/résumé.html"), "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n",
		'make copies to relative B') or diag $out;
}

# --- the build file spells names as the file system does, so make
# finds them.  Here the file system spells them in ISO-8859-1.  A name
# the file system cannot spell is an error.
SKIP: {
	my $L = "$utmp/latin1";
	mkdir fs($L) or die "$L: $!";
	my $name = "r\xe9sum\xe9.html";  # bytes, as ISO-8859-1 spells résumé.html
	my $why = fs_surprise($name, fs($L));
	skip "file system: $why", 8 if defined $why;
	my %L1 = ( SITECONF_CODESETS => 'filesys:ISO-8859-1' );
	mkdir fs("$L/html") or die $!;
	spew_raw(fs("$L/html/") . $name, "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n");
	spew("$L/Makefile.in", "résumé.html:\n\t"
		. 'cd ${A:Q} && cp ${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}' . "\n");
	spew("$L/MANIFEST", "MAKE all\n\tNEED résumé.html\n");
	run($L, {}, $script, 'init', '-q');
	run($L, {}, 'configure', '-q', '-DB=build');
	($status, $out) = run($L, {%L1}, $script, '-g', '-q', '-B', 'build');
	is($status, 0, 'siteconf -g, filesys:ISO-8859-1') or diag $out;
	my $text = slurp_raw(fs("$L/build/Makefile"));
	like($text, qr/^site\/r\xe9sum\xe9\.html: [^ ]*html\/r\xe9sum\xe9\.html /m,
		'the Makefile spells it as the file system does');
	unlike($text, qr/r\xc3\xa9sum/, '... and not as UTF-8');
	($status, $out) = run($L, {%L1}, $script, '-g', '-q', '-B', 'build', '-G', 'ninja');
	is($status, 0, 'siteconf -g -G ninja') or diag $out;
	like(slurp_raw(fs("$L/build/build.ninja")), qr/^build site\/r\xe9sum\xe9\.html: rule1 [^ ]*html\/r\xe9sum\xe9\.html /m,
		'... and so does build.ninja');
	($status, $out) = run($L, { SITECONF_CODESETS => 'filesys:ascii' }, $script, '-g', '-q', '-B', 'build');
	isnt($status, 0, 'a name the file system cannot spell is an error');
	like($out, qr/^E: cannot encode "[^"]*r\\x\{e9\}sum\\x\{e9\}\.html" in US-ASCII/m, '... and says so');
	SKIP: {
		my $make = $ENV{MAKE} || 'make';
		system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0
			or skip 'no make', 1;
		($status, $out) = run("$L/build", {}, '-e', 'exec @ARGV', $make, '-s');
		is(Encode::decode('UTF-8', slurp_raw(fs("$L/build/site/") . $name), Encode::FB_CROAK()), "# HAVE: \${A}/\${a}/résumé.html\nrésumé\n",
			'make makes it, under that name') or diag $out;
	}
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

# --- by default (GenLib 0.0300), location is a URI path (UTF-8
# escapes), and target is the file name (characters); locate
# compares URI paths
SKIP: {
	for my $m (qw( Template RdKw::WwW::GenLib )) {
		eval "require $m; 1" or skip "$m is not installed", 2;
	}
	($status, $out) = run($P, {}, $script, 'init', '-q', '-P', 'web',
		'-o', 'configure:/dev/null', '-o', 'render:render-uri');
	is($status, 0, 'init -P web') or diag $out;
	mkdir fs("$P/html/文書") or die "文書: $!";
	spew("$P/html/文書/résumé.html", "[%# HAVE: \${a}/文書/résumé.html : -%]\n"
		. "[% location %]|[% target %]|[% locate(file2uri('文書/ないもの.html')) %]"
		. "|[% locate('./r%c3%a9sum%c3%a9.html') %]|[% uri2file(location) %]\n");
	($status, $out) = run($P, {}, 'render-uri', '-B', $Bdir, '--',
		'html/文書/résumé.html', 'résumé.uri.html');
	is(slurp("$P/résumé.uri.html"),
		"%E6%96%87%E6%9B%B8/r%C3%A9sum%C3%A9.html|文書/résumé.html"
		. "|%E3%81%AA%E3%81%84%E3%82%82%E3%81%AE.html"
		. "||文書/résumé.html\n",
		'location, target, locate and uri2file') or diag $out;
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

# LC_ALL=C is ASCII where the C library says so (it does not on Android,
# whose nl_langinfo(CODESET) is UTF-8 whatever the locale), and where it
# does not we say so ourselves; no more than that, for what we test here
# is what we do about a locale that cannot, not how it came to be.
sub c_locale_is_ascii
{
	local $ENV{LC_ALL} = 'C';
	my $cmd = qq("$^X" -MPOSIX=setlocale,LC_ALL -MI18N::Langinfo=langinfo,CODESET)
		. q( -e "setlocale(LC_ALL, q()); print langinfo(CODESET)");
	my $codeset = `$cmd`;
	return 0 if $? or !defined $codeset or $codeset eq '';
	(Encode::resolve_alias($codeset) || '') eq 'ascii';
}
my %ASCII = c_locale_is_ascii() ? (LC_ALL => 'C') : (SITECONF_CODESETS => '0');
my $C = "$utmp/c";
mkdir fs($C) or die $!;
spew("$C/Makefile.in", "ないもの.html:\n");
spew("$C/MANIFEST", "MAKE all\n\tNEED ないもの.html\n");
run($C, {}, $script, 'init', '-q');
run($C, {}, 'configure', '-q', '-DB=build', '-Da=.');
($status, $out) = run($C, {%ASCII}, $script, '-g', '-B', 'build');
isnt($status, 0, 'a missing source is still missing');
like($out, qr/\\x\{306a\}\\x\{3044\}\\x\{3082\}\\x\{306e\}\.html/,
	'... and says so as \\x{...} where the locale cannot say it');
unlike($out, qr/[^\x00-\x7f]/, '... in nothing but ASCII');

# (bytes, as a UTF-8 locale would have said `-Sa=é')
($status, $out) = run($C, {%ASCII}, $script, 'init', '-o', '/dev/null',
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
($status, $out) = run($C, { SITECONF_CODESETS => 'argv:ascii' }, $script, '-C1', 'init', '-o', '/dev/null', '-Sa=é');
is($status, 0, '... but -C1 overrides it') or diag $out;
($status, $out) = run($C, {}, $script, '-C0', '-C', 'nope', '-V');
like($out, qr/\Asiteconf: -C \(argv 3\): unknown category or encoding "nope"/, '-C is checked too');
($status, $out) = run($C, {}, $script, '-V', '-C1');
like($out, qr/\Asiteconf: too late to -C now\./, '-C after anything else: too late');
($status, $out) = run($C, {}, $script, '-VC1');
like($out, qr/\Asiteconf: too late to -C now\./, '... even glued to it');
($status, $out) = run($C, { LC_ALL => 'C' }, 'configure', '-q', '-C', 'argv:UTF-8');
like($out, qr/\Aconfigure: too late to -C now\./, 'configure: too late, too');
($status, $out) = run($C, {%ASCII}, 'configure', '-q', '-DB=build', '-Dx=é');
like($out, qr/: cannot decode argv 3: /, 'configure: unreadable arguments are an error');
($status, $out) = run($C, { LC_ALL => 'C' }, 'configure', '-C', 'argv:UTF-8', '-q', '-DB=build', '-Dx=é');
is($status, 0, 'configure -C argv:UTF-8: reads them') or diag $out;
is({ read_make("$C/build/MY/config.mk") }->{x}, 'é', '... as it says');
