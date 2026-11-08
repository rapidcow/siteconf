use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;
use File::ShareDir::Install qw(install_share);

my %WriteMakefileArgs = (
	NAME             => 'WwW::SiteConf',
	AUTHOR           => q{rapidcow},
	VERSION_FROM     => 'lib/RdKw/WwW/SiteConf.pm',
	ABSTRACT         => q{Web site transformation rulebook configuration utilties},
	LICENSE          => 'gpl_3',
	MIN_PERL_VERSION => '5.006',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '0',
		'File::ShareDir::Install' => '0',
	},
	TEST_REQUIRES => {
		'Test::More' => '0',
	},
	PREREQ_PM => {
		'version' => '0',
		'File::ShareDir' => '0',
		'RdKw::WwW::GenGenLib' => '0.0003',
		# RdKw::WwW::GenLib isn't a dependency, though
		# for those who use the web preset it is when
		# they run the render script (... which we don't
		# seem to generate so it's likely known dep :v)
	},
	EXE_FILES => [
		'script/siteconf',
	],
	MAN1PODS => {
		'script/siteconf' => 'blib/man1/siteconf.1',
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES => 'WwW-SiteConf-*' },
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

install_share('share');
WriteMakefile(%WriteMakefileArgs);

package MY;

sub postamble
{
	my ($Me) = @_;
	my $command = '$(FULLPERLRUN)';
	File::ShareDir::Install::postamble($Me) . <<'MAKE_FRAG' .
EXTRA_TEST_FILES=	xt/*
xtest :: subdirs-test_dynamic
MAKE_FRAG
	$_[0]->test_via_harness($command, '$(EXTRA_TEST_FILES)');
}
