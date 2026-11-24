package Tools;
#
# t/lib/Tools.pm - the programs that the tests run: which one ($REDO
# may say), and where it is (t/00-load.t says).
#
use strict;
use warnings;

use Cwd qw( abs_path );
use File::Spec;

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( which describe redo_cmd );

# Where a command (its first word) is: there, if it has a `/'; or else
# the first in $PATH.  undef if it is nowhere.
sub which
{
	my ($cmd) = @_;
	my ($word) = split ' ', $cmd;
	defined $word or return undef;
	return -f $word && -x _ ? $word : undef if $word =~ m!/!;
	for my $dir (File::Spec->path) {
		my $path = File::Spec->catfile(length $dir ? $dir : '.', $word);
		return $path if -f $path && -x _;
	}
	undef;
}

# A line of diag: where the command is (and what file, if that is a
# link), and the first line of what `cmd @version' says, if asked
sub describe
{
	my ($label, $cmd, @version) = @_;
	defined $cmd or return "$label: none";
	my $path = which($cmd);
	defined $path or return "$label: $cmd: not found";
	my $line = "$label: $path";
	my $real = abs_path($path);
	$line .= " -> $real" if -l $path && defined $real;
	if (@version) {
		my ($v) = split /\n/, `$cmd @version 2>/dev/null`;
		$line .= " ($v)" if defined $v && length $v;
	}
	$line;
}

# `redo', or what $REDO says.  (What a .do runs, as redo-ifchange, is
# found in $PATH, whatever $REDO is.)
sub redo_cmd { $ENV{REDO} || 'redo' }

1;
