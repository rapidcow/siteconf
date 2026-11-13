package TestPaths;

use strict;
use warnings;
use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Spec;
use Test::More ();
use parent qw( Exporter );
our @EXPORT_OK = qw( project_root script_path perl5lib fs_surprise );

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

# Does the file system (of a directory; the current one if not given)
# take these bytes for a name as they are, as we expect of it?  That
# is: a directory under a missing one of that name is ENOENT (and not
# EILSEQ, EINVAL, or whatever else it has to say about the name); one
# of that name can be made, is listed under those very bytes (not
# normalized, nor folded), and can be removed again.  Returns what was
# surprising, or undef if nothing was; leaves nothing behind.
#
# This is about the file system, not the locale: pin filesys:UTF-8
# (or whatever the bytes are in), and ask this before a test that
# hands such a name to the file system.
sub fs_surprise
{
	my ($name, $dir) = @_;
	defined $dir or $dir = '.';
	my $path = "$dir/$name";
	return 'the name is already taken' if -e $path || -l $path;
	if (mkdir "$path/x") {
		rmdir "$path/x"; rmdir $path;
		return 'mkdir under a missing directory worked';
	}
	return "mkdir under a missing directory: $! (expected ENOENT)"
		unless $!{ENOENT};
	return 'a failed mkdir made something' if -e $path || -l $path;
	mkdir $path or return "mkdir: $!";
	my @found;
	if (opendir my $dh, $dir) {
		@found = grep { $_ eq $name } readdir $dh;
		closedir $dh;
	}
	rmdir $path or return "rmdir: $!";
	return 'the name is not listed as it was given' unless @found == 1;
	return 'rmdir left something' if -e $path || -l $path;
	undef;
}

1;
