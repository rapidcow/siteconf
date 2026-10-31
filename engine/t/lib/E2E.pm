package E2E;
#
# t/lib/E2E.pm - what t/e2e-*.t have in common: a copy of t/fixture/web
# in a directory of its own, which we stand in, and a built siteconf.
#
use strict;
use warnings;
use Test::More;
use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Spec;
use File::Temp qw( tempdir );

use parent qw( Exporter );
our @EXPORT = qw( run slurp );

my $dir;	# (it is removed when we are)

# Skips the test file unless all is well; otherwise returns the
# path to our siteconf, having cd'd to the copy of the fixture.
sub setup
{
	for my $m (qw( Template URI )) {
		eval "require $m; 1" or plan skip_all => "$m is not installed";
	}

	my $root = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir, File::Spec->updir));
	my $script = "$root/blib/script/siteconf";
	-f $script or plan skip_all => "not built: perl Makefile.PL && make, in engine/ and genlib/";
	my $fixture = "$root/t/fixture/web";
	# Whatever lets us load our modules lets the children do so
	$ENV{PERL5LIB} = join ':', map { abs_path($_) } grep { defined && -d } @INC;

	$dir = tempdir(CLEANUP => 1);
	system('cp', '-R', "$fixture/.", $dir) == 0 or die "cp: $?";
	chdir $dir or die;
	$script;
}

# `make' or whatever $MAKE says, if it can run a makefile at all.
# (Not `make -v': that is a different thing to bmake.)
sub make
{
	my $make = $ENV{MAKE} || 'make';
	system("printf 'all:\\n' | $make -f - >/dev/null 2>&1") == 0
		or plan skip_all => "no make";
	$make;
}

sub run
{
	my ($desc, @cmd) = @_;
	my $out = `@cmd 2>&1`;
	my $ok = ok($? == 0, $desc);
	diag $out unless $ok;
	$out;
}

sub slurp { open my $fh, '<:utf8', $_[0] or return; local $/; <$fh> }

# the end: out of the directory that is about to go
sub done
{
	chdir '/';
	done_testing;
}

1;
