#!perl
#
# t/l10n.t - what siteconf says, in the catalogs made here (mo/,
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
plan skip_all => q[no catalogs made (re-run with `perl Makefile.PL LINGUAS="en zh"'?)]
	unless -f "$mo/zh/LC_MESSAGES/siteconf.mo" && -f "$mo/en/LC_MESSAGES/siteconf.mo";
plan skip_all => 'Locale::Messages required'
	unless eval { require Locale::Messages; 1 };
plan skip_all => 'POSIX::LC_MESSAGES required'
	unless eval { require POSIX; defined POSIX::LC_MESSAGES(); };

require RdKw::WwW::SiteConf::L10N;
{
	no warnings 'once';
	$RdKw::WwW::SiteConf::L10N::LOCALEDIR = $mo;
}
# (the pure Perl one reads the catalog, whatever locales are installed)
Locale::Messages::select_package('gettext_pp');
plan skip_all => 'RdKw::WwW::SiteConf (and what it needs) required'
	unless eval { require RdKw::WwW::SiteConf; 1 };
# A locale that is not C, by an XPG name (language[_TERRITORY
# [.codeset]][@modifier], as gettext_pp has it): LANGUAGE is not heard
# in C, and some gettext_pp take C.UTF-8 for C.  Its codeset does not
# matter, since the domain is bound to UTF-8; so yours will do, if it
# is one.  Else, one that `locale -a' lists, or one that is likely to
# be there anyway.
my $XPG = qr/\A[a-z][a-z](?:_[A-Z][A-Z](?:\.[-_A-Za-z0-9]+)?)?(?:\@[-_A-Za-z0-9]+)?\z/;
my $locale = POSIX::setlocale(POSIX::LC_MESSAGES());
my @try;
if (defined $locale && $locale =~ $XPG) {
	diag "Using YOUR locale! $locale";
}
else {
	undef $locale;
	no warnings 'exec';
	if (open my $fh, '-|', 'locale', '-a') {
		@try = grep { /$XPG/ } map { chomp; $_ } <$fh>;
		close $fh;
	}
	# being conservative here unless i know it is used.
	# en_US is on Termux, en_GB is stock Raspberry Pi...
	push @try, qw( en_US.UTF-8 en_GB.UTF-8 );
	$locale = List::Util::first { POSIX::setlocale(POSIX::LC_MESSAGES(), $_) } @try;
	plan skip_all => 'no non-C locale found :(' unless defined $locale;
	diag "Using non-C locale: $locale";
}
plan tests => 11;
diag("Locale::Messages $Locale::Messages::VERSION ($INC{'Locale/gettext_pp.pm'})");

my $cs = RdKw::I18N::CodeSets->new(stderr => 'UTF-8', filesys => 'UTF-8', diag => 'unicode');
local $RdKw::I18N::CodeSets::LOCALE = $cs;

# What `code' says, in LANGUAGE
sub in
{
	my ($language, $code) = @_;
	local $ENV{LC_ALL} = $locale;
	local $ENV{LANGUAGE} = $language;
	POSIX::setlocale(POSIX::LC_MESSAGES(), $locale);
	$code->();
}

# What siteconf says of a build directory that is not configured, in
# LANGUAGE
sub says
{
	my ($language) = @_;
	in($language, sub {
		eval { RdKw::WwW::SiteConf->new(B => "nope\x{e9}"); 1 } and return;
		$@;
	});
}

like(says('zh'), qr/\AE: 你还没有配置！（没有 "nope\x{e9}\/MY\/config\.mk"）\nE: 请先运行/, 'zh');
like(says('en'), qr/\AE: You have not configured!  \(no "nope\x{e9}\/MY\/config\.mk"\)\nE: You should/,
	'en');
like(says('xx'), qr/\AE: You have not configured!  \(no "nope\x{e9}\/MY\/config\.mk"\)\nE: You should/,
	'no catalog: as it is written');
{
	local $RdKw::I18N::CodeSets::LOCALE = $cs->new(diag => 'ascii');
	like(says('zh'), qr/\AE: 你还没有配置！（没有 "nope\\x\{e9\}\/MY\/config\.mk"）/,
		'the name is said as CodeSets says');
}
{
	local $ENV{OUTPUT_CHARSET} = 'ISO-8859-1';
	like(says('zh'), qr/\AE: 你还没有配置！（没有 "nope\x{e9}\/MY\/config\.mk"）/,
		'UTF-8, whatever OUTPUT_CHARSET says');
}

my @problems = ('%d problem; no Makefile for you.', '%d problems; no Makefile for you.');
is(in(zh => sub { RdKw::WwW::SiteConf::__n(@problems, 2) }), '%d 个问题；不给你 Makefile。',
	'__n: one form, in zh');
is(in(en => sub { RdKw::WwW::SiteConf::__n(@problems, 1) }), $problems[0], '__n: one, in en');
is(in(en => sub { RdKw::WwW::SiteConf::__n(@problems, 2) }), $problems[1], '__n: more, in en');
# (what configure says of its help, which it says later, as N__ marks it)
is(in(zh => sub { RdKw::WwW::SiteConf::__('Disable tips') }), '关闭提示', 'a msgid that is N__ there');

# gettext may set $! (as libintl does, failing to open the catalogs
# that are not there; gettext_pp does not), but $! is as it was after
# __, for a %m
{
	use Errno qw( EACCES ENOENT );
	no warnings 'once', 'redefine';
	local *Locale::Messages::dgettext = sub { $! = ENOENT; $_[1] };
	local *Locale::Messages::dngettext = sub { $! = ENOENT; $_[3] == 1 ? $_[1] : $_[2] };
	$! = EACCES;
	RdKw::WwW::SiteConf::__('x');
	is(0 + $!, EACCES, '__: $! as it was');
	$! = EACCES;
	RdKw::WwW::SiteConf::__n('one file', '%s files', 2);
	is(0 + $!, EACCES, '__n: likewise');
}
