package RdKw::WwW::SiteConf::Builder::Ninja;

use 5.008;
use strict;
use warnings;

use version;
use RdKw::WwW::SiteConf 0.03_00 ();

our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

RdKw::WwW::SiteConf::Builder::Ninja - build.ninja backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(ninja));   # siteconf -g -G ninja

=head1 DESCRIPTION

The generator C<ninja> of L<RdKw::WwW::SiteConf/generate>.  Each
goal is a C<phony> build statement, the first of which is the
C<default>.  Every file gets a rule of its own (C<rule1>, C<rule2>,
...), holding the recipe from
F<Makefile.in>, since by now it has been spelled out for that very
file; the sources and the first dependency are the explicit inputs,
the rest are implicit, and the directory marker is order-only.

Recipes are written as for L<make(1)>, so this undoes make's reading
of them: each line is a command of its own (and so is run in a
subshell, as C<cd> would not carry over in make either), a backslash
joins lines, a leading C<@> is dropped and a leading C<-> ignores
failure.  For clean-up there is C<ninja -t clean>.

Each directory has a marker (C<.ok>, as C<-Se> says), which the rule
C<mkdir_marker> makes: C<[ -d >I<dir>C< ] || mkdir -- >I<dir>, then
C<< > >>I<marker>.  With C<-Smkpath=1> there are no markers, and the
command of each file begins with C<mkdir -p -- >I<dir>C< &&>.

A space, C<:> or C<$> in a name is escaped (as C<$ >, C<$:> and
C<$$>).  A C<|> has no escape, and is C<${pipe}>, a variable that
F<build.ninja> sets to C<|>.  Any other character is as it is, a tab
and a C<#> included.  A vertical space (a line break, CR, form feed,
...) cannot be named, and is an error.

F<build.ninja> is bytes, as the Makefile of
L<RdKw::WwW::SiteConf::Builder::Make> is.  Ninja reads F<build.ninja> as bytes, so every name and every recipe is
spelled as the file system spells it: L<RdKw::I18N::CodeSets/filesys>.
A name the file system cannot spell is an error.

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

C<mkpath>, C<cmd_mkdir> and C<cmd_mkdir_p>, as for
L<RdKw::WwW::SiteConf::Builder::Make/Options>, but a C<@>, C<-> or C<+>
in front of a command is as it is: ninja reads nothing in front of
a command.  A C<$> in a command is the shell's (ninja reads it as
C<$$>).  There is no cleaning rule: C<ninja -t clean> cleans.

=item B<default_output>

F<build.ninja>.

=item B<emit> I<plan>, I<file>

F<build.ninja>, as C<[ >I<file>C<, >I<bytes>C< ]>.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

C<ninja>, with C<-C> I<builddir> unless it is C<.>, C<-f> I<file> if
it is defined, and I<goal> if it is.

=back

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

# A name as the file system spells it, or an error prefixed `E:' (see
# RdKw::WwW::SiteConf::fs_text for what that is).
sub _fs { RdKw::WwW::SiteConf::fs_text($_[0]); }

# Every string from the plan goes through _fs, so the result is bytes
# throughout.  Make.pm says why.
sub options { qw( mkpath cmd_mkdir cmd_mkdir_p ); }

sub default_output { q(build.ninja); }

sub emit { my ($class, $plan, $file) = @_; [ $file, $class->_text($plan) ]; }

sub build_command
{
	my ($class, $prog, $B, $file, $goal) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	($prog, ($B eq q(.) ? () : (q(-C), $q->($B))),
		(defined $file ? (q(-f), $q->($file)) : ()),
		(defined $goal ? $q->($goal) : ()));
}

sub _text
{
	my ($class, $plan) = @_;
	my @goal = @{ $plan->{goals} };
	# (with -Smkpath=1, each command makes its directory, and there are no
	# markers to make)
	my $mkpath = $plan->{opt} && $plan->{opt}{mkpath} ? 1 : 0;
	my @dirs = $mkpath ? () : @{ $plan->{dirs} };
	my $mkdir = _cmd($plan->{opt}, cmd_mkdir => q(mkdir --));
	my $mkdir_p = _cmd($plan->{opt}, cmd_mkdir_p => q(mkdir -p --));

	my $out = "#\n# build.ninja!\n" . RdKw::WwW::SiteConf::header_comment($plan) . "#\n" . <<NINJA;
ninja_required_version = 1.3

# (a `|' in a path would end it; \${pipe} does not)
pipe = |

NINJA
	$out .= <<NINJA if @dirs;
rule mkdir_marker
  command = [ -d \$dir ] || $mkdir \$dir && > \$out
  description = MKDIR \$dir

NINJA

	for my $dir (@dirs) {
		my $line = "build " . _path($dir->{marker}) . ": mkdir_marker";
		$line .= " || " . join ' ', map { _path($_) } @{ $dir->{deps} }
			if @{ $dir->{deps} };
		_vertical($dir->{dir});
		$out .= "$line\n  dir = "
			. _escape(RdKw::WwW::SiteConf::shell_quote(_fs($dir->{dir}))) . "\n";
	}
	$out .= "\n" if @dirs;

	my $n = 0;
	for my $file (@{ $plan->{order} }) {
		my $node = $plan->{node}{$file};
		my $command = _command(RdKw::WwW::SiteConf::recipe_bytes($node->{recipe},
			line_break => __(
				# HEY!  the second %s is the value, which has a line break
				"%s: ninja cannot spell a line break in %q (it ends a command)")));
		defined $command and length $command
			or die _status 0, tagmsg(E => diag(__(
				"%#q: no recipe to make it (and ninja has no"
				. " way to make nothing)"), $file));
		my ($dir) = $node->{bpath} =~ m{\A(.*)/};
		if ($mkpath and defined $dir) {
			_vertical($dir);
			$command = "$mkdir_p " . _escape(RdKw::WwW::SiteConf::shell_quote(_fs($dir)))
				. " && $command";
		}
		my $rule = 'rule' . ++$n;
		$out .= "rule $rule\n  command = $command\n";

		# Input first, then what we need but is not an input; what is
		# a marker only has to be there, not newer.
		my @dep = @{ $node->{deps} };
		my $input = $node->{nosrc} ? undef : shift @dep;
		my (@need, @order);
		for (@dep) {
			if (m{(?:\A|/)\Q$plan->{D}{e}\E\z}) { push @order, $_ unless $mkpath; }
			else { push @need, $_; }
		}
		my $build = "build " . _path($node->{bpath}) . ": $rule";
		$build .= " " . _path($input) if defined $input;
		$build .= " | " . join ' ', map { _path($_) } @need if @need;
		$build .= " || " . join ' ', map { _path($_) } @order if @order;
		$out .= "$build\n\n";
	}

	# A goal is typed after `ninja', so it is encoded as an argument is.
	$out .= "build " . RdKw::WwW::SiteConf::argv_text($_->{name}) . ": phony "
		. join(' ', map { _path($plan->{node}{$_}{bpath}) } @{ $_->{files} })
		. "\n" for @goal;
	$out .= "\ndefault " . RdKw::WwW::SiteConf::argv_text($goal[0]{name}) . "\n" if @goal;
	$out;
}

# A command of -S (see RdKw::WwW::SiteConf/command), with a `$' as
# `$$' (ninja expands nothing in it)
sub _cmd { (my $b = RdKw::WwW::SiteConf::command(@_)) =~ s/\$/\$\$/g; $b; }

# A path, as ninja wants to read it (which is never with a line
# break, and with a `|' as ${pipe}): bytes.
sub _path
{
	my ($s) = @_;
	_vertical($s);
	(my $b = _escape(_fs($s))) =~ s/\|/\${pipe}/g;
	$b;
}

# An error if ninja cannot name the string, whatever it escapes
sub _vertical
{
	my ($s) = @_;
	$s =~ /([\n\cK\f\r\x{85}\x{2028}\x{2029}])/
		and die _status 0, tagmsg(E => diag(__(
			# HEY!  the %s is a character, as U+000A
			"ninja cannot name %q (with inescapable %s)"),
			$s, sprintf('U+%04X', ord $1)));
}

# What ninja reads as a space, a colon or a variable in bytes, escaped
sub _escape { (my $b = $_[0]) =~ s/([ :\$])/\$$1/g; $b; }

# make's recipe, in make's words, as one command in ninja's.  A lone
# `$' in it is for make, and we do not have any (`$$' stays `$$': it is
# `$' to the shell either way, and a `$' to ninja is written `$$').
# Each command is grouped, so that `|| true' is not for what came before.
sub _command
{
	join q( && ), map { $_->[0] ? "( ( $_->[1] ) || true )" : "( $_->[1] )" }
		RdKw::WwW::SiteConf::recipe_commands($_[0]);
}

1;

=head1 SEE ALSO

L<RdKw::WwW::SiteConf::Builder>, L<RdKw::WwW::SiteConf/generate>.

=cut
