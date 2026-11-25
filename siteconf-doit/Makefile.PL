use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
	NAME             => 'WwW::SiteConf::Doit',
	AUTHOR           => q{rapidcow},
	VERSION_FROM     => 'lib/RdKw/WwW/SiteConf/Builder/Doit.pm',
	ABSTRACT         => q{dodo.py generator for siteconf},
	LICENSE          => 'gpl_3',
	MIN_PERL_VERSION => '5.008',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '0',
	},
	TEST_REQUIRES => {
		'Test::More' => '0',
	},
	# The same version as siteconf: they are released together
	PREREQ_PM => {
		'version' => '0',
		'RdKw::WwW::SiteConf' => '0.03_00',
		'RdKw::I18N::CodeSets' => '0',
		'RdKw::L10N::TextDomain' => '0',
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES => 'WwW-SiteConf-Doit-*' },
	test => { TESTS => 't/*.t' },
);

# Compatibility with old versions of ExtUtils::MakeMaker
unless (eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 }) {
    my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES} || {};
    @{$WriteMakefileArgs{PREREQ_PM}}{keys %$test_requires} = values %$test_requires;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION('6.52'); 1 };
delete $WriteMakefileArgs{MIN_PERL_VERSION}
    unless eval { ExtUtils::MakeMaker->VERSION('6.48'); 1 };
delete $WriteMakefileArgs{LICENSE}
    unless eval { ExtUtils::MakeMaker->VERSION('6.31'); 1 };

WriteMakefile(%WriteMakefileArgs);

package MY;

sub postamble
{
	my $command = '$(FULLPERLRUN)';
	<<'MAKE_FRAG' . $_[0]->test_via_harness($command, '$(EXTRA_TEST_FILES)');
EXTRA_TEST_FILES=	xt/*
xtest :: subdirs-test_dynamic
MAKE_FRAG
}
