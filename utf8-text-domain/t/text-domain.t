#!perl
#
# t/text-domain.t - __, __n and N__, with catalogs, without, and
# without Locale::Messages

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More;
use File::Spec;
use File::Temp qw( tempdir );

use RdKw::L10N::Utf8TextDomain ();
my $TD = 'RdKw::L10N::Utf8TextDomain';
my $HAVE_GETTEXT = eval { require Locale::Messages; 1 };

# `use' it in package `pkg', with @args
sub install
{
	my ($pkg, @args) = @_;
	eval "package $pkg; $TD->import(\@args); 1";
}

my $tmp = tempdir(CLEANUP => 1);

# --- what is written
ok(install('T::None', 'no-such-domain', $tmp), 'a domain with no catalogs') or diag $@;
is(T::None::__('炒饭'), '炒饭', '__: as it is written');
is(T::None::__n('one file', '%d files', 1), 'one file', '__n: one');
is(T::None::__n('one file', '%d files', 2), '%d files', '__n: more');
is(T::None::N__('炒饭'), '炒饭', 'N__: as it is');
ok(install('T::NoDir', 'no-such-domain'), '... nor LOCALEDIR') or diag $@;
is(T::NoDir::__('x'), 'x', '... as it is written');

ok(install('T::Gone', ':module' => 'No::Such::L10N'), ':module that is not there')
	or diag $@;
is(T::Gone::__('炒饭'), '炒饭', '... as it is written');
is(T::Gone::__n('one file', '%d files', 2), '%d files', '... __n too');

# (a module of our own, in a directory of its own)
my $lib = File::Spec->catdir($tmp, 'lib');
my $mo = File::Spec->catdir($tmp, 'mo');
mkdir $_ or die "$_: $!" for $lib, File::Spec->catdir($lib, 'T');
sub module
{
	my ($name, $text) = @_;
	open my $fh, '>', File::Spec->catfile($lib, 'T', "$name.pm") or die "$name: $!";
	print $fh "package T::$name;\n$text\n1;\n";
	close $fh or die $!;
}
module(L10N => "our \$DOMAIN = 'test';\nour \$LOCALEDIR = '$mo';");
module(NoDomain => "our \$LOCALEDIR = '$mo';");
module(Unbuilt => "our \$DOMAIN = 'test';\nour \$LOCALEDIR = \@localedir\@;");
unshift @INC, $lib;
ok(install('T::NoDomain', ':module' => 'T::NoDomain'), ':module with no $DOMAIN');
is(T::NoDomain::__('x'), 'x', '... as it is written');
ok(install('T::Unbuilt', ':module' => 'T::Unbuilt'), ':module that is not built')
	or diag $@;
is(T::Unbuilt::__('x'), 'x', '... as it is written');

# --- what is not said
for my $bad ([], [':moduel', 'T::L10N'], [':module'], [':module', 'T::L10N', 'x'],
	[':module', 'not a name'], [''], [undef], ['a', 'b', 'c'])
{
	ok(!install('T::Bad', @$bad), 'dies: (' . join(', ', map { defined ? "'$_'" : 'undef' } @$bad) . ')');
}

# --- without Locale::Messages, as it is written
{
	my $code = 'BEGIN { unshift @INC, sub { die "hidden\n" if $_[1] eq "Locale/Messages.pm"; return } }'
		. ' package P; use RdKw::L10N::Utf8TextDomain "test", $ARGV[0];'
		. ' binmode STDOUT, ":encoding(UTF-8)";'
		. ' print join "|", __("hello"), __n("one file", "%d files", 2), N__("x"),'
		. ' eval { require Locale::Messages; 1 } ? "has" : "hasnot"';
	my @inc = map { "-I$_" } grep { !ref } @INC;
	my $out = `"$^X" @inc -e '$code' '$mo'`;
	is($?, 0, 'without Locale::Messages: loads');
	is($out, 'hello|%d files|x|hasnot', '... and says as it is written');
}

SKIP: {
	skip 'Locale::Messages required', 2 unless $HAVE_GETTEXT;
	use Errno qw( EACCES ENOENT );
	# gettext may set $! (as libintl does, failing to open the catalogs
	# that are not there), but $! is as it was after, for a %m
	no warnings qw( redefine once );
	local *Locale::Messages::dgettext = sub { $! = ENOENT; $_[1] };
	local *Locale::Messages::dngettext = sub { $! = ENOENT; $_[3] == 1 ? $_[1] : $_[2] };
	$! = EACCES;
	T::None::__('x');
	is(0 + $!, EACCES, '__: $! as it was');
	$! = EACCES;
	T::None::__n('one file', '%d files', 2);
	is(0 + $!, EACCES, '__n: likewise');
}

# --- with a catalog
SKIP: {
	my $msgfmt = grep { -x File::Spec->catfile($_, 'msgfmt') } File::Spec->path;
	skip 'msgfmt (GNU gettext) required', 6 unless $msgfmt;
	skip 'Locale::Messages required', 6 unless $HAVE_GETTEXT;
	skip 'POSIX::LC_MESSAGES required', 6
		unless eval { require POSIX; defined POSIX::LC_MESSAGES() };
	my $dir = File::Spec->catdir($mo, 'zh', 'LC_MESSAGES');
	require File::Path;
	File::Path::mkpath($dir);
	my $po = File::Spec->catfile($tmp, 'zh.po');
	open my $fh, '>:encoding(UTF-8)', $po or die "$po: $!";
	print $fh <<'PO';
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Plural-Forms: nplurals=1; plural=0;\n"

msgid "hello"
msgstr "你好"

msgid "炒饭"
msgstr "fried rice"

msgid "one file"
msgid_plural "%d files"
msgstr[0] "%d 个文件"
PO
	close $fh or die $!;
	system('msgfmt', '-o', File::Spec->catfile($dir, 'test.mo'), $po) == 0
		or skip 'msgfmt failed', 6;

	# A locale that is not C, by an XPG name: LANGUAGE is not heard in C
	# (see gengenlib-l10n's t/l10n.t)
	my $XPG = qr/\A[a-z][a-z](?:_[A-Z][A-Z](?:\.[-_A-Za-z0-9]+)?)?(?:\@[-_A-Za-z0-9]+)?\z/;
	my $locale = POSIX::setlocale(POSIX::LC_MESSAGES());
	unless (defined $locale && $locale =~ $XPG) {
		my @try;
		no warnings 'exec';
		if (open my $ph, '-|', 'locale', '-a') {
			@try = grep { /$XPG/ } map { chomp; $_ } <$ph>;
			close $ph;
		}
		push @try, qw( en_US.UTF-8 en_GB.UTF-8 );
		undef $locale;
		for (@try) { $locale = $_, last if POSIX::setlocale(POSIX::LC_MESSAGES(), $_) }
		skip 'no non-C locale found', 6 unless defined $locale;
	}
	# (the pure Perl one reads the catalog, whatever locales are installed)
	Locale::Messages::select_package('gettext_pp');
	local $ENV{LC_ALL} = $locale;
	local $ENV{LANGUAGE} = 'zh';
	POSIX::setlocale(POSIX::LC_MESSAGES(), $locale);

	ok(install('T::Zh', ':module' => 'T::L10N'), ':module') or diag $@;
	is(T::Zh::__('hello'), "\x{4f60}\x{597d}", '__: as the catalog says, in characters');
	is(T::Zh::__('炒饭'), 'fried rice', '... of a msgid that is not ASCII');
	is(T::Zh::__n('one file', '%d files', 3), "%d \x{4e2a}\x{6587}\x{4ef6}", '__n: likewise');
	is(T::Zh::__('nope'), 'nope', '... or as it is written, if it has not');
	{
		local $ENV{OUTPUT_CHARSET} = 'ISO-8859-1';
		is(T::Zh::__('hello'), "\x{4f60}\x{597d}", '... UTF-8, whatever OUTPUT_CHARSET says');
	}
}

done_testing;
