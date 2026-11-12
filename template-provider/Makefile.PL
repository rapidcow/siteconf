use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
	NAME             => 'WwW::GenGenLib::Template::Provider',
	AUTHOR           => q{rapidcow},
	VERSION_FROM     => 'lib/RdKw/WwW/GenGenLib/Template/Provider.pm',
	ABSTRACT_FROM    => 'lib/RdKw/WwW/GenGenLib/Template/Provider.pm',
	LICENSE          => 'gpl_3',
	MIN_PERL_VERSION => '5.008',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '0',
	},
	TEST_REQUIRES => {
		'Encode' => '0',
		'Encode::Locale' => '0',
		'PerlIO::encoding' => '0',
		'Test::More' => '0',
	},
	PREREQ_PM => {
		'Cwd' => '0',
		'File::Spec' => '0',
		'RdKw::I18N::CodeSets' => '0',
		'RdKw::WwW::GenGenLib' => '0.0100',
		'Template' => '0',
		'Template::Constants' => '0',
		'Template::Provider' => '0',
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES => 'WwW-GenGenLib-Template-Provider-*' },
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
