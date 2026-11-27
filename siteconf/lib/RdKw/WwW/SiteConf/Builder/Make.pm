package RdKw::WwW::SiteConf::Builder::Make;

use 5.008;
use strict;
use warnings;

use RdKw::WwW::SiteConf ();
our $VERSION = $RdKw::WwW::SiteConf::VERSION;

=head1 NAME

RdKw::WwW::SiteConf::Builder::Make - Makefile backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(make));   # siteconf -g -G make

=head1 DESCRIPTION

The generator C<make> of L<RdKw::WwW::SiteConf/generate>.  Each goal
becomes a phony target, the first of which is what a bare L<make(1)>
builds; there is also a rule to clean up if C<-Sclean> asks for it
(see below).  The one thing asked of L<make(1)> is that a recipe may
be a tab-indented shell fragment, so any make will do.

Any make will not do with just any name, though: there is no
escaping a file name in POSIX, and bmake reads a dependency line
twice, so that not even C<$$> is a C<$>.  So a name with white
space, a control, a C<$>, any of C<#:;=|(){}[]*?>, a C<\> at the
end or a C<~> in front is an error here, and so is a target with any
of C<%\E<lt>E<gt>"'`&>; L<RdKw::WwW::SiteConf::Builder::Gmake> escapes most of
those.

Names are spelled by C<< $class->_name >>, so that a subclass need
only say how else to spell them.

=head2 Options

Those of C<-S> of C<siteconf -g>:

=over

=item C<clean>

Without it, there is no rule to clean up.  C<-Sclean> makes one called
C<clean>, which removes the files that C<make> (the first goal) makes,
which are those that goal's manifest names, with what other goals it
includes; so it is the opposite of C<make>.  The directory markers
stay, and so do the files that are only made on the way (a cache
file, say, or anything the rules make that the manifest does not name).
C<-Sclean=>I<name> calls it I<name>.

A name may be made of what a goal name may, and C<&> in it stands for
the name of a goal: then
there is a rule for each goal, which removes what that goal makes, as
C<make> I<goal> does.  So C<-Sclean='clean-&'> makes C<clean-all> and
C<clean-small>.  A comma-separated list makes all that it names:
C<-Sclean='clean,clean-&'>.  An entry may not be empty.  A goal cannot
have the name of a rule.  A lone C<&> (which would name each rule after its
goal) means no rule, as no C<-Sclean> does.  The names may be of any
character an argument can spell.

=item C<purge>

The same as C<clean> (the names are the same sort, and may not clash
with those of C<clean>; the default name is C<purge>), but the rule
removes as well what is made on the way to what the manifest names, and
so on: a cache file, say.

=item C<arg_max>

How many bytes of file names an C<rm> line of a cleaning rule may
have; more files go on more lines.  16384 without it, or with no value.
C<-Sarg_max=>I<bytes> says how many, and C<-Sarg_max=0> or
C<-Sarg_max=> puts all of them on one line.  C<-Sarg_max=auto> is an
eighth of C<sysconf(_SC_ARG_MAX)> on the machine that runs
C<siteconf -g>, but no more than 131071 less the bytes of the C<rm>
command and a space: make hands a recipe line to C<sh -c> as one
argument, and Linux takes none longer than 128 KiB.
See L<RdKw::WwW::SiteConf/arg_max>.

=item C<mkpath>

Without it, or with C<-Smkpath=0> or no value, each directory has
a marker (C<.ok>, as C<-Se> says), a file that its rule makes once
the directory is there: C<[ -d >I<dir>C< ] || mkdir -- >I<dir>, then
C<< @> >>I<marker>.  What is made in a directory depends on its marker.
With C<-Smkpath=1>, there are no markers, and the recipe of each file
begins with C<mkdir -p -- >I<dir>.

=item C<cmd_mkdir>, C<cmd_touch>, C<cmd_mkdir_p>, C<cmd_rm_f>

The commands of the rules above, which the names follow as words of
their own: C<mkdir --> and C<< @> >> make a directory and its marker,
C<mkdir -p --> a directory with C<-Smkpath=1>, and C<rm -f --> removes
the files of a cleaning rule.  L<RdKw::WwW::SiteConf/command> says
what a command may be.  The C<@>, C<-> and C<+> in front of one are
for make, and go in front of the line it is on:
C<-Scmd_mkdir='@mkdir --'> writes C<@[ -d >I<dir>C< ] || mkdir -- >I<dir>.
A C<$> in the rest is the shell's (make reads it as C<$$>), so
C<-Scmd_rm_f='sh -c '\''rm -fv -- "$@"'\'' sh'> runs the C<sh -c>
that it says.

=back

The Makefile is bytes.  L<make(1)> reads the Makefile as bytes, in
no particular encoding.  So every name in a rule, a recipe or the
header is spelled as the file system spells it:
L<RdKw::I18N::CodeSets/filesys>; except the name of a goal or a cleaning
rule (which one types after C<make>), which is spelled as an argument
is: L<RdKw::I18N::CodeSets/argv>.  A name the file system cannot spell
is an error.

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

C<clean>, C<purge>, L</arg_max>, L</mkpath> and the C<cmd_> options.

=item B<default_output>

F<Makefile>.

=item B<emit> I<plan>, I<file>

The Makefile, as C<[ >I<file>C<, >I<bytes>C< ]>.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

I<generator> (C<make> or C<gmake>), with C<-C> I<builddir> unless it
is C<.>, C<-f> I<file> if it is defined, and I<goal> if it is.

=back

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

# Linux takes no argument longer than 128 KiB, its NUL included; make
# hands each recipe line to `sh -c' as one, so -Sarg_max=auto (which
# goes by the total) may not say more than this, less the command
# (`rm -f -- ') and its space.
use constant ARG_LEN => 131072 - 1;

sub _status { $! = 0; $? = shift; @_; }

# A string as the file system spells it, so that make finds the file;
# or an error prefixed `E:'.
sub _fs { RdKw::WwW::SiteConf::fs_text($_[1]); }

# Every string from the plan goes through _fs.  The result is bytes
# throughout: a byte string joined to a character string would be
# upgraded by perl, and spelled wrong.
sub _text
{
	my ($class, $plan) = @_;
	# (where a name is, for GNU Make: a `target', an `order'-only
	# prerequisite, or another prerequisite)
	my $name = sub { $class->_name(@_) };
	my $fs = sub { $class->_fs(@_) };
	# What is typed after `make' (the name of a goal, or of a rule): as an
	# argument is spelled
	my $arg = sub { RdKw::WwW::SiteConf::argv_text($_[0]) };
	my $D = $plan->{D};
	my @goal = @{ $plan->{goals} };
	# Every target is named as one first: the goal lines name them as
	# prerequisites, and an error there would say what GNU Make can do
	# with a prerequisite (a tab, say), which is not what it can do with
	# a target.
	# (with -Smkpath=1, each recipe makes its directory, and there are no
	# markers to make)
	my $mkpath = $plan->{opt} && $plan->{opt}{mkpath} ? 1 : 0;
	my @dirs = $mkpath ? () : @{ $plan->{dirs} };
	$name->($_, 'target') for (map { $_->{marker} } @dirs),
		map { $plan->{node}{$_}{bpath} } @{ $plan->{order} };
	my $out = "#\n# Makefile!\n" . RdKw::WwW::SiteConf::header_comment($plan) . "#\n"
		. ".PHONY: " . join(' ', map { $arg->($_->{name}) } @goal, @{ $plan->{clean} }) . "\n";

	for my $goal (@goal) {
		my @target = map { $name->($plan->{node}{$_}{bpath}) } @{ $goal->{files} };
		$out .= $arg->($goal->{name}) . ": @target\n";
	}
	my ($rm_at, $rm) = $class->_command($plan->{opt}, cmd_rm_f => q(rm -f --));
	my $max = RdKw::WwW::SiteConf::arg_max($plan->{opt},
		ARG_LEN - length(RdKw::WwW::SiteConf::command($plan->{opt}, cmd_rm_f => q(rm -f --))) - 1);
	for my $rule (@{ $plan->{clean} }) {
		$out .= $arg->($rule->{name}) . ":\n";
		# So many files go on several lines (0: one line)
		my @file = map { _quote($fs->($_)) } @{ $rule->{files} };
		while (@file) {
			my $line = shift @file;
			$line .= ' ' . shift @file
				while @file and (!$max || length($line) + 1 + length($file[0]) <= $max);
			$out .= "\t$rm_at$rm $line\n";
		}
	}

	# A directory marker has only to be there, so what is made in a
	# directory need not wait on how new it is: that is, with `|', if
	# the backend asks for it (-Sorder=1).
	my $order = $class->_order_only($plan->{opt});
	my %marker = map { $_->{marker} => 1 } @{ $plan->{dirs} };
	my $deps = sub {
		@_ = grep { !$marker{$_} } @_ if $mkpath;
		my @dep = $order ? grep({ !$marker{$_}; } @_) : @_;
		my @mark = $order ? grep({ $marker{$_}; } @_) : ();
		join ' ', (map { $name->($_) } @dep), (@mark ? ('|', map { $name->($_, 'order') } @mark) : ());
	};

	# (each command of -S, as make reads it; see _command)
	my ($mkdir_at, $mkdir) = $class->_command($plan->{opt}, cmd_mkdir => q(mkdir --));
	my ($touch_at, $touch) = $class->_command($plan->{opt}, cmd_touch => q(@>));
	my ($mkdir_p_at, $mkdir_p) = $class->_command($plan->{opt}, cmd_mkdir_p => q(mkdir -p --));
	for my $dir (@dirs) {
		my $d = _quote($fs->($dir->{dir}));
		$out .= $name->($dir->{marker}, 'target') . ": " . $deps->(@{ $dir->{deps} }) . "\n";
		$out .= "\t$mkdir_at\[ -d $d ] || $mkdir $d\n";
		$out .= "\t$touch_at$touch " . _quote($fs->($dir->{marker})) . "\n";
	}

	for my $file (@{ $plan->{order} }) {
		my $node = $plan->{node}{$file};
		my $recipe = RdKw::WwW::SiteConf::recipe_bytes($node->{recipe},
			line_break => __(
				# HEY!  the second %s is the value, which has a line break
				"%s: make cannot spell a line break in %q (it ends a command)"));
		$recipe .= "\n" if length $recipe and $recipe !~ /\n\z/;
		my ($dir) = $node->{bpath} =~ m{\A(.*)/};
		$recipe = "\t$mkdir_p_at$mkdir_p " . _quote($fs->($dir)) . "\n$recipe"
			if $mkpath and defined $dir;
		$out .= $name->($node->{bpath}, 'target') . ": " . $deps->(@{ $node->{deps} }) . "\n" . $recipe;
	}
	$out;
}

sub options { qw( clean purge arg_max mkpath cmd_mkdir cmd_mkdir_p cmd_rm_f cmd_touch ); }

sub default_output { q(Makefile); }

sub emit { my ($class, $plan, $file) = @_; [ $file, $class->_text($plan) ]; }

sub build_command
{
	my ($class, $prog, $B, $file, $goal) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	($prog, ($B eq q(.) ? () : (q(-C), $q->($B))),
		(defined $file ? (q(-f), $q->($file)) : ()),
		(defined $goal ? $q->($goal) : ()));
}

# A command of -S (see RdKw::WwW::SiteConf/command), as make reads it:
# the prefix that make reads in front of a recipe line (`@', `-', `+'),
# which goes in front of the line it is in, and the command after it,
# with a `$' as `$$' (make expands nothing in it)
sub _command
{
	my ($class, $opt, $name, $default) = @_;
	my ($prefix, $cmd) = RdKw::WwW::SiteConf::command($opt, $name, $default)
		=~ /\A((?:[\@+-][ \t]*)*)(.*)\z/s;
	length $cmd
		or die _status 0, tagmsg(E => diag(__("%s: no command to run"), "-S$name"));
	$prefix =~ s/[ \t]//g;
	$cmd =~ s/\$/\$\$/g;
	($prefix, $cmd);
}

# Whether a directory marker is an order-only prerequisite (after a `|')
sub _order_only { 0; }

# A name, as any make reads it: as it is, or not at all
sub _name
{
	my ($class, $s, $where) = @_;
	# (and in a target, what siteconf has never let a target have)
	$s =~ /([\p{Cc} \x{2028}\x{2029}\$#:;=|(){}\[\]*?]|\\\z|\A~)/
		|| ($where || '') eq 'target' && $s =~ /([%\\<>"'`&])/
		or return $class->_fs($s);
	my $c = $1;
	require RdKw::WwW::SiteConf::Builder::Gmake;
	my $gnu_can = eval { RdKw::WwW::SiteConf::Builder::Gmake->_name($s, $where); 1; };
	die _status 0, tagmsg(E => diag($gnu_can
		# HEY!  the %s is a character, as `$' or U+0020.
		# You don't need to keep the ";)"; it's just
		# reflexive for me as a tone indicator... :x
		? __("make cannot name %q (with inescapable %s),\n"
		. "... but GNU Make can!  (Pass -G gmake if you want that. ;)")
		: __("make cannot name %q (with inescapable %s)"), $s, $class->_char($c)));
}

# A character, as one would see it said
sub _char
{
	my ($class, $c) = @_;
	$c =~ /\A[!-~]\z/ ? "`$c'" : sprintf 'U+%04X', ord $c;
}

# A name, as bytes, for the shell in make's words.  It is quoted by what
# the shell reads, which are bytes: `'\'' is written after any byte that
# is a quote, so that what the shell makes of it is the same bytes.
sub _quote
{
	my ($bytes) = @_;
	(my $s = RdKw::WwW::SiteConf::shell_quote($bytes)) =~ s/\$/\$\$/g;
	$s;
}

1;

=head1 SEE ALSO

L<RdKw::WwW::SiteConf::Builder>, L<RdKw::WwW::SiteConf/generate>.

=cut
