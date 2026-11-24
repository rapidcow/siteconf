package RdKw::WwW::SiteConf::Backend::Redo;

use 5.008;
use strict;
use warnings;

use version;
use RdKw::WwW::SiteConf 0.03_00 ();

# (released with siteconf, at its version)
our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

RdKw::WwW::SiteConf::Backend::Redo - redo backend for siteconf

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
run it from the build directory.  The recipe writes the target itself,
which redo does not allow, so the target is then moved to C<$3>, the
file redo makes the target of.  What the recipe writes to the standard
output goes to the standard error, so that redo does not take it for
the target.

Recipes are written as for L<make(1)>, so this undoes make's reading
of them: each line is a command of its own, in a subshell of its own
(so a C<cd> does not carry over, as in make), and the F<.do> file stops
at the first that fails (C<set -e>); a backslash joins lines, a leading
C<@> is dropped, a leading C<-> ignores failure, and a C<$$> is a C<$>.
Directory markers are not made: the directory of a target is made when
its F<.do> file is written.  There is nothing to clean with: redo has
no such thing.

A target, and a goal, is named twice: as a file (its F<.do> file), and
as an argument (to C<redo>, or C<redo-ifchange>).  So it is an error if
the encoding of arguments (B<argv> of L<RdKw::I18N::CodeSets>) spells
it differently from the file system (B<filesys>): the bytes, and not the
encodings, so that an ASCII name is all right with UTF-8 file names and
ASCII arguments.  It is an error, too,
if a goal has the name of a file that a target makes or needs (redo
would take the goal for that file, and not make it), and if a target or
a goal is out of the build directory (where its F<.do> file could not
find the build directory again: a C<..> in its name, say).  The name
of a directory is all right.  Any other name is quoted for the shell, a
line break included.

Tested with apenwarr's redo, 0.42d.

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

None.

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

sub options { () }

sub default_output { q(all.do) }

sub emit
{
	my ($class, $plan, $default) = @_;
	# A goal's .do says how that goal was asked for (-t goal, or -t
	# WANT:goal), and no other; a target's says no goal.  So a .do is the
	# same file whatever else is asked for, and is then left alone.
	my $head = sub {
		"#\n# redo!\n" . RdKw::WwW::SiteConf::header_comment(
			{ %$plan, args => [ _with_goals($plan->{args} || [], @_) ] }) . "#\n";
	};
	my $target_head = $head->();
	my $marker = qr{(?:\A|/)\Q$plan->{D}{e}\E\z};
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
				line_break => __(
					# HEY!  the second %s is the value, which has a line break
					"%s: redo cannot spell a line break in %q (it ends a command)")));
		@cmd or die _status 0, tagmsg(E => diag(__(
			"%#q: no recipe to make it (and redo has no way to make"
			. " nothing)"), $file));
		my $text = $target_head . _preamble($target, 'out');
		my @need = grep { !/$marker/ } @{ $node->{deps} };
		$text .= "redo-ifchange " . join(' ', map { _word($_) } @need) . "\n" if @need;
		for (@cmd) {
			my ($ignore, $line) = @$_;
			# (make's `$$' is the shell's `$')
			$line =~ s/\$\$/\$/g;
			$text .= $ignore ? "( $line ) || true\n" : "( $line )\n";
		}
		$text .= "mv -f -- " . _word($target) . " \"\$siteconf_out\"\n";
		push @file, [ "$target.do", $text ];
	}

	# The default goal's .do (all.do, which a bare redo makes, unless -o
	# says otherwise; none for -o /dev/null): a name that redo looks for,
	# and of no file, and of no other goal
	# (and only if there is a default goal: -t goal has none)
	undef $default unless grep { defined $_->{default} } @{ $plan->{goals} };
	my $alias;
	if (defined $default) {
		($alias = $default) =~ s/\.do\z//
			# HEY!  %s is the name given with -o, for the default goal
			or die _status 0, tagmsg(E => diag(__(
				"redo cannot find %q: the name of a .do file ends in .do"),
				$default));
		length $alias && !$taken{$alias}
			# HEY!  %s is the name given with -o (as default.do)
			or die _status 0, tagmsg(E => diag(__(
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
				# HEY!  the second %s is the .do file of the default goal
				and die _status 0, tagmsg(E => diag(__(
					"redo cannot name goal %q: %s is the default goal's"),
					$name, "$alias.do"));
			$taken{$name}
				# HEY!  %s is the name of a goal, which a .do file is named after
				and die _status 0, tagmsg(E => diag(__(
					"redo cannot name goal %q: a file has that name"), $name));
			push @do, [ $name, $goal->{select} ];
		}
		push @do, [ $alias, $goal->{default} ] if defined $goal->{default} && defined $alias;
		for (@do) {
			my ($do, $how) = @$_;
			my $text = $head->($how) . _preamble($do);
			$text .= "redo-ifchange " . join(' ', map { _word($_) } @files) . "\n" if @files;
			push @file, [ "$do.do", $text ];
		}
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
	$B eq q(.) ? @redo : (q[(], q(cd), $q->($B), q(&&), @redo, q[)]);
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
# be written, as `out'), go to the build directory, and say what is said
# on the standard error.
sub _preamble
{
	my ($name, $out) = @_;
	_argv_is_fs($name);
	my @up = split m!/!, $name, -1;
	pop @up;
	grep { $_ eq '..' || $_ eq '.' || $_ eq '' } @up
		# HEY!  %s is the name of a target, or a goal
		and die _status 0, tagmsg(E => diag(__(
			"redo cannot name %q: it is not in the build directory"), $name));
	my $text = "set -e\n";
	$text .= 'case $3 in /*) siteconf_out=$3 ;; *) siteconf_out=$PWD/$3 ;; esac' . "\n"
		if $out;
	$text .= "cd " . join('/', ('..') x @up) . "\n" if @up;
	$text . "exec >&2\n";
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
		# HEY!  %s is a name, which the encoding of arguments (what is
		# typed after redo) has no bytes for
		or die _status 0, tagmsg(E => diag(__(
			"redo cannot name %q: arguments cannot spell it"), $name));
	$fs eq $argv
		# HEY!  %s is a name; an argument (what is typed after redo) and the
		# file system spell it in different bytes, in their encodings
		or die _status 0, tagmsg(E => diag(__(
			"redo cannot name %q: arguments and file names spell it"
			. " differently"), $name));
	1;
}

1;
