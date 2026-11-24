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
in the build directory (F<all.do>).  A file of that name that is
already there is overwritten.  So the output tree holds the F<.do>
files too.

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
it differently from the file system (B<filesys>).  It is an error, too,
if a goal has the name of a target or of a directory of one, and if
a target is out of the build directory (where its F<.do> file could
not find the build directory again).  Any other name is quoted for the
shell, a line break included.

Tested with apenwarr's redo, 0.42d.

=head2 Methods

These are what L<RdKw::WwW::SiteConf/generate> asks of a generator.
They change with siteconf: they are not a stable interface.

=over

=item B<options>

None.

=item B<default_output>

C<undef>: there are many files, and C<-o> cannot name them.

=item B<emit> I<plan>

The F<.do> files, as C<[ >I<name>C<, >I<bytes>C< ]>.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

C<redo> I<builddir>C</>I<goal>, or C<redo> in I<builddir> if there is
no goal.

=back

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

sub options { () }

sub default_output { undef }

sub emit
{
	my ($class, $plan) = @_;
	my $head = "#\n# redo!\n" . RdKw::WwW::SiteConf::header_comment($plan) . "#\n";
	my $marker = qr{(?:\A|/)\Q$plan->{D}{e}\E\z};
	my @file;

	# What a goal may not be called: a target, or a directory of one
	my %taken;
	for my $file (@{ $plan->{order} }) {
		my $path = $plan->{node}{$file}{bpath};
		$taken{$path} = 1;
		$taken{$path} = 1 while $path =~ s!/[^/]*\z!!;
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
		my $text = $head . _preamble($target, 'out');
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

	for my $goal (@{ $plan->{goals} }) {
		my $name = $goal->{name};
		$taken{$name}
			# HEY!  %s is the name of a goal, which a .do file is named after
			and die _status 0, tagmsg(E => diag(__(
				"redo cannot name goal %q: a target or its directory has"
				. " that name"), $name));
		my $text = $head . _preamble($name);
		my @files = map { $plan->{node}{$_}{bpath} } @{ $goal->{files} };
		$text .= "redo-ifchange " . join(' ', map { _word($_) } @files) . "\n" if @files;
		push @file, [ "$name.do", $text ];
	}
	@file;
}

sub build_command
{
	my ($class, $prog, $B, $file, $goal) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	return ($prog, $q->($B eq '.' ? $goal : "$B/$goal")) if defined $goal;
	$B eq '.' ? ($prog) : ('cd', $q->($B), '&&', $prog);
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
	my $argv = RdKw::WwW::SiteConf::argv_text($name);
	$fs eq $argv
		# HEY!  %s is a name; an argument (what is typed after redo) and the
		# file system spell it in different bytes, in their encodings
		or die _status 0, tagmsg(E => diag(__(
			"redo cannot name %q: arguments and file names spell it"
			. " differently"), $name));
	1;
}

1;
