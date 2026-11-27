package E2E;
#
# t/lib/E2E.pm - siteconf's t/fixture/web, copied to a directory of its
# own, which we stand in, and siteconf's built script.  Both are found
# next to this distribution, in ../siteconf (or $SITECONF_DIR), as in
# the source repository; without them, the test is skipped.
#
use strict;
use warnings;
use Test::More;

use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Temp qw( tempdir );

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT = qw( run slurp );

# What siteconf says is said as it is written
$ENV{LANGUAGE} = 'C';
delete $ENV{SITECONF_CODESETS};

my $dist = $ENV{SITECONF_DIR} || dirname(__FILE__) . '/../../../siteconf';
my $dir;	# (it is removed when we are)

# Skips the test file unless all is well; otherwise returns the
# path to siteconf, having cd'd to the copy of the fixture.
sub setup
{
	for my $m (qw( Template RdKw::WwW::GenLib )) {
		eval "require $m; 1" or plan skip_all => "$m is not installed";
	}
	my $root = abs_path($dist);
	my $script = defined $root && "$root/blib/script/siteconf";
	my $fixture = defined $root && "$root/t/fixture/web";
	defined $root && -f $script && -d $fixture
		or plan skip_all => "no built siteconf next to us (set SITECONF_DIR)";
	# Whatever lets us load our modules lets the children do so
	$ENV{PERL5LIB} = join ':', map { abs_path($_) } grep { defined && !ref && -d } @INC;

	$dir = tempdir(CLEANUP => 1);
	system('cp', '-R', "$fixture/.", $dir) == 0 or die "cp: $?";
	chdir $dir or die;
	$script;
}

sub run
{
	my ($desc, @cmd) = @_;
	my $out = `@cmd 2>&1`;
	my $ok = ok($? == 0, $desc);
	diag $out unless $ok;
	$out;
}

sub slurp { open my $fh, '<:utf8', $_[0] or return; local $/; <$fh>; }

# the end: out of the directory that is about to go
sub done
{
	chdir '/';
	done_testing;
}

1;
