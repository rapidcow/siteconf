package Tools;
#
# t/lib/Tools.pm - the programs that the tests run: which ones ($REDO
# and $REDO_IFCHANGE may say), and where they are (t/00-load.t says);
# and what runs a .do ($REDO_SH may say).
#
use strict;
use warnings;

use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Spec;
use File::Temp qw( tempdir );

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( which describe redo_cmd ifchange_cmd redo_bin redo_sh shq );

# Where a command (its first word) is: there, if it has a `/'; or else
# the first in $PATH.  undef if it is nowhere.
sub which
{
	my ($word) = split ' ', $_[0];
	defined $word ? _find($word) : undef;
}

# Where a program is, as which says, but all of it is the name
sub _find
{
	my ($word) = @_;
	length $word or return undef;
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

# `redo-ifchange', or what $REDO_IFCHANGE says.  (It may be the same
# program as $REDO, which does what its argv[0] says, as goredo does.)
sub ifchange_cmd { $ENV{REDO_IFCHANGE} || 'redo-ifchange' }

# A .do runs redo-ifchange, which it finds in $PATH.  So that it is the
# one we mean, we make a directory of two links, redo and
# redo-ifchange, and put it first in $PATH.  Without $REDO_IFCHANGE,
# redo-ifchange is the one next to redo, or else the first in $PATH.
# If links cannot be made, redo's own directory goes first in $PATH,
# and redo-ifchange must be in it.
#
# Returns the redo to run (in the directory of links, so that it is
# named redo), and the directory; or nothing, and why.
sub redo_bin
{
	my $redo = _find(redo_cmd());
	defined $redo or return (undef, sprintf "%s: not found", redo_cmd());
	$redo = File::Spec->rel2abs($redo);
	my $here = dirname($redo);
	my $ifchange = $ENV{REDO_IFCHANGE} ? _find(ifchange_cmd())
		: -f "$here/redo-ifchange" && -x _ ? "$here/redo-ifchange"
		: _find(ifchange_cmd());
	defined $ifchange or return (undef, sprintf "%s: not found", ifchange_cmd());
	$ifchange = File::Spec->rel2abs($ifchange);
	my $bin = tempdir(CLEANUP => 1);
	my $dir;
	if (eval { symlink($redo, "$bin/redo")
		&& symlink($ifchange, "$bin/redo-ifchange") }) {
		$dir = $bin;
	} else {
		-f "$here/redo-ifchange" && -x _
			&& File::Spec->rel2abs("$here/redo-ifchange") eq $ifchange
			or return (undef, "no links, and redo-ifchange is not in $here");
		$dir = $here;
	}
	$ENV{PATH} = join ':', $dir, grep { $_ ne $dir } File::Spec->path;
	("$dir/redo", $dir);
}

# What $REDO_SH says (for -Ssh, and the #! of a .do), or undef.  Termux
# has no /bin/sh: REDO_SH=/data/data/com.termux/files/usr/bin/sh
sub redo_sh { defined $ENV{REDO_SH} && length $ENV{REDO_SH} ? $ENV{REDO_SH} : undef }

# One word for sh
sub shq { (my $s = shift) =~ s/'/'\\''/g; "'$s'" }

1;
