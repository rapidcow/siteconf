package RdKw::WwW::SiteConf::Builder::Redo;

use 5.008;
use strict;
use warnings;

use version;
use RdKw::WwW::SiteConf 0.03_00 ();

# (released with siteconf, at its version)
our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

RdKw::WwW::SiteConf::Builder::Redo - redo backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(redo));   # siteconf -g -G redo

=head1 DESCRIPTION

The generator C<redo> of L<RdKw::WwW::SiteConf/generate>.  It writes a
F<.do> file for each target, next to the target (F<site/index.html.do>
for F<site/index.html>, in the build directory), and one for each goal
in the build directory, I<goal>F<.do> (with the directories its name
says: F<demo/index.do> for C<demo/index>).  The default goal (C<-t ,>,
C<-t ,goal>; see C<-t> of L<siteconf(1)>) is F<all.do> instead, so
that C<redo> alone makes it, and is I<goal>F<.do> too only if it is a
goal of its own as well; so if there is a default goal, no goal of its
own may be called C<all>.  C<-o> I<name>F<.do> names that file instead
(and then a goal may be called C<all>), and C<-o /dev/null> writes none.
A file of any of those names that is already there is overwritten.  So
the output tree holds the F<.do> files too.

The header of a F<.do> file says how C<siteconf -g> was run, but for
the goals: a goal's says only how it was selected (C<-t goal>, or
C<-t WANT:goal>; F<all.do>, C<-t ,goal> or C<-t ,>), and a target's no
goal at all.
  So a F<.do> file is
the same whatever other goals are asked for, and is left alone if what
it says has not changed.

A goal's F<.do> file runs C<redo-ifchange> on the files of the goal.
A target's F<.do> file goes to the build directory (a F<.do> file runs
in its own directory), runs C<redo-ifchange> on what the target
needs, and then runs the recipe from F<Makefile.in>, as make would
run it from the build directory.  A F<.do> may not write the target
itself: it writes C<$3>, and redo makes the target of that.  So in the
recipe, C<${@}> and C<${@:Q}> (and C<${.TARGET}>) name C<$3>: they are
C<$O> and C<"$O">, which is the target's directory, as C<${@}> says it,
and then the last part of the name of C<$3>, which is in that
directory.  Its name
is redo's, and need not end as the target's does: a program that
looks at the end of a name for the format to write (as ImageMagick
does) should be told the format (C<png:${b}/${@}>).  With any other
modifier, as C<${@:R}> or C<${@:T}>, C<${@}> is the target's own name,
as it is in the prerequisites.  A recipe that does not say C<${@}>
that way writes the target, which is then moved to C<$3>.
C<-Sliteral_target=1> says the target's own name everywhere, and moves
the target (see L</Options>).  What the recipe writes to the standard
output goes to the standard error, so that redo does not take it for
the target.

Recipes are written as for L<make(1)>, so this undoes make's reading
of them: each line is a command of its own, in a subshell of its own
(so a C<cd> does not carry over, as in make), and the F<.do> file stops
at the first that fails (C<set -e>); a backslash joins lines, a leading
C<@> is dropped, a leading C<-> ignores failure, and a C<$$> is a C<$>.
Directory markers are not made: the directory of a target is made when
its F<.do> file is written.

A F<.do> file keeps names in shell variables: the build directory,
seen from where the F<.do> runs, in C<$d>; and what C<${@}> says
(above), in C<$O>, or, if the F<.do> moves the target to C<$3>, the
absolute name of C<$3>, in C<$o>.  The recipes run in the same shell
(in subshells), so they see these too.  C<-Sarg_prefix> puts a prefix
on the names (see L</Options>).

A cleaning rule of C<-Sclean> or C<-Spurge> (named as with
L<RdKw::WwW::SiteConf::Builder::Make/Options>) is I<name>F<.do> in the
build directory, which goes to the build directory and removes the
files with C<rm -f>.  So C<redo clean> removes them, and a later C<redo>
makes them again.  A cleaning rule is named as a goal is, and may not
have the name of the default goal's F<.do> (F<all.do>, or as C<-o>
says).  Nor may it be C<default> or C<default.>I<ext>, in any
directory: redo runs F<default.do> and F<default.>I<ext>F<.do> for a
name that has no F<.do> of its own.  The F<.do> of a target or a goal
does not say C<-Sclean>, C<-Spurge> or C<-Sarg_max> in its header, so
it does not change with them, and redo does not make the target
again.

A target, and a goal, is named twice: as a file (its F<.do> file), and
as an argument (to C<redo>, or C<redo-ifchange>).  So it is an error if
the encoding of arguments (L<RdKw::I18N::CodeSets/argv>) spells it
differently from the file system (L<RdKw::I18N::CodeSets/filesys>): the
bytes, and not the encodings, so that an ASCII name is all right with
UTF-8 file names and ASCII arguments.  It is an error, too, if a goal or
a cleaning rule has the name of a file that a target makes or needs
(redo would take the goal for that file, and not make it), if a F<.do>
file would have the name of such a file, and if a target, a goal or a
cleaning rule is out of the build directory (where its F<.do> file could
not find the build directory again: a C<..> in its name, say).  The name
of a directory is all right.  Any other name is quoted for the shell, a
line break included.

Tested with apenwarr's redo, 0.42d.

=head2 Options

Those of C<-S> of C<siteconf -g>:

=over

=item C<arg_prefix>

The prefix of the shell variables of a F<.do> file: C<-Sarg_prefix=sc_>
names them C<$sc_d>, C<$sc_O> and C<$sc_o>.  The default is no prefix
(C<$d>, C<$O> and C<$o>), and so is C<-Sarg_prefix> with no value, or an empty one.  A
prefix is a letter or C<_>, and then letters, digits and C<_>.  Choose
one that the recipes do not use.

=item C<clean>, C<purge>

As with L<RdKw::WwW::SiteConf::Builder::Make/Options>: a F<.do> file for
each cleaning rule.

=item C<arg_max>

How many bytes of file names an C<rm> line of a cleaning rule may
have, as with L<RdKw::WwW::SiteConf::Builder::Make/Options>.  The F<.do>
runs C<rm> with each name an argument of its own, so
C<-Sarg_max=auto> is an eighth of C<sysconf(_SC_ARG_MAX)>, with no other
limit.  See L<RdKw::WwW::SiteConf/arg_max>.

=item C<cmd_rm_f>, C<cmd_mv_f>

The command that removes the files of a cleaning rule (C<rm -f -->
by default), and the one that moves the target to C<$3> (C<mv -f -->
by default), for a recipe that writes the target (one that does not
say C<${@}>, or with L</literal_target>).  The names follow it as words
of their own.
It goes in the F<.do> as it is: C<-Scmd_rm_f='rm -fv --'>.
L<RdKw::WwW::SiteConf/command> says what it may be.

=item C<literal_target>

Without it, or with C<-Sliteral_target=0> or no value, C<${@}> in a
recipe names C<$3> (see L</DESCRIPTION>).  With
C<-Sliteral_target=1>, C<${@}> in a recipe is the target's own name,
which the recipe writes, and which is then moved to C<$3>.  The target
is then gone while the F<.do> runs, which not every redo allows: when what is made is the same
as before, goredo keeps the old target in place of C<$3>, and fails,
as it is not there.

=item C<sh>

The interpreter on the C<#!> line of every F<.do>: F</bin/sh> without
it, or with no value.  A redo may run a F<.do> as a program, and
a system may not have F</bin/sh> (Termux on Android has its shell in
F</data/data/com.termux/files/usr/bin/sh>), so
C<-Ssh=/data/data/com.termux/files/usr/bin/sh> names it.  It may be
several words, as C<-Ssh='/usr/bin/env sh'>; the kernel says how many
it takes.  Blanks at either end are dropped.  It is an error if nothing
is left, if a line feed is left in it, or if the file system cannot
spell it.

=back

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

L</arg_prefix>, C<clean>, C<purge>, L</arg_max>, C<cmd_rm_f>,
C<cmd_mv_f>, L</sh> and L</literal_target>.

=item B<recipe_target> I<options>

True, for C<${@}> in a recipe to name C<$3>; false with
L</literal_target>.

=item B<default_output>

F<all.do>: the file of the default goal, which C<-o> may name.

=item B<emit> I<plan>, I<file>

The F<.do> files, as C<[ >I<name>C<, >I<bytes>C< ]>; I<file> is that of
the default goal, or C<undef> for none.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>, I<plan>

C<( cd >I<builddir>C< && redo >I<name>C< )>, run from the build
directory as C<make -C> would be (and so with the database of redo
there); C<redo> I<name> if I<builddir> is C<.>.  I<name> is that of the
default goal's F<.do> (C<all>, or as C<-o> says), or if there is none,
the first goal of its own; or there is no I<name>.

=back

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

sub options { qw( arg_prefix clean purge arg_max cmd_rm_f cmd_mv_f sh literal_target ) }

# Whether ${@} in a recipe says $3 (see the DESCRIPTION, and _target):
# unless -Sliteral_target=1 says the target itself
sub recipe_target
{
	my ($class, $opt) = @_;
	!($opt && $opt->{literal_target});
}

# ${@} (or ${@:Q}, `quoted'), as $3: $O, which _preamble set to it.
# In make's words, as recipe_bytes says: a `$' for the shell is $$.
sub _target
{
	my ($v, $name, $quoted) = @_;
	$quoted ? qq("\$\$$v->{O}") : "\$\$$v->{O}";
}

sub default_output { q(all.do) }

sub emit
{
	my ($class, $plan, $default) = @_;
	# A goal's .do says how that goal was asked for (-t goal, or -t
	# WANT:goal), and no other; a target's says no goal.  So a .do is the
	# same file whatever else is asked for, and is then left alone.
	# (#! first: a redo may run a .do as a program, by execve)
	# The options of the cleaning rules are said only in their own .do
	# (a redo makes a target again if its .do changes)
	my $clean_opt = qr/\A-S(?:clean|purge|arg_max|cmd_rm_f)(?:=|\z)/;
	my $sh = _sh($plan->{opt});
	my $head = sub {
		my ($all, @goal) = @_;
		"#!$sh\n#\n# redo!\n" . RdKw::WwW::SiteConf::header_comment(
			{ %$plan, args => [ grep { $all || !/$clean_opt/ }
				_with_goals($plan->{args} || [], @goal) ] }) . "#\n";
	};
	my $target_head = $head->(0);
	my $v = _vars($plan->{opt});
	my $marker = qr{(?:\A|/)\Q$plan->{D}{e}\E\z};
	# (the commands of -S, as they are: a .do is a shell script)
	my $mv = RdKw::WwW::SiteConf::command($plan->{opt}, cmd_mv_f => q(mv -f --));
	my $rm = RdKw::WwW::SiteConf::command($plan->{opt}, cmd_rm_f => q(rm -f --));
	my @file;

	# What a goal may not be called: a file, which redo would take for
	# that file (a target, as the same .do file; or a source, which redo
	# does not make).  A directory is all right.
	my %taken;
	for my $file (@{ $plan->{order} }) {
		my $node = $plan->{node}{$file};
		$taken{$_} = 1 for $node->{bpath}, grep { !/$marker/ } @{ $node->{deps} };
	}

	for my $file (@{ $plan->{order} }) {
		my $node = $plan->{node}{$file};
		my $target = $node->{bpath};
		my @cmd = RdKw::WwW::SiteConf::recipe_commands(
			RdKw::WwW::SiteConf::recipe_bytes($node->{recipe},
				target => sub { _target($v, @_) },
				line_break => __(
					# HEY!  the second %s is the value, which has a line break
					"%s: redo cannot spell a line break in %q (it ends a command)")));
		@cmd or die _status 0, tagmsg(E => diag(__(
			"%#q: no recipe to make it (and redo has no way to make"
			. " nothing)"), $file));
		my $text = $target_head . _preamble($v, $target, 'out', $node->{recipe_target});
		my @need = grep { !/$marker/ } @{ $node->{deps} };
		$text .= _ifchange($v, @need);
		# (a redo may have made $3 already, as redo-c does, for us to
		# write into, with a mode of its own: the recipe makes its own)
		$text .= "rm -f -- \"\$3\"\n" if defined $node->{recipe_target};
		# (the recipe, from the build directory)
		$text .= _cd($v);
		for (@cmd) {
			my ($ignore, $line) = @$_;
			# (make's `$$' is the shell's `$')
			$line =~ s/\$\$/\$/g;
			$text .= $ignore ? "( $line ) || true\n" : "( $line )\n";
		}
		# (a recipe that said ${@} wrote $3; one that did not, the target)
		$text .= "$mv " . _word($target) . " \"\$$v->{o}\"\n"
			unless defined $node->{recipe_target};
		push @file, [ "$target.do", $text, 1 ];
	}

	# The default goal's .do (all.do, which a bare redo makes, unless -o
	# says otherwise; none for -o /dev/null): a name that redo looks for,
	# and of no file, and of no other goal
	# (and only if there is a default goal: -t goal has none)
	undef $default unless grep { defined $_->{default} } @{ $plan->{goals} };
	my $alias;
	if (defined $default) {
		($alias = $default) =~ s/\.do\z//
			or die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the name given with -o, for the default goal
				"redo cannot find %q: the name of a .do file ends in .do"),
				$default));
		length $alias && !$taken{$alias}
			or die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the name given with -o (as default.do)
				"redo cannot name the default goal %q: a file has that name"),
				$default));
	}

	# A goal of its own (-t goal) is goal.do; the default goal (-t , or
	# -t ,goal) is the alias, and is not goal.do unless it is a goal of
	# its own too (-t ,goal,goal)
	for my $goal (@{ $plan->{goals} }) {
		my $name = $goal->{name};
		my @files = map { $plan->{node}{$_}{bpath} } @{ $goal->{files} };
		my @do;
		if (defined $goal->{select}) {
			defined $alias && $name eq $alias
				and die _status 0, tagmsg(E => diag(__(
					# HEY!  the second %s is the .do file of the default goal
					"redo cannot name goal %q: %s is the default goal's"),
					$name, "$alias.do"));
			$taken{$name}
				and die _status 0, tagmsg(E => diag(__(
					# HEY!  %s is the name of a goal, which a .do file is named after
					"redo cannot name goal %q: a file has that name"), $name));
			push @do, [ $name, $goal->{select} ];
		}
		push @do, [ $alias, $goal->{default} ] if defined $goal->{default} && defined $alias;
		for (@do) {
			my ($do, $how) = @$_;
			my $text = $head->(0, $how) . _preamble($v, $do);
			$text .= _ifchange($v, @files);
			push @file, [ "$do.do", $text, 1 ];
		}
	}

	# A cleaning rule (-Sclean, -Spurge) is name.do, named as a goal is,
	# which removes its files from the build directory
	my $max = RdKw::WwW::SiteConf::arg_max($plan->{opt});
	for my $rule (@{ $plan->{clean} || [] }) {
		my $name = $rule->{name};
		defined $alias && $name eq $alias
			and die _status 0, tagmsg(E => diag(__(
				# HEY!  the second %s is the .do file of the default goal
				"redo cannot name cleaning rule %q: %s is the default goal's"),
				$name, "$alias.do"));
		$taken{$name}
			and die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the name of a cleaning rule (-Sclean), which a
				# .do file is named after
				"redo cannot name cleaning rule %q: a file has that name"), $name));
		# (default.do, default.EXT.do: redo would run it for other names,
		# in that directory and below)
		$name =~ m{(?:\A|/)default(?:\.[^/]*)?\z}
			and die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the name of a cleaning rule; default.do is what
				# redo runs for a name that has no .do of its own
				"redo cannot name cleaning rule %q: redo would run its .do"
				. " for other names"), $name));
		my $text = $head->(1) . _preamble($v, $name) . _cd($v);
		my @word = map { _word($_) } grep { !/$marker/ } @{ $rule->{files} };
		while (@word) {
			my $line = shift @word;
			$line .= ' ' . shift @word
				while @word and (!$max || length($line) + 1 + length($word[0]) <= $max);
			$text .= "$rm $line\n";
		}
		push @file, [ "$name.do", $text, 1 ];
	}

	# No .do may be written over a file that a target makes or needs, or
	# over another .do (goal `x' and target `x.do' would both be x.do)
	my %seen;
	for (@file) {
		my $do = $_->[0];
		$taken{$do} || $seen{$do}++
			and die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the name of a .do file to be written
				"redo cannot write %q: another file has that name"), $do));
	}
	@file;
}

sub build_command
{
	my ($class, $prog, $B, $file, $goal, $plan) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	# The default goal, by its alias (all, unless -o said otherwise), or
	# else the first goal of its own
	my ($first) = $plan ? @{ $plan->{goals} } : ();
	my $name = !$first ? $goal
		: defined $first->{default} && defined $plan->{output} ? ($plan->{output} =~ /\A(.*)\.do\z/s)[0]
		: (map { $_->{name} } grep { defined $_->{select} } @{ $plan->{goals} })[0];
	my @redo = ($prog, defined $name ? $q->($name) : ());
	# (in a subshell, so that the shell stays where it is)
	$B eq q(.) ? @redo : (q[(], q(cd), ($B =~ /\A-/ ? q(--) : ()), $q->($B), q(&&), @redo, q[)]);
}

# The interpreter of a .do (after its #!), as -Ssh says: /bin/sh by
# default (and with no value).  The blanks at either end go; what is
# left is one line, and the file system spells it.
sub _sh
{
	my ($opt) = @_;
	my $v = $opt ? $opt->{sh} : undef;
	defined $v or return q(/bin/sh);
	(my $s = $v) =~ s/\A[\t\n\cK\f\r ]+//;
	$s =~ s/[\t\n\cK\f\r ]+\z//;
	length $s
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is the option, as -Ssh
			"%s: no interpreter to run"), "-Ssh"));
	$s =~ /\n/
		and die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is the option, as -Ssh; #! is the first line of a script
			"%s: the line of #! cannot have a line break"), "-Ssh"));
	RdKw::WwW::SiteConf::fs_text($s, "-Ssh");
}

# The arguments of the command line, with these goals for its -t (in
# their place: before -S, if not where -t was)
sub _with_goals
{
	my ($args, @goal) = @_;
	my @arg = @$args;
	my @t = map { (q(-t), $_) } grep { defined } @goal;
	my @keep;
	# (-t is followed by its value; -S has its own glued on, as -Sname=value)
	while (@arg) {
		my $opt = shift @arg;
		if ($opt eq '-t') { shift @arg; push @keep, splice(@t); next }
		push @keep, splice(@t) if $opt =~ /\A-S/;
		push @keep, $opt;
	}
	(@keep, @t);
}

# The beginning of the .do file of `name' (relative to the build
# directory): stop at the first failure, keep where $3 is (if it is to
# be written, as `out'), find the build directory, and say what is said
# on the standard error.
#
# A redo may run a .do where the .do is (apenwarr's: $0 is `x.do'), or
# where redo was run (JdeBP's: $0 is `build/site/x.do').  JdeBP's redo
# also keeps each prerequisite by the name it was given, and looks for it
# from where redo was run; so the .do stays where it was run, and names
# what it needs by way of $d (`d' of _vars): the build directory, seen
# from there (empty, or ending in a `/'; not beginning with a `-').  $3
# is kept in $o (if `out'), as an absolute name, for the mv after the
# recipe's `cd'; or, given `at' (the target's name in its tree, as ${@}),
# $O is what ${@} says: its directory, then the last part of $3 (see
# _target), and there is no mv, nor $o.
sub _preamble
{
	my ($v, $name, $out, $at) = @_;
	my ($d, $o, $O) = @$v{qw( d o O )};
	_argv_is_fs($name);
	my @up = split m!/!, $name, -1;
	pop @up;
	grep { $_ eq '..' || $_ eq '.' || $_ eq '' } @up
		and die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is the name of a target, or a goal
			"redo cannot name %q: it is not in the build directory"), $name));
	my $text = "set -e\n";
	if (defined $at) {
		my ($dir) = $at =~ m!\A(.*/)!s;
		$text .= "$O=" . (defined $dir ? RdKw::WwW::SiteConf::shell_quote(
			RdKw::WwW::SiteConf::fs_text($dir)) : '') . "\${3##*/}\n";
	} elsif ($out) {
		$text .= "case \$3 in /*) $o=\$3 ;; *) $o=\${PWD}/\$3 ;; esac\n";
	}
	$text .= "case \$0 in -*/*) $d=./\${0%/*}/ ;; */*) $d=\${0%/*}/ ;; *) $d= ;; esac\n";
	$text .= "$d=\$$d" . ('../' x @up) . "\n" if @up;
	# Certain redo implementations redirect standard
	# output to $3 for writing, which is inconsistent
	# with an ordinary Make backend.  So we'll merge
	# standard output into standard error (which when
	# run in an interactive shell a would be the tty).
	$text . "exec >&2\n";
}

# What a .do needs, each from the build directory (see _preamble)
sub _ifchange
{
	my ($v, @need) = @_;
	@need or return '';
	"redo-ifchange " . join(' ', map { qq("\$$v->{d}") . _word($_) } @need) . "\n";
}

# To the build directory (see _preamble)
sub _cd { "cd -- \"\${$_[0]{d}:-.}\"\n" }

# The names of the shell variables (see _preamble): `d' and `o', after
# -Sarg_prefix (none by default; -Sarg_prefix alone, or empty, is none)
sub _vars
{
	my ($opt) = @_;
	my $p = $opt ? $opt->{arg_prefix} : undef;
	$p = '' unless defined $p;
	$p =~ /\A(?:[A-Za-z_][A-Za-z0-9_]*)?\z/
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is the option, as -Sarg_prefix=1x
			"%s: a prefix is a letter or `_', then letters, digits and `_'"),
			"-Sarg_prefix=$p"));
	+{ d => "${p}d", o => "${p}o", O => "${p}O" };
}

# A name, as one word of the shell, as the file system spells it (and
# not as an option: `./-x')
sub _word
{
	my ($s) = @_;
	$s = "./$s" if $s =~ /\A-/;
	RdKw::WwW::SiteConf::shell_quote(RdKw::WwW::SiteConf::fs_text($s));
}

# A name is typed (as an argument) and a .do file is found by it (as a
# file name): those must be the same bytes
sub _argv_is_fs
{
	my ($name) = @_;
	my $fs = RdKw::WwW::SiteConf::fs_text($name);
	# (the bytes, and not the encodings: an ASCII name is the same in
	# ASCII and UTF-8, and so is any name in the same encoding)
	my $argv = eval { RdKw::WwW::SiteConf::argv_text($name) };
	defined $argv
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is a name, which the encoding of arguments (what is
			# typed after redo) has no bytes for
			"redo cannot name %q: arguments cannot spell it"), $name));
	$fs eq $argv
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is a name; an argument (what is typed after redo) and the
			# file system spell it in different bytes, in their encodings
			"redo cannot name %q: arguments and file names spell it"
			. " differently"), $name));
	1;
}

1;

=head1 SEE ALSO

L<RdKw::WwW::SiteConf::Builder>, L<RdKw::WwW::SiteConf/generate>.

=cut
