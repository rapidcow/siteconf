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
use Test::More;

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
# (LANGUAGE is not heard in the C locale)
my ($utf8) = grep { POSIX::setlocale(POSIX::LC_MESSAGES(), $_) } qw( C.UTF-8 en_US.UTF-8 );
plan skip_all => 'no UTF-8 locale (C.UTF-8 or en_US.UTF-8) installed' unless defined $utf8;
plan tests => 6;

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
