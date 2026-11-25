package Tools;
#
# t/lib/Tools.pm - the programs that the tests run: which one
# ($GO_TASK may say), and where it is (t/00-load.t says).
#
use strict;
use warnings;

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( which describe task_check task_cmd task_works );

use Cwd qw( abs_path );
use File::Spec;
use File::Temp qw( tempdir );
use Test::Builder;

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

# What $GO_TASK says; or else `go-task' (as Arch Linux names it), if it
# is in $PATH; or else `task'.  (This is Go Task, not Taskwarrior.)
sub task_cmd { $ENV{GO_TASK} || (which('go-task') ? 'go-task' : 'task') }

# Whether $cmd is Go Task: in an empty directory, it runs a Taskfile
# whose task touches a file named by a variable, and the file is there.
# Taskwarrior is also `task'; for it, TASKRC and TASKDATA are in the
# empty directory, and stdin is /dev/null, so that it cannot read or
# change the user's tasks, or ask to make a .taskrc.
sub task_works
{
	my ($cmd) = @_;
	my $dir = tempdir(CLEANUP => 1);
	open my $fh, '>', "$dir/Taskfile.yml" or die "Taskfile.yml: $!";
	print $fh <<\taskfile;
version: '3'

vars:
  NAME: probe.ok

tasks:
  default:
    cmds:
      - touch "{{.NAME}}"
    silent: true
taskfile
	close $fh or die "Taskfile.yml: $!";
	(my $q = $dir) =~ s/'/'\\''/g;
	local $ENV{TASKRC} = "$dir/taskrc";
	local $ENV{TASKDATA} = $dir;
	system("cd '$q' && $cmd </dev/null >/dev/null 2>&1");
	$? == 0 && -f "$dir/probe.ok";
}

sub task_check
{
	my ($cmd) = @_;
	return 1 if task_works($cmd);
	my $tb = Test::Builder->new;
	my $itried = $cmd eq 'task' ? "" : " (tried: $cmd)";
	$tb->plan(skip_all => ($? == 0 ? "no task" : "wrong task") . $itried);
}

1;
