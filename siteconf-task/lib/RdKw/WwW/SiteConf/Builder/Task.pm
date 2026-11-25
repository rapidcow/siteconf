package RdKw::WwW::SiteConf::Builder::Task;

use 5.008;
use strict;
use warnings;

use version;
use Encode ();
use RdKw::WwW::SiteConf 0.03_00 ();

# (released with siteconf, at its version)
our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

RdKw::WwW::SiteConf::Builder::Task - Taskfile.yml backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(task));   # siteconf -g -G task

=head1 DESCRIPTION

The generator C<task> of L<RdKw::WwW::SiteConf/generate>.  It writes
F<Taskfile.yml> for Task (L<https://taskfile.dev/>), version 3 of the
schema.  Run C<task> in the build directory to build the first goal,
or C<task> I<goal> for another one.  We have tested it with Task 3.54.

Each goal is a task that has the tasks of its files as C<deps>.  The
first goal also has the alias C<default>, which a bare C<task> runs.
Each file is a task called C<file:>I<path>, with:

=over

=item *

C<deps>: the tasks of the files it needs that are made here, and that
of the marker of its directory.  Task runs
the C<deps> of a task in parallel.  C<run: once> makes a task run
at most once in each call of C<task>.

=item *

C<status>: C<[ -e> I<file> C<]>, and C<[ !> I<need> C<-nt> I<file>
C<]> for each file it needs but the marker.  Task runs the task unless
all of them succeed: if the file is not there, or something it needs is
newer, as make decides.  A needed file that does not exist does not
make the task run.  Task runs these with its own shell after the
C<deps>.  Its C<[> reads C<[ ! -n -nt x ]> as some other test, so
a name that does not begin with a letter, a digit, C<_>, C<.> or C</>
is written C<./>I<name> there.  Task's
C<sources> and C<generates> are not used: with them, Task 3.54 took
a file whose recipe had failed to be up to date on the next run, and
did not make F<out/a-b> again after its source changed, when the task
of F<out/a.b> was checked first.

=item *

C<cmds>: the recipe.

=back

Each directory has a marker (C<.ok>, as C<-Se> says): a task
C<file:>I<marker>, with the task of the marker of its parent as C<deps>,
C<[ -e> I<marker> C<]> as C<status>, and C<[ -d> I<dir> C<] || mkdir -->
I<dir> and C<touch --> I<marker> as C<cmds>.  With C<-Smkpath=1> there
are no markers, and the C<cmds> of a file begin with C<mkdir -p -->
I<dir>.

Recipes are written as for L<make(1)>, and this undoes make's reading of
them: each line is a command of its own, a backslash joins lines,
a leading C<@> is dropped, and a leading C<-> is C<ignore_error: true>.
Each line is a command C</bin/sh -c '>I<line>C<'>, which Task echoes
and runs, so each line runs in a new shell, as in make.  Task's own
shell interpreter (from L<mvdan.cc/sh|https://github.com/mvdan/sh>)
runs only that C</bin/sh>, the C<mkdir>, C<touch> and C<rm>, and the
C<[>: it does not
take C<cd -->, which siteconf's recipes use.  Task reads C<{{> as the
start of a Go template, so C<{{> in a command is written C<{{"{{"}}>.

The name of a goal or a cleaning rule is the task name if Task can
take it as an argument.  A name with C<*> (a wildcard to Task), C<=>
(an assignment), C<{>, C<}>, C<:>, C<%> or a C<-> in front, and a goal
C<default> that is not the first goal, is written C<goal:> and the name
with each such character as C<%> and two hex digits.  C<a=b> is then
C<goal:a%3db>.  The command that C<siteconf -g> prints spells it the same
way.

F<Taskfile.yml> is UTF-8, and Task reads it as UTF-8.  A file name is
spelled as the file system spells it (L<RdKw::I18N::CodeSets/filesys>),
and a goal as an argument is (L<RdKw::I18N::CodeSets/argv>).  Either
spelling must be valid UTF-8, or it is an error.  A line break in
a name in a recipe is an error, as it is to C<-G make>.

=head2 Options

C<clean>, C<purge>, C<arg_max>, C<mkpath>, C<cmd_mkdir>, C<cmd_mkdir_p>,
C<cmd_rm_f> and C<cmd_touch>, as for
L<RdKw::WwW::SiteConf::Builder::Make/Options>.  A cleaning rule is a task
that runs C<rm -f --> on the files.  C<-Sarg_max> limits the bytes of
file names on one C<rm>, with no cap for C<-Sarg_max=auto>: Task runs
C<rm> with the names as separate arguments.

A command (C<-Scmd_>I<name>) is run by Task's own shell, as it is: a
C<@>, C<-> or C<+> in front of it is not for Task.  The marker is made
with C<touch --> by default.  A C<{{> in a command is escaped, as in
a recipe.  A command must be UTF-8 as the file system spells it, as
a name must.

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

C<clean>, C<purge>, C<arg_max>, C<mkpath> and the C<cmd_> options.

=item B<default_output>

F<Taskfile.yml>.

=item B<emit> I<plan>, I<file>

F<Taskfile.yml>, as C<[ >I<file>C<, >I<bytes>C< ]>.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

C<task>, with C<-t> I<builddir>C</>I<file> if I<file> is defined (or
else C<-d> I<builddir> unless it is C<.>), and I<goal> if it is.

=back

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

sub options { qw( clean purge arg_max mkpath cmd_mkdir cmd_mkdir_p cmd_rm_f cmd_touch ) }

sub default_output { q(Taskfile.yml) }

sub emit { my ($class, $plan, $file) = @_; [ $file, $class->_text($plan) ] }

sub build_command
{
	my ($class, $prog, $B, $file, $goal) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	($prog,
		(defined $file ? (q(-t), $q->($B eq q(.) ? $file : "$B/$file"))
			: $B eq q(.) ? () : (q(-d), $q->($B))),
		(defined $goal ? $q->(_task_name($goal, 1)) : ()));
}

# Bytes as characters, if they are UTF-8; else undef
sub _utf8
{
	my ($bytes) = @_;
	my $s = eval { Encode::decode('UTF-8', $bytes, Encode::FB_CROAK) };
	$s;
}

# A name as Task reads it: the bytes that the file system (or argv)
# spells, which must be UTF-8 since the file is
sub _name
{
	my ($s, $argv) = @_;
	my $b = $argv ? RdKw::WwW::SiteConf::argv_text($s)
		: RdKw::WwW::SiteConf::fs_text($s);
	my $c = _utf8($b);
	defined $c or die _status 0, tagmsg(E => diag(__(
		"task cannot name %q: it is not UTF-8 in the encoding of this"
		. " locale, and Taskfile.yml is UTF-8"), $s));
	$c;
}

# What Task may take as the name of a goal or a rule (see DESCRIPTION),
# or `goal:' and the name with %XX escapes.  The first goal is the
# `default' alias, so another goal may not be called that.
sub _task_name
{
	my ($s, $first) = @_;
	return $s unless $s =~ /[*=:{}%]|\A-/ || !$first && $s eq 'default';
	$s =~ s/([*=:{}%]|\A-)/sprintf '%%%02x', ord $1/ge;
	"goal:$s";
}

# The task of a file: never typed, but named in `deps', which Task
# expands as a template and matches as a wildcard
sub _file_task
{
	(my $s = $_[0]) =~ s/([*=:{}%\x00-\x1f\x7f])/sprintf '%%%02x', ord $1/ge;
	"file:$s";
}

# A command, with what Task would read as a template escaped
sub _template { (my $s = $_[0]) =~ s/\{\{/{{"{{"}}/g; $s }

# A shell word for a name
sub _quote { RdKw::WwW::SiteConf::shell_quote($_[0]) }

# A shell word for a name as an operand of `[': Task's `[' reads
# `[ ! -n -nt x ]' and `[ ! ! -nt x ]' as other tests, so a name that
# could be an operator is ./name
sub _operand { _quote($_[0] =~ m{\A[^A-Za-z0-9_./]} ? "./$_[0]" : $_[0]) }

# A YAML scalar: always double-quoted, so that none of it reads as
# anything but a string (a plain NULL is null to Task, and crashes it)
sub _yaml
{
	my ($s) = @_;
	$s =~ s/([\\"])/\\$1/g;
	$s =~ s/([\x00-\x1F\x7F-\x9F\x{2028}\x{2029}\x{FEFF}])/sprintf '\\u%04X', ord $1/ge;
	qq("$s");
}

# A command of -S (see RdKw::WwW::SiteConf/command), as characters
sub _cmd
{
	my ($opt, $name, $default) = @_;
	my $c = _utf8(RdKw::WwW::SiteConf::command($opt, $name, $default));
	defined $c or die _status 0, tagmsg(E => diag(__(
		# HEY!  %s is the option, as -Scmd_rm_f
		"%s: task cannot run it: it is not UTF-8 in the encoding of this"
		. " locale, and Taskfile.yml is UTF-8"), "-S$name"));
	$c;
}

sub _list { '[' . join(', ', map { _yaml($_) } @_) . ']' }

sub _text
{
	my ($class, $plan) = @_;
	my @goal = @{ $plan->{goals} };
	my $opt = $plan->{opt};
	my %marker = map { $_->{marker} => 1 } @{ $plan->{dirs} };
	# (with -Smkpath=1, each task makes its directory, and there are no
	# markers to make)
	my $mkpath = $opt && $opt->{mkpath} ? 1 : 0;
	my @dirs = $mkpath ? () : @{ $plan->{dirs} };
	my %made = map { $_ => 1 } (map { $plan->{node}{$_}{bpath} } @{ $plan->{order} }),
		map { $_->{marker} } @dirs;
	my %cmd = (
		mkdir => _cmd($opt, cmd_mkdir => q(mkdir --)),
		mkdir_p => _cmd($opt, cmd_mkdir_p => q(mkdir -p --)),
		rm => _cmd($opt, cmd_rm_f => q(rm -f --)),
		touch => _cmd($opt, cmd_touch => q(touch --)),
	);

	my $out = "#\n# Taskfile.yml!\n" . RdKw::WwW::SiteConf::header_comment($plan) . "#\n";
	utf8::upgrade($out);
	$out .= qq(version: "3"\nrun: "once"\n\ntasks:);
	my $tasks = '';

	my $first = 1;
	for my $goal (@goal) {
		my $name = _name($goal->{name}, 1);
		$tasks .= "\n  " . _yaml(_task_name($name, $first)) . ":\n";
		$tasks .= qq(    aliases: ["default"]\n) if $first && $name ne 'default';
		$tasks .= "    deps: " . _list(map { _file_task(_name($plan->{node}{$_}{bpath})) }
			@{ $goal->{files} }) . "\n";
		$first = 0;
	}

	my $max = RdKw::WwW::SiteConf::arg_max($opt);
	for my $rule (@{ $plan->{clean} }) {
		$tasks .= "\n  " . _yaml(_task_name(_name($rule->{name}, 1))) . ":\n    cmds:\n";
		# So many files go on several lines (0: one line)
		my @file = map { _quote(_name($_)) } @{ $rule->{files} };
		while (@file) {
			my $line = shift @file;
			$line .= ' ' . shift @file
				while @file and (!$max || length($line) + 1 + length($file[0]) <= $max);
			$tasks .= "      - " . _yaml(_template("$cmd{rm} $line")) . "\n";
		}
	}

	# A marker is there once its directory is
	for my $dir (@dirs) {
		my $m = _name($dir->{marker});
		my $d = _quote(_name($dir->{dir}));
		$tasks .= "\n  " . _yaml(_file_task($m)) . ":\n";
		$tasks .= "    deps: " . _list(map { _file_task(_name($_)) } @{ $dir->{deps} }) . "\n"
			if @{ $dir->{deps} };
		$tasks .= "    status: " . _list(_template("[ -e " . _operand($m) . " ]")) . "\n    cmds:\n";
		$tasks .= "      - " . _yaml(_template($_)) . "\n"
			for "[ -d $d ] || $cmd{mkdir} $d", "$cmd{touch} " . _quote($m);
	}

	for my $file (@{ $plan->{order} }) {
		my $node = $plan->{node}{$file};
		my $target = _name($node->{bpath});
		my @need = grep { !$marker{$_} } @{ $node->{deps} };
		# (a marker has only to be there: it is a dep, and never newer)
		my @mark = grep { $marker{$_} && $made{$_} } @{ $node->{deps} };
		my $recipe = RdKw::WwW::SiteConf::recipe_bytes($node->{recipe},
			line_break => __(
				# HEY!  the second %s is the value, which has a line break
				"%s: task cannot spell a line break in %q (it ends a command)"));
		my @cmd = RdKw::WwW::SiteConf::recipe_commands($recipe);
		@cmd or die _status 0, tagmsg(E => diag(__("%#q: no recipe to make it"), $file));

		$tasks .= "\n  " . _yaml(_file_task($target)) . ":\n";
		my @dep = map { _file_task(_name($_)) } grep { $made{$_} } @need, @mark;
		$tasks .= "    deps: " . _list(@dep) . "\n" if @dep;
		# Up to date if it is there, and nothing it needs is newer
		my $t = _operand($target);
		$tasks .= "    status: " . _list(map { _template($_) } "[ -e $t ]",
			map { "[ ! " . _operand(_name($_)) . " -nt $t ]" } @need) . "\n    cmds:\n";
		my ($dir) = $target =~ m{\A(.*)/};
		$tasks .= "      - " . _yaml(_template("$cmd{mkdir_p} " . _quote($dir))) . "\n"
			if $mkpath and defined $dir;
		for (@cmd) {
			my ($ignore, $line) = @$_;
			# ($$ is the shell's $, in make's words)
			$line =~ s/\$\$/\$/g;
			my $text = _utf8($line);
			defined $text or die _status 0, tagmsg(E => diag(__(
				"%#q: task cannot run its recipe: it is not UTF-8, and"
				. " Taskfile.yml is UTF-8"), $file));
			# (Task's own shell does not take `cd --')
			$text = _yaml(_template("/bin/sh -c " . _quote($text)));
			$tasks .= $ignore ? "      - cmd: $text\n        ignore_error: true\n"
				: "      - $text\n";
		}
	}
	$out .= length $tasks ? "$tasks" : " {}\n";
	utf8::encode($out);
	$out;
}

1;

=head1 SEE ALSO

L<RdKw::WwW::SiteConf::Builder>, L<RdKw::WwW::SiteConf/generate>.

=cut
