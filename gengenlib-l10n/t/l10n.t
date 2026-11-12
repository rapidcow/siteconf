#!perl
#
# t/l10n.t - what gengenlib says, in the catalogs made here (mo/,
# as made by perl Makefile.PL LINGUAS="en zh")

use 5.008;
use strict;
use warnings;
use utf8;
use Cwd ();
use File::Spec;
use List::Util ();
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

my $mo = File::Spec->rel2abs('mo');
plan skip_all => 'no catalogs made (perl Makefile.PL LINGUAS="en zh")'
	unless -f "$mo/zh/LC_MESSAGES/gengenlib.mo" && -f "$mo/en/LC_MESSAGES/gengenlib.mo";
plan skip_all => 'Locale::Messages required'
	unless eval { require Locale::Messages; 1 };
plan skip_all => 'POSIX::LC_MESSAGES required'
	unless eval { require POSIX; defined POSIX::LC_MESSAGES(); };

require RdKw::WwW::GenGenLib::L10N;
{
	no warnings 'once';
	$RdKw::WwW::GenGenLib::L10N::LOCALEDIR = $mo;
}
# (the pure Perl one reads the catalog, whatever locales are installed)
Locale::Messages::select_package('gettext_pp');
plan skip_all => 'RdKw::WwW::GenGenLib (and RdKw::I18N::CodeSets) required'
	unless eval { require RdKw::WwW::GenGenLib; 1 };
# A UTF-8 locale that is not C, by an XPG name (language_TERRITORY.
# codeset): LANGUAGE is not heard in C, and some gettext_pp take
# C.UTF-8 for C.  Whatever `locale -a' lists (glibc spells it utf8),
# and then what is likely to be there anyway.
my $XPG_UTF8 = qr/\A[a-z][a-z]_[A-Z][A-Z]\.(?i:utf-?8)\z/;
my @try;
{
	no warnings 'exec';
	if (open my $fh, '-|', 'locale', '-a') {
		@try = grep { /$XPG_UTF8/ } map { chomp; $_ } <$fh>;
		close $fh;
	}
}
# being conservative here unless i know it is used.
# en_US is on Termux, en_GB is stock Raspberry Pi...
push @try, qw( en_US.UTF-8 en_GB.UTF-8 );
my $utf8 = List::Util::first { POSIX::setlocale(POSIX::LC_MESSAGES(), $_) } @try;
plan skip_all => 'no UTF-8 locale (but C) installed' unless defined $utf8;
diag "Using non-C locale: $utf8";
plan tests => 6;
diag("Locale::Messages $Locale::Messages::VERSION ($INC{'Locale/gettext_pp.pm'})");

my $cs = RdKw::I18N::CodeSets->new(diag => 'unicode');
local $RdKw::I18N::CodeSets::LOCALE = $cs;

# What read_deps says of a file that is not there, in LANGUAGE
sub says
{
	my ($language) = @_;
	local $ENV{LC_ALL} = $utf8;
	local $ENV{LANGUAGE} = $language;
	POSIX::setlocale(POSIX::LC_MESSAGES(), $utf8);
	eval { RdKw::WwW::GenGenLib::read_deps("nope\x{e9}"); 1 } and return;
	$@;
}

like(says('zh'), qr/\Aread_deps: 无法打开文件 "nope\x{e9}"：/, 'zh');
like(says('en'), qr/\Aread_deps: cannot open file "nope\x{e9}": /, 'en');
like(says('xx'), qr/\Aread_deps: cannot open file "nope\x{e9}": /,
	'no catalog: as it is written');
{
	local $RdKw::I18N::CodeSets::LOCALE = RdKw::I18N::CodeSets->new(diag => 'ascii');
	like(says('zh'), qr/\Aread_deps: 无法打开文件 "nope\\x\{e9\}"：/,
		'the name is said as CodeSets says');
}

is(RdKw::WwW::GenGenLib::__n('one file', '%s files', 1), 'one file', '__n: one');
is(RdKw::WwW::GenGenLib::__n('one file', '%s files', 2), '%s files', '__n: more');
