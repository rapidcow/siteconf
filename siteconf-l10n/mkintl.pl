#!/usr/bin/env perl
#
# mkintl.pl - the message catalogs of siteconf, and how to make them
#
#     perl mkintl.pl [-B BUILD] [LINGUAS="en zh"] LOCALEDIR=/usr/local/share/locale
#     make -C BUILD && make -C BUILD install
#
# writes BUILD/Makefile (BUILD is the current directory, unless
# given; it must exist, and must not be this one, which has a
# Makefile of its own), which makes the catalogs of LINGUAS (all of
# po/*.po, unless given) and installs them in LOCALEDIR, which has
# no default here: it is wherever RdKw::WwW::SiteConf::L10N was
# told they are (perl -MRdKw::WwW::SiteConf::L10N -le
# 'print $RdKw::WwW::SiteConf::L10N::LOCALEDIR').
#
# Makefile.PL does this file too, for the routines below.

use 5.008;
use strict;
use warnings;

use Cwd ();
use File::Basename qw( basename dirname );
use File::Spec;
use Getopt::Long ();

our $DOMAIN = 'siteconf';

# Where the po/ directory is (wherever we are done from)
our $SRCDIR = File::Spec->rel2abs(dirname(__FILE__));

# Take KEY=VALUE for these out of @$argv (so that MakeMaker does not
# see them), and give them back
sub take_args
{
	my ($argv) = @_;
	my %arg;
	@$argv = grep { /\A(LINGUAS|LOCALEDIR)=(.*)\z/s ? do { $arg{$1} = $2; 0 } : 1 } @$argv;
	%arg;
}

# The languages of LINGUAS (blank-separated), which must each have
# a po/LANG.po; all of them, if LINGUAS is undef and $all says so
sub linguas
{
	my ($linguas, $all) = @_;
	my $po = File::Spec->catdir($SRCDIR, 'po');
	unless (defined $linguas) {
		return () unless $all;
		opendir my $dh, $po or die "cannot open $po: $!\n";
		return sort map { /\A(.+)\.po\z/ ? $1 : () } readdir $dh;
	}
	my @lang = split ' ', $linguas;
	for (@lang) {
		/\A[A-Za-z]{2,3}(?:_[A-Za-z0-9]+)?(?:\@[A-Za-z0-9]+)?\z/
			or die "LINGUAS: `$_' is no language\n";
		-f File::Spec->catfile($po, "$_.po")
			or die "LINGUAS: no catalog for `$_' (no po/$_.po)\n";
	}
	@lang;
}

# How to make a catalog: a command that takes -o OUT IN, as
# msgfmt(1) does, for a Makefile in which $(PERL) is perl
sub find_msgfmt
{
	require File::Which;
	my $bin = File::Which::which('msgfmt');
	return make_quote(qq{"$bin"}) if defined $bin;
	# (-o is left over, and that is fine)
	return '$(PERL) -MLocale::Msgfmt -e "msgfmt({ in => pop, out => pop })" --'
		if eval { require Locale::Msgfmt; 1 };
	die "cannot make message catalogs: neither msgfmt (GNU gettext)"
		. " nor Locale::Msgfmt is installed\n";
}

# A path, for a Makefile
sub make_quote
{
	my ($s) = @_;
	$s =~ /[\n\r]/ and die "a newline in `$s' cannot be said to make\n";
	$s =~ s/\$/\$\$/g;
	$s =~ s/#/\\#/g;
	$s;
}

# ... which the shell is told of, in double quotes (by us, and again
# by MakeMaker's pm_to_blib, for PM_FILTER), and so cannot have in it
# what means anything there
sub make_path
{
	my ($s) = @_;
	$s =~ /([\$"`\\\n\r])/
		and die "`$s' cannot be said to the shell (it has a "
			. ($1 eq "\n" || $1 eq "\r" ? 'line break' : "`$1'") . " in it)\n";
	make_quote($s);
}

# What makes (intl), installs (install_intl), and removes
# (clean_intl) the catalogs of @$linguas: their sources are in
# $po, and they are made in mo/, with $msgfmt.  The Makefile says
# PERL, MKPATH, CP, CHMOD, PERM_RW, RM_RF and LOCALEDIR (and maybe
# DESTDIR).
sub rules
{
	my (%o) = @_;
	my @lang = @{ $o{linguas} };
	my $mo = "$DOMAIN.mo";
	my $text = <<MAKE_FRAG;
INTL_DOMAIN = $DOMAIN
INTL_LINGUAS = @lang
INTL_PO = @{[ make_path($o{po}) ]}
MSGFMT = $o{msgfmt}

intl :: @{[ map { "mo/$_/LC_MESSAGES/$mo" } @lang ]}

MAKE_FRAG
	for my $lang (@lang) {
		my $dir = "mo/$lang/LC_MESSAGES";
		$text .= <<MAKE_FRAG;
$dir/$mo : \$(INTL_PO)/$lang.po
	\$(MKPATH) $dir
	\$(MSGFMT) -o $dir/$mo "\$(INTL_PO)/$lang.po"

MAKE_FRAG
	}
	$text .= "install_intl :: intl\n";
	for my $lang (@lang) {
		my $dir = "$lang/LC_MESSAGES";
		$text .= <<MAKE_FRAG;
	\$(MKPATH) "\$(DESTDIR)\$(LOCALEDIR)/$dir"
	\$(CP) mo/$dir/$mo "\$(DESTDIR)\$(LOCALEDIR)/$dir/$mo"
	\$(CHMOD) \$(PERM_RW) "\$(DESTDIR)\$(LOCALEDIR)/$dir/$mo"
MAKE_FRAG
	}
	$text . <<'MAKE_FRAG';

clean_intl ::
	$(RM_RF) mo
MAKE_FRAG
}

sub main
{
	my $Me = basename($0);
	my $usage = "usage: $Me [-B BUILD] [LINGUAS=\"LANG ...\"] LOCALEDIR=DIR\n";
	my $build = '.';
	Getopt::Long::GetOptions('B=s' => \$build) or die $usage;
	my %arg = take_args(\@ARGV);
	@ARGV and die "$Me: what is `$ARGV[0]'?\n$usage";

	my $localedir = $arg{LOCALEDIR};
	defined $localedir && length $localedir
		or die "$Me: where should they go?  LOCALEDIR=... is required\n$usage";
	File::Spec->file_name_is_absolute($localedir)
		or die "$Me: LOCALEDIR=$localedir is not absolute\n";
	eval { make_path($localedir); 1 } or die "$Me: LOCALEDIR=$@";

	-d $build or die "$Me: no build directory $build (make it first)\n";
	my $real = Cwd::realpath($build);
	defined $real && $real ne Cwd::realpath($SRCDIR)
		or die "$Me: $build is the source directory, whose Makefile is"
			. " Makefile.PL's; use -B BUILD (or Makefile.PL LINGUAS=...)\n";
	$real =~ /[\s#\$:%"\\]/ || $SRCDIR =~ /[\s#\$:%"\\]/
		and die "$Me: make cannot be told of $real or $SRCDIR\n";

	my @lang = eval { linguas($arg{LINGUAS}, 1) } or die "$Me: ${\ ($@ || \"no catalogs\n\") }";
	my $msgfmt = eval { find_msgfmt() } or die "$Me: $@";

	my $makefile = File::Spec->catfile($real, 'Makefile');
	open my $fh, '>', $makefile or die "$Me: cannot open $makefile: $!\n";
	print $fh <<MAKE_FRAG, rules(linguas => \@lang, po => "$SRCDIR/po", msgfmt => $msgfmt)
# The message catalogs of $DOMAIN, by $Me:
#
#     make && make install [DESTDIR=...]

PERL = @{[ make_quote(qq{"$^X"}) ]}
MKPATH = \$(PERL) -MExtUtils::Command -e mkpath --
CP = \$(PERL) -MExtUtils::Command -e cp --
CHMOD = \$(PERL) -MExtUtils::Command -e chmod --
RM_RF = \$(PERL) -MExtUtils::Command -e rm_rf --
PERM_RW = 644
DESTDIR =
LOCALEDIR = @{[ make_path($localedir) ]}

all : intl

install : install_intl

clean : clean_intl

MAKE_FRAG
		or die "$Me: write $makefile: $!\n";
	close $fh or die "$Me: write $makefile: $!\n";
	print "Writing $makefile for $DOMAIN (LINGUAS=@lang)\n";
	0;
}

exit main() unless caller;

1;
