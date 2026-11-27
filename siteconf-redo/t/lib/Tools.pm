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
our @EXPORT_OK = qw( which describe redo_cmd ifchange_cmd redo_bin redo_sh sh_runs shq );

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
# redo-ifchange, and put it first in $PATH.
#
# $REDO_IFCHANGE says which redo-ifchange, and we take it as it is.
# Without it, redo-ifchange is the one in redo's directory (as it was
# found), or else in the directory of the file redo links to, or else
# the first in $PATH; but only if it is of the same redo, as one of
# them says (see _together).  If links cannot be made, the directories
# of redo and redo-ifchange go first in $PATH, and they must be the
# first found there.
#
# Returns the redo to run (named redo, as it is in the directory of
# links), and the directory; or nothing, and why.
sub redo_bin
{
	my $redo = _find(redo_cmd());
	defined $redo or return (undef, sprintf "%s: not found", redo_cmd());
	$redo = File::Spec->rel2abs($redo);
	my $ifchange;
	if ($ENV{REDO_IFCHANGE}) {
		$ifchange = _find(ifchange_cmd());
		defined $ifchange or return (undef, sprintf "%s: not found", ifchange_cmd());
	} else {
		my $real = abs_path($redo);
		($ifchange) = grep { -f && -x _ } "@{[ dirname($redo) ]}/redo-ifchange",
			defined $real ? "@{[ dirname($real) ]}/redo-ifchange" : ();
		if (!defined $ifchange) {
			$ifchange = _find('redo-ifchange');
			defined $ifchange or return (undef, "redo-ifchange: not found");
			_together($redo, $ifchange) or return (undef, sprintf
				"%s is not of the same redo as %s (set REDO_IFCHANGE?)",
				$ifchange, $redo);
		}
	}
	$ifchange = File::Spec->rel2abs($ifchange);
	my $bin = tempdir(CLEANUP => 1);
	if (eval { symlink($redo, "$bin/redo")
		&& symlink($ifchange, "$bin/redo-ifchange") }) {
		$ENV{PATH} = join ':', $bin, File::Spec->path;
		return ("$bin/redo", $bin);
	}
	my %seen;
	my $was = $ENV{PATH};
	$ENV{PATH} = join ':', grep { !$seen{$_}++ }
		dirname($redo), dirname($ifchange), File::Spec->path;
	my ($r, $i) = (_find('redo'), _find('redo-ifchange'));
	return ($redo, dirname($redo))
		if defined $r && $r eq $redo && defined $i && $i eq $ifchange;
	$ENV{PATH} = $was;
	(undef, "no links, and \$PATH would not find $redo and $ifchange");
}

# Whether redo-ifchange belongs with redo: in the same directory (as
# found, so a directory such as /opt/homebrew/bin that links both is
# trusted), or links into the same directory, or is the same file (a
# program that does what its argv[0] says).
sub _together
{
	my ($redo, $ifchange) = @_;
	dirname(File::Spec->rel2abs($redo)) eq dirname(File::Spec->rel2abs($ifchange))
		and return 1;
	my ($r, $i) = (abs_path($redo), abs_path($ifchange));
	defined $r && defined $i or return 0;
	$r eq $i || dirname($r) eq dirname($i);
}

# What $REDO_SH says (for -Ssh, and the #! of a .do), or undef.  Termux
# has no /bin/sh: REDO_SH=/data/data/com.termux/files/usr/bin/sh
sub redo_sh { defined $ENV{REDO_SH} && length $ENV{REDO_SH} ? $ENV{REDO_SH} : undef }

# Whether `#!$sh' runs: as the kernel runs it, the first word is the
# program, and the rest is one argument; then -c 'exit 0'.  (Not which:
# on Termux, termux-exec makes exec find /usr/bin/env, but not stat.)
sub sh_runs
{
	my ($prog, $arg) = split ' ', $_[0], 2;
	defined $prog or return 0;
	open my $err, '>&', \*STDERR or return 0;
	open STDERR, '>', File::Spec->devnull or return 0;
	my $status = system { $prog; } $prog, defined $arg ? $arg : (), '-c', 'exit 0';
	open STDERR, '>&', $err;
	$status == 0;
}

# One word for sh
sub shq { (my $s = shift) =~ s/'/'\\''/g; "'$s'"; }

1;
