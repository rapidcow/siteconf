package TestPaths;

use strict;
use warnings;
use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Spec;
use Test::More ();
use parent qw( Exporter );
our @EXPORT_OK = qw( project_root script_path perl5lib );

# Use locale encoding for wide-characters, since console
# output/error is often meant for humans and not machine-
# consumable.  Fall back to ASCII \x{...} when a Unicode
# character cannot be encoded, however.
{
	require Encode;
	require Encode::Locale;
	require PerlIO::encoding;
	local $PerlIO::encoding::fallback = Encode::PERLQQ();
	my $tb = Test::More->builder;
	binmode $tb->$_, ':encoding(console_out)' for qw( output failure_output todo_output );
}

# What siteconf says is said as it is written, whatever the locale
# and whatever catalogs are installed (here, and in what it runs).
$ENV{LANGUAGE} = 'C';

# Resolve while loading, before a test changes to its temporary directory.
my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..', '..'));

sub project_root { $root }

sub script_path
{
	my $script = File::Spec->catfile($root, 'blib', 'script', 'siteconf');
	-f $script or Test::More::plan(skip_all =>
		'not built: perl Makefile.PL && make, in siteconf/ and genlib/');
	$script;
}

# Call before chdir so child processes can use the same modules as the test.
sub perl5lib
{
	join ':', map { abs_path($_) } grep { defined && !ref && -d } @INC;
}

1;
