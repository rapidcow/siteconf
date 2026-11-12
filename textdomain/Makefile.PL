use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
	NAME             => 'L10N::TextDomain',
	AUTHOR           => q{rapidcow},
	VERSION_FROM     => 'lib/RdKw/L10N/TextDomain.pm',
	ABSTRACT_FROM    => 'lib/RdKw/L10N/TextDomain.pm',
	LICENSE          => 'gpl_3',
	MIN_PERL_VERSION => '5.008',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '0',
	},
	TEST_REQUIRES => {
		'File::Spec' => '0',
		'File::Temp' => '0',
		'Test::More' => '0',
	},
	# (nothing but what comes with Perl)
	PREREQ_PM => {
		'Carp' => '0',
		'Encode' => '0',
	},
	# What is said is said in the language of the locale, with this
	# (and as it is written, without it)
	META_MERGE => {
		'meta-spec' => { version => 2 },
		prereqs => { runtime => { recommends => {
			'Locale::Messages' => '0',
		} } },
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES => 'L10N-TextDomain-*' },
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

sub postamble
{
	my $command = '$(FULLPERLRUN)';
	<<'MAKE_FRAG' .
EXTRA_TEST_FILES=	xt/*
xtest :: subdirs-test_dynamic
MAKE_FRAG
	$_[0]->test_via_harness($command, '$(EXTRA_TEST_FILES)');
}
