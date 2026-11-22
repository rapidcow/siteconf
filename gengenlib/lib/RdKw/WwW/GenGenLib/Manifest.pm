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
    my $mf = read_manifest('MANIFEST');

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

C<MAKE> takes the name of a goal: any characters but white space
(of any script, a no-break space too), controls, format characters
(a zero-width joiner, say), and C<:>, C<#>, C<%>, C<$> and C<\>, not
beginning with a hyphen.  So it may have a slash, and letters of any
script.  There is nothing to escape.  A goal is only made once.

C<NEED> and C<WANT> take any number of names, which belong to the last
C<MAKE>; each is split off at white space, and is unescaped as a spec
of B<subs_deps> without definitions is (see L<RdKw::WwW::GenGenLib/escape_dep>, which writes one): C<${$}>
or C<$$> is a C<$>, C<${U+>I<hex>C<}> is that character (C<${U+0020}>
for a space, C<${U+0023}> for a C<#> that is no comment, and C<${"...">C<}>
for a string, as in C<${"some\sbread"}>: see B<scan_string>), and a
leading C<${A}/> is the root and is dropped, as it is in a header.
Any other variable, and any malformed C<$>, is an error, and so is a
name that is nothing, or that has a NUL in it.  What a name I<may> be
is not for us to say: the build decides that (L<siteconf(1)> takes
no blanks, for one, escaped or not).

Errors say C<read_manifest: >I<file>C< line >I<n>C<: ...>.

=head1 METHODS

=over

=cut

use Encode ();
use RdKw::WwW::GenGenLib qw( subs_deps );

use RdKw::I18N::CodeSets::Functions qw( diag to_fs tagmsg );
# Use the same gettext domain as our parent GenGenLib.pm.
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

# POSIX white space since [[:space:]] is too broad.
# (This is the same character set used in SiteConf.pm)
my $SP = '\t\n\cK\f\r ';

# What a goal may be called: anything that is a name to make and ninja
# alike, that is no white space (of any script), control or format
# character, and none of `: # % $ \'; and no hyphen to begin with
my $GOAL = qr/\A(?!-)[^\s\p{Cc}\p{Cf}:#%\$\\]+\z/;

=item B<read> I<file>

Reads I<file> (a name, which is spelled as L<RdKw::I18N::CodeSets>
says, or a reference to the text itself, which is then called
F<MANIFEST>).  B<RdKw::WwW::GenGenLib::read_manifest> is the same.

=cut

sub _blame
{
	my ($file, $line) = @_;
	# HEY!  %#q is the file name of the faulty
	# file and %d is its lineno.
	diag(__("%#q line %d"), $file, $line);
}

sub read
{
	local ($_, $.);
	# Usually read_manifest delegates to us;
	# so we are them.
	my ($class, $file, %kwds) = @_;
	my $prog = RdKw::WwW::GenGenLib::_getprog(\%kwds, 'read_manifest');
	my $kwds = { prog => $prog };
	my $fh;
	if (ref $file) {
		open $fh, '<', $file
			or die tagmsg($prog => diag(__("cannot open string: %m")));
		$file = 'MANIFEST';
	} else {
		open $fh, '<', to_fs($file, { prog => $prog })
			or die tagmsg($prog => diag(__("cannot open file %q: %m"), $file));
	}

	my (@goal, %goal, $goal);
	while (<$fh>) {
		# HEY!  %#q is the file name of the faulty
		# MANIFEST and %d is its lineno.
		eval { $_ = Encode::decode('UTF-8', $_, Encode::FB_CROAK()); 1 }
			or die _status 0, tagmsg($prog => diag(__("%s: not UTF-8"),
				_blame($file, $.)));
		s/(?:^|[$SP])#.*//so;
		my ($kw, @arg) = /([^$SP]+)/go;
		defined $kw or next;
		# MAKE:, NEED: and WANT: are those, with a colon (and then
		# a name may follow it, without a space)
		if ($kw =~ s/\A(MAKE|NEED|WANT|JUST-NEED|JUST-WANT)://) {
			my $key = $1;
			unshift @arg, $kw if length $kw;
			$kw = $key;
		}
		if ($kw eq 'MAKE') {
			@arg == 1 or die _status 0, tagmsg($prog => diag(__(
				"%s: MAKE takes exactly one goal name"),
				_blame($file, $.)));
			my $name = $arg[0];
			$name =~ /$GOAL/
				or die _status 0, tagmsg($prog => diag(__("%s: bad goal name %q"),
				_blame($file, $.), $name));
			$goal{$name} and die _status 0, tagmsg($prog => diag(__(
				"%s: goal %q is already made"),
				_blame($file, $.), $name));
			push @goal, $goal = $goal{$name}
				= { name => $name, need => [], want => [], line => $. };
			next;
		}
		if ($kw =~ /\A(?:JUST-)?(?:NEED|WANT)\z/) {
			# HEY!  the second %s is the string "NEED" or "WANT"
			$goal or die _status 0, tagmsg($prog => diag(__("%s: %s before any MAKE"),
				_blame($file, $.), $kw));
			# HEY!  the second %s is the string "NEED" or "WANT"
			@arg or die _status 0, tagmsg($prog => diag(__("%s: %s takes a file"
				. " (use # for comments)"), _blame($file, $.), $kw));
			for my $arg (@arg) {
				my $name = eval { subs_deps(undef, $arg,
					{ strict => 1, on_missing => 'croak', prog => undef }) };
				defined $name or do {
					# Prefix subs_deps' error message with our name
					# and a blame line.
					(my $why = $@) =~ s/^/_blame($file, $.) . ": "/gem;
					die _status 0, tagmsg($prog => $why);
				};
				length $name or die _status 0, tagmsg($prog => diag(__("%s: %q is empty"),
					_blame($file, $.), $arg));
				$name =~ /\0/ and die _status 0, tagmsg($prog => diag(__("%s: %q has a NUL in it"),
					_blame($file, $.), $arg));
				(my $key = lc $kw) =~ s/\Ajust-//;
				push @{ $goal->{$key} }, { file => $name, line => $.,
					just => ($kw =~ /\AJUST-/ ? 1 : 0) };
			}
			next;
		}
		die _status 0, tagmsg($prog => diag(__("%s: expected MAKE, NEED, WANT, JUST-NEED or JUST-WANT, not %q"),
			_blame($file, $.), $kw));
	}
	close $fh or die tagmsg($prog => diag(__("cannot read file %q: %m"), $file));
	# HEY!  It's singular because "no mind to think,
	# no will to break, no voice to cry suffering..."
	# (actually, with a verb now, it is substantially
	# more clear.)
	@goal or die _status 0, tagmsg($prog => diag(__("%#q: no goal to make"), $file));
	bless { file => $file, goals => \@goal, goal => \%goal, prog => $prog }, $class;
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
C<< { name, line, need, want } >> hash references, where the latter two
are lists of C<< { file, line, just } >> (C<just> is 1 for a C<JUST-NEED>
or C<JUST-WANT>, and 0 if not).  These are copies.

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
