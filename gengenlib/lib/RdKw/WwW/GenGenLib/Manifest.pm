package RdKw::WwW::GenGenLib::Manifest;

use 5.008;
use strict;
use warnings;

use RdKw::WwW::GenGenLib ();
our $VERSION = $RdKw::WwW::GenGenLib::VERSION;

=head1 NAME

RdKw::WwW::GenGenLib::Manifest - siteconf manifest parser

=head1 SYNOPSIS

    use RdKw::WwW::GenGenLib qw( read_manifest );

    # MAKE goal
    #     NEED sunshine
    #     NEED rainbow
    #     WANT disco_ball
    # MAKE other
    my $mf = read_manifest({}, 'MANIFEST');

    scalar $mf->target;     # 'goal'
    $mf->default_target;    # the same, in any context
    $mf->target;            # qw( goal other ), in list context
    $mf->targets;           # the same, in any context
    $mf->needed;            # qw( sunshine rainbow )
    $mf->needed('other');   # ()
    $mf->wanted;            # qw( disco_ball )

    my @all_NEEDs = map $mf->needed($_), $mf->target;
    my @all_WANTs = map $mf->wanted($_), $mf->target;

=head1 DESCRIPTION

A manifest names the goals of a build, each a L<make(1)> target, and
the files that each one C<NEED>s (it cannot be made without them) or
C<WANT>s (it can, and they are dropped):

    MAKE all
        NEED index.html           # a comment
        WANT extra/index.html

    MAKE small
        NEED index.html

Lines are split into words at white space as L<make(1)> knows it --
space, tab, newline, vertical tab, form feed and carriage return --
and at nothing else (a no-break space is part of a name).  Indentation
is only for the eyes.  A C<#> at the start of a line, or after white
space, begins a comment.  The file is UTF-8.

C<JUST-NEED> and C<JUST-WANT> are those two, for a file whose header
is not read, and what is in it is not followed (see
L<RdKw::WwW::GenGenLib/read_deps>); they are spelled out in full.

    MAKE christmas
        WANT      not-a-lot
        JUST-NEED one-thing

A keyword may have a colon after it, with or without a space (C<MAKE: all>,
C<NEED:index.html>).

C<INCLUDE> takes one or more paths, and reads those manifests where it
stands, as if they were written there: the last C<MAKE> goes on in
them, and on after them.  A path is a spec of L<RdKw::WwW::GenGenLib/subs_deps> with the
definitions given to L</read>, and is a path from the current
directory, which is taken to be C<${A}>.  Every file must exist, and
none may include itself.

C<MAKE> takes the name of a goal (a string, C<${"...">C<}>, stands for its
characters, which must be a goal name as well): any characters but white space
(of any script, a no-break space too), controls, format characters
(a zero-width joiner, say), and C<:>, C<#>, C<%>, C<$> and C<\>, not
beginning with a hyphen.  So it may have a slash, and letters of any
script.  There is nothing to escape.  A goal is only made once.

C<NEED> and C<WANT> take any number of names, which belong to the last
C<MAKE>; each is split off at white space, and is unescaped as a spec
of L<RdKw::WwW::GenGenLib/subs_deps> without definitions is (see
L<RdKw::WwW::GenGenLib/escape_deps>, which writes one): C<${$}> or
C<$$> is a C<$>, C<${U+>I<hex>C<}> is that character (C<${U+0020}>
for a space, C<${U+0023}> for a C<#> that is no comment, and C<${"...">C<}>
for a string, as in C<${"some\sbread"}>: see L<RdKw::WwW::GenGenLib/scan_string>), and a
leading C<${A}/> is the root and is dropped, as it is in a header.
Any other variable, and any malformed C<$>, is an error, and so is a
name that is nothing, or that has a NUL in it.  What a name I<may> be
is not for us to say: the build decides that (L<siteconf(1)> takes
no blanks, for one, escaped or not).

Errors say C<read_manifest: >I<file>C< line >I<n>C<: ...>.

=head1 METHODS

=over

=cut

use Cwd qw( abs_path );
use Encode ();
use RdKw::WwW::GenGenLib qw( subs_deps );

use RdKw::I18N::CodeSets::Functions qw( diag to_fs tagmsg );
# Use the same gettext domain as our parent GenGenLib.pm.
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

# POSIX white space since [[:space:]] is too broad.
# (This is the same character set used in SiteConf.pm)
my $SP = '\t\n\cK\f\r ';

# A string literal, ${"..."}
my $STRING = qr/\$\{"(?:[^"\\]|\\.)*"\}/s;

# What a goal may be called: anything that is a name to make and ninja
# alike, that is no white space (of any script), control or format
# character, and none of `: # % $ \'; and no hyphen to begin with
my $GOAL = qr/\A(?!-)[^\s\p{Cc}\p{Cf}:#%\$\\]+\z/;

=item B<read> \%D, I<file>[, { prog => 'read_manifest' }]

Reads I<file> (a name, which is spelled as L<RdKw::I18N::CodeSets>
says, or a reference to the text itself, which is then called
F<MANIFEST>).  L<RdKw::WwW::GenGenLib/read_manifest> is the same.
C<\%D> is a required map of variable definitions, as for
L<RdKw::WwW::GenGenLib/walk_deps>: it is substituted in the paths of
C<INCLUDE>, and nowhere else.  The current directory is taken to be
the project root, C<${A}>, so a caller gives C<A> as C<.>, or leaves
it out.

=cut

sub _blame
{
	my ($file, $line) = @_;
	# HEY!  %#q is the file name of the faulty
	# file and %d is its lineno.
	diag(__("%#q line %d"), $file, $line);
}

# Where a line is: `input' (the name of a file) and `line'
sub _where { _blame($_[0]{input}, $_[0]{line}) }

sub read
{
	my $kwds = RdKw::WwW::GenGenLib::_getkwds(\@_);
	# Usually read_manifest delegates to us;
	# so we are them.
	my ($class, $D, $file) = @_;
	my $prog = RdKw::WwW::GenGenLib::_getprog($kwds, 'read_manifest');
	my $name = ref $file ? 'MANIFEST' : $file;
	# What is read so far: the goals, and the last MAKE (an INCLUDE
	# shares both); how many lines; and the files that are open.
	my $st = { D => $D, prog => $prog, goals => [], goal => {},
		cur => undef, order => 0, open => {} };
	_read_file($st, $file, $name);
	# HEY!  It's singular because "no mind to think,
	# no will to break, no voice to cry suffering..."
	# (actually, with a verb now, it is substantially
	# more clear.)
	@{ $st->{goals} } or die _status 0, tagmsg($prog => diag(__("%#q: no goal to make"), $name));
	bless { file => $name, goals => $st->{goals}, goal => $st->{goal}, prog => $prog }, $class;
}

# Read `input' (a name, or a reference to the text), called `name'.
# `at' is where the INCLUDE that names it is, if one does.
sub _read_file
{
	my ($st, $input, $name, $at) = @_;
	my $prog = $st->{prog};
	my ($fh, $key);
	if (ref $input) {
		open $fh, '<', $input
			or die tagmsg($prog => diag(__("cannot open string: %m")));
	} else {
		my $path = to_fs($input, { prog => $prog });
		open $fh, '<', $path or die tagmsg($prog => defined $at
			? diag(__("%s: cannot open file %q: %m"), $at, $input)
			: diag(__("cannot open file %q: %m"), $input));
		# (a file is the same file whatever path names it)
		$key = abs_path($path);
		defined $key or $key = $path;
		$st->{open}{$key} and die _status 0, tagmsg($prog => diag(__(
			"%s: include cycle through %q"), $at, $input));
	}
	local $st->{open}{$key} = 1 if defined $key;
	my $n = 0;
	while (defined(my $text = <$fh>)) {
		my $pos = { input => $name, line => ++$n, order => ++$st->{order} };
		eval { $text = Encode::decode('UTF-8', $text, Encode::FB_CROAK()); 1; }
			or die _status 0, tagmsg($prog => diag(__("%s: not UTF-8"), _where($pos)));
		_read_line($st, $text, $pos);
	}
	close $fh or die tagmsg($prog => diag(__("cannot read file %q: %m"), $name));
}

# `arg' of the line at `pos' as one name: unescaped, with `D' (if
# given) substituted
sub _name
{
	my ($st, $arg, $pos, $D) = @_;
	my $prog = $st->{prog};
	my $name = eval { subs_deps($D, $arg,
		{ strict => 1, on_missing => 'croak', prog => undef }) };
	defined $name or do {
		# Prefix subs_deps' error message with our name
		# and a blame line.
		(my $why = $@) =~ s/^/_where($pos) . ": "/gem;
		die tagmsg($prog => $why);
	};
	length $name or die _status 0, tagmsg($prog => diag(__("%s: %q is empty"),
		_where($pos), $arg));
	$name =~ /\0/ and die _status 0, tagmsg($prog => diag(__("%s: %q has a NUL in it"),
		_where($pos), $arg));
	$name;
}

sub _read_line
{
	my ($st, $text, $pos) = @_;
	my $prog = $st->{prog};
	my ($kw, @arg);
	if ($text =~ /\$\{"/) {
		# String literals may be present:  upgrade
		# to the same stateful lexer read_deps uses.
		($kw, @arg) = RdKw::WwW::GenGenLib::_words($text, blank => $SP, hash => 1);
	} else {
		$text =~ s/(?:^|[$SP])#.*//so;
		($kw, @arg) = $text =~ /([^$SP]+)/go;
	}
	defined $kw or return;
	# MAKE:, NEED: and WANT: are those, with a colon (and then
	# a name may follow it, without a space)
	if ($kw =~ s/\A(INCLUDE|MAKE|NEED|WANT|JUST-NEED|JUST-WANT)://) {
		my $key = $1;
		unshift @arg, $kw if length $kw;
		$kw = $key;
	}
	if ($kw eq 'INCLUDE') {
		@arg or die _status 0, tagmsg($prog => diag(__(
			# HEY!  the second %s is the keyword: INCLUDE or AUGMENT
			"%s: %s takes at least one file"), _where($pos), 'INCLUDE'));
		for my $path (map { _name($st, $_, $pos, $st->{D}) } @arg) {
			_read_file($st, $path, $path, _where($pos));
		}
		return;
	}
	if ($kw eq 'MAKE') {
		@arg == 1 or die _status 0, tagmsg($prog => diag(__(
			"%s: MAKE takes exactly one goal name"), _where($pos)));
		# (a string is the only escape in a goal name, and what it
		# says must be a goal name too)
		(my $name = $arg[0]) =~ s{($STRING)}{
			my $d = RdKw::WwW::GenGenLib::_decode_string(substr $1, 3, -2);
			defined $d ? $d : $1 }ge;
		$name =~ /$GOAL/
			or die _status 0, tagmsg($prog => diag(__("%s: bad goal name %q"),
			_where($pos), $name));
		$st->{goal}{$name} and die _status 0, tagmsg($prog => diag(__(
			"%s: goal %q is already made"), _where($pos), $name));
		push @{ $st->{goals} }, $st->{cur} = $st->{goal}{$name}
			= { name => $name, need => [], want => [], %$pos };
		return;
	}
	if ($kw =~ /\A(?:JUST-)?(?:NEED|WANT)\z/) {
		$st->{cur} or die _status 0, tagmsg($prog => diag(__(
			# HEY!  the second %s is the string "NEED" or "WANT"
			"%s: %s before any MAKE"),
			_where($pos), $kw));
		@arg or die _status 0, tagmsg($prog => diag(__(
			# HEY!  the second %s is the string "NEED" or "WANT"
			"%s: %s takes a file (use # for comments)"),
			_where($pos), $kw));
		(my $key = lc $kw) =~ s/\Ajust-//;
		my $just = $kw =~ /\AJUST-/ ? 1 : 0;
		push @{ $st->{cur}{$key} }, map {
			+{ file => _name($st, $_, $pos), %$pos, just => $just }
		} @arg;
		return;
	}
	die _status 0, tagmsg($prog => diag(__(
		"%s: expected MAKE, NEED, WANT, JUST-NEED or JUST-WANT, not %q"),
		_where($pos), $kw));
}

=item B<file>

The name of the file that was read.

=cut

sub file { $_[0]{file} }

=item B<target>

The name of the first goal in scalar context, which is the default
one; and the names of all goals, in order, in list context.

=item B<default_target>

=item B<targets>

The same, whatever the context.

=cut

sub target { wantarray ? $_[0]->targets : $_[0]->default_target }

sub default_target { $_[0]{goals}[0]{name} }

sub targets { map { $_->{name} } @{ $_[0]{goals} } }

=item B<needed> [ I<goal> ]

=item B<wanted> [ I<goal> ]

The names that I<goal> (the default one, if not given) C<NEED>s, or
C<WANT>s (also with C<JUST->), in order, as they were in the manifest -- unescaped.  A
goal that is not there is an error.

=cut

sub _goal
{
	my ($self, $name) = @_;
	defined $name or return $self->{goals}[0];
	$self->{goal}{$name} or die _status 0, tagmsg($self->{prog} =>
		diag(__("%#q: missing goal %q"), $self->{file}, $name));
}

sub needed { map { $_->{file} } @{ $_[0]->_goal($_[1])->{need} } }

sub wanted { map { $_->{file} } @{ $_[0]->_goal($_[1])->{want} } }

=item B<goals>

All goals, in order, with the lines they were on: a list of
C<< { name, input, line, order, need, want } >> hash references, where
the latter two are lists of C<< { file, input, line, order, just } >>
(C<just> is 1 for a C<JUST-NEED> or C<JUST-WANT>, and 0 if not).
C<input> is the manifest the line is in (as L</file> names the first,
and as C<INCLUDE> expands the others), and C<order> counts the lines
read, across every file, from 1.  These are copies.

=cut

sub goals
{
	map {
		my $g = $_;
		+{ %$g, map { $_ => [ map { +{ %$_ } } @{ $g->{$_} } ] } qw( need want ) };
	} @{ $_[0]{goals} };
}

=back

Added in 0.0100.

=cut

1;
