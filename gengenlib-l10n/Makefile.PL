use 5.008;
use strict;
use warnings;
# (6.31 for INSTALL_BASE, where LOCALEDIR is by default)
use ExtUtils::MakeMaker 6.31;

#
#     perl Makefile.PL [LINGUAS="en zh"] [LOCALEDIR=DIR]
#
# LINGUAS are the catalogs to make and install (none, unless given);
# LOCALEDIR is where (INSTALL_BASE or PREFIX, then share/locale,
# unless given).  They are ours, not MakeMaker's.
#
do './mkintl.pl' or die "mkintl.pl: " . ($@ || "$!\n");
my %intl = take_args(\@ARGV);
my @linguas = linguas($intl{LINGUAS});
my $msgfmt = @linguas ? find_msgfmt() : undef;
if (defined $intl{LOCALEDIR}) {
	File::Spec->file_name_is_absolute($intl{LOCALEDIR})
		or die "LOCALEDIR=$intl{LOCALEDIR} is not absolute\n";
	# (or dies, before MakeMaker begins)
	make_path($intl{LOCALEDIR});
}

my %WriteMakefileArgs = (
	NAME             => 'WwW::GenGenLib::L10N',
	AUTHOR           => q{rapidcow},
	VERSION_FROM     => 'lib/RdKw/WwW/GenGenLib/L10N.pm',
	ABSTRACT_FROM    => 'lib/RdKw/WwW/GenGenLib/L10N.pm',
	LICENSE          => 'gpl_3',
	MIN_PERL_VERSION => '5.008',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '6.31',
		'File::Which' => '0',
	},
	BUILD_REQUIRES => {
		'File::Which' => '0',
	},
	TEST_REQUIRES => {
		'Test::More' => '0',
	},
	PREREQ_PM => {
	},
	# (not mkintl.pl or pm_filter.pl, which are no modules)
	PM => {
		'lib/RdKw/WwW/GenGenLib/L10N.pm' => '$(INST_LIB)/RdKw/WwW/GenGenLib/L10N.pm',
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES => 'WwW-GenGenLib-L10N-* mo' },
	test => { TESTS => 't/*.t' },
);

# Compatibility with old versions of ExtUtils::MakeMaker
unless (eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 }) {
    my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES} || {};
    @{$WriteMakefileArgs{PREREQ_PM}}{keys %$test_requires} = values %$test_requires;
}

unless (eval { ExtUtils::MakeMaker->VERSION('6.55_03'); 1 }) {
    my $build_requires = delete $WriteMakefileArgs{BUILD_REQUIRES} || {};
    @{$WriteMakefileArgs{PREREQ_PM}}{keys %$build_requires} = values %$build_requires;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION('6.52'); 1 };
delete $WriteMakefileArgs{MIN_PERL_VERSION}
    unless eval { ExtUtils::MakeMaker->VERSION('6.48'); 1 };
delete @WriteMakefileArgs{qw(META_ADD META_MERGE)}
    unless eval { ExtUtils::MakeMaker->VERSION('6.46'); 1 };
delete $WriteMakefileArgs{LICENSE}
    unless eval { ExtUtils::MakeMaker->VERSION('6.31'); 1 };

WriteMakefile(%WriteMakefileArgs);

package MY;

# LOCALEDIR, and @localedir@ in the module is it
sub post_initialize
{
	my $self = shift;
	my $dir = defined $intl{LOCALEDIR}
		? ::make_path($intl{LOCALEDIR})
		: ($self->{INSTALL_BASE} || $self->{PREFIX}) . '/share/locale';
	$self->{PM_FILTER} = '$(PERLRUN) pm_filter.pl "$(LOCALEDIR)"';
	$self->SUPER::post_initialize(@_) . "LOCALEDIR = $dir\n";
}

sub postamble
{
	my $self = shift;
	my $command = '$(FULLPERLRUN)';
	my $text = <<'MAKE_FRAG' . $self->test_via_harness($command, '$(EXTRA_TEST_FILES)');
EXTRA_TEST_FILES=	xt/*
xtest :: subdirs-test_dynamic
MAKE_FRAG

	# For the maintainer: po/gengenlib.pot from the sources, and the
	# catalogs brought up to date with it
	$text .= <<'MAKE_FRAG';

GENGENLIB = ../gengenlib
PROVIDER = ../template-provider
XGETTEXT = xgettext
MSGMERGE = msgmerge

pot :
	$(XGETTEXT) -L Perl --from-code=UTF-8 -k__ -k__n:1,2 \
		--package-name=WwW-GenGenLib --add-comments='HEY!' \
		-o po/gengenlib.pot \
		$(GENGENLIB)/lib/RdKw/WwW/GenGenLib.pm \
		$(GENGENLIB)/lib/RdKw/WwW/GenGenLib/Manifest.pm \
		$(PROVIDER)/lib/RdKw/WwW/GenGenLib/Template/Provider.pm

update-po : pot
	for po in po/*.po; do \
		$(MSGMERGE) -U --backup=none "$$po" po/gengenlib.pot || exit 1; \
	done
MAKE_FRAG

	@linguas or return $text;
	$text . "\n" . ::rules(linguas => \@linguas, po => 'po', msgfmt => $msgfmt)
		. <<'MAKE_FRAG';

pure_all :: intl

pure_install :: install_intl

clean :: clean_intl
MAKE_FRAG
}
