#!perl
#
# t/unicode.t - file names are characters, spelled as the locale says

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More;
use Encode ();
use Encode::Locale ();
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw(
	read_make write_make update_file load_state
	read_deps walk_deps to_fs un_fs );

# What we name files here; if the locale cannot spell them, there is
# nothing for us to test (and we would rather not guess).
my @names = ( 'résumé.html', 'ディレクトリ', 'ディレクトリ/索引.html', 'ß.mk' );
for my $name (@names) {
	eval { Encode::encode(locale_fs => $name,
		Encode::FB_CROAK() | Encode::LEAVE_SRC()); 1 }
		or plan skip_all => "locale_fs ($Encode::Locale::ENCODING_LOCALE_FS)"
			. " cannot spell our file names";
}
plan tests => 15;

my $dir = tempdir(CLEANUP => 1);
my $udir = un_fs($dir);
sub fs { Encode::encode(locale_fs => $_[0]) }

# --- to_fs, un_fs
is(to_fs('résumé.html'), fs('résumé.html'), 'to_fs: as the locale spells it');
is(un_fs(fs('résumé.html')), 'résumé.html', 'un_fs: and back');
my $bad = "x\x{D800}";
ok(!eval { to_fs($bad, 'here'); 1 }, 'to_fs: no surrogates');
like($@, qr/\Ahere: cannot encode "x\\x\{d800\}"/, '... and says who could not');
is($bad, "x\x{D800}", '... leaving the name be');

# --- update_file, write_make, read_make: the name on disk is the locale's
{
	my $f = "$udir/ß.mk";
	cmp_ok(write_make($f, { name => 'résumé' }, 'test'), '==', 2, 'write_make: created');
	ok(-f fs($f), '... under its locale name');
	is_deeply({ read_make($f) }, { name => 'résumé' }, 'read_make: by character name');
	cmp_ok(update_file($f, "#\n# configured by `test'\n#\nname=\trésumé\n"), '==', 0,
		'update_file: unchanged is unchanged');
}

# --- load_state
{
	mkdir fs("$udir/ディレクトリ") or die $!;
	mkdir fs("$udir/ディレクトリ/MY") or die $!;
	write_make("$udir/ディレクトリ/MY/$_.mk", { a => 'ディレクトリ' }, 'test')
		for qw( config option );
	my %S = eval { load_state("$udir/ディレクトリ") };
	is($S{config}{a}, 'ディレクトリ', 'load_state: in a directory of any name') or diag $@;
}

# --- read_deps, walk_deps
{
	my $spew = sub {
		my ($name, $text) = @_;
		open my $fh, '>:encoding(UTF-8)', fs("$udir/$name") or die "$name: $!";
		print $fh $text;
		close $fh or die;
	};
	$spew->('résumé.html', "# HAVE: \${A}/résumé.html\n# NEED: ディレクトリ/索引.html\n");
	$spew->('ディレクトリ/索引.html', "# NEED: ß.mk\n");
	my %I = read_deps("$udir/résumé.html");
	is_deeply(\%I, { HAVE => '${A}/résumé.html', NEED => [ 'ディレクトリ/索引.html' ] },
		'read_deps: by character name');
	ok(!eval { read_deps("$udir/$bad", { forgive_missing => 1 }); 1 },
		'read_deps: a name we cannot spell is not forgiven');

	chdir fs($udir) or die $!;
	my %G;
	my @got = walk_deps({ A => '.' }, 'résumé.html', { graph => \%G,
		follow => sub { 1 } });
	is_deeply(\@got, [ 'résumé.html', 'ディレクトリ/索引.html', 'ß.mk' ],
		'walk_deps: follows names of any kind');
	is_deeply($G{'ディレクトリ/索引.html'}, { NEED => [ 'ß.mk' ] }, '... and reads them');
	ok(!eval { walk_deps({}, $bad, { follow => sub { 1 } }); 1 },
		'walk_deps: but not the unspellable');
	chdir '/';
}
