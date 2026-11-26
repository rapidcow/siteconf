package Tools;
#
# t/lib/Tools.pm - the programs that the tests run: which one ($REDO
# may say), and where it is (t/00-load.t says); and what runs a .do
# ($REDO_SH may say).
#
use strict;
use warnings;

use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Spec;

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( which describe redo_cmd redo_path redo_sh shq );

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

# `redo', or what $REDO says.  $REDO goes out of the environment: to
# apenwarr's redo, it says that we are in a .do (it sets it there),
# and redo at the top would not check what is out of date.
my $REDO = delete $ENV{REDO};
sub redo_cmd { $REDO || 'redo' }

# A .do runs redo-ifchange, which it finds in $PATH.  So that it is
# the one of the same redo, put where redo is first in $PATH.  Returns
# that directory, or undef (and $PATH as it was) if redo is nowhere.
sub redo_path
{
	my $path = which(redo_cmd());
	defined $path or return undef;
	my $dir = dirname($path);
	$ENV{PATH} = join ':', $dir, grep { $_ ne $dir } File::Spec->path;
	$dir;
}

# What $REDO_SH says (for -Ssh, and the #! of a .do), or undef.  Termux
# has no /bin/sh: REDO_SH=/data/data/com.termux/files/usr/bin/sh
sub redo_sh { defined $ENV{REDO_SH} && length $ENV{REDO_SH} ? $ENV{REDO_SH} : undef }

# One word for sh
sub shq { (my $s = shift) =~ s/'/'\\''/g; "'$s'" }

1;
