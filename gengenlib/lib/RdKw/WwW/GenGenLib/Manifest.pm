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

C<MAKE> takes the name of a goal: a letter or digit, then letters,
digits, C<_>, C<->, C<.> and C<+>, and nothing to escape.  A goal is
only made once.

C<NEED> and C<WANT> take one name each, which belongs to the last
C<MAKE> and is unescaped as a spec of B<subs_dep> without definitions
is (see L<RdKw::WwW::GenGenLib/escape_dep>, which writes one): C<${$}>
or C<$$> is a C<$>, C<${U+>I<hex>C<}> is that character (C<${U+0020}>
for a space, C<${U+0023}> for a C<#> that is no comment), and a
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
use RdKw::WwW::GenGenLib qw( subs_dep );

use RdKw::I18N::CodeSets::Functions qw( diag to_fs );
# Use the same gettext domain as our parent GenGenLib.pm.
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

# POSIX white space since [[:space:]] is too broad.
# (This is the same character set used in SiteConf.pm)
my $SP = '\t\n\cK\f\r ';

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
	my ($class, $file) = @_;
	my $fh;
	if (ref $file) {
		open $fh, '<', $file
			or die diag(__("read_manifest: cannot open string: %m")) . "\n";
		$file = 'MANIFEST';
	} else {
		open $fh, '<', to_fs($file, { prog => 'read_manifest' })
			or die diag(__("read_manifest: cannot open file %q: %m"), $file) . "\n";
	}

	my (@goal, %goal, $goal);
	while (<$fh>) {
		# HEY!  %#q is the file name of the faulty
		# MANIFEST and %d is its lineno.
		eval { $_ = Encode::decode('UTF-8', $_, Encode::FB_CROAK()); 1 }
			or die diag(__("read_manifest: %s: not UTF-8"),
				_blame($file, $.)) . "\n";
		s/(?:^|[$SP])#.*//so;
		my ($kw, @arg) = /([^$SP]+)/go;
		defined $kw or next;
		if ($kw eq 'MAKE') {
			@arg == 1 or die diag(__("read_manifest: %s: "
				. "MAKE takes exactly one goal name"),
				_blame($file, $.)) . "\n";
			my $name = $arg[0];
			$name =~ /\A[A-Za-z0-9][-\w.+]*\z/
				or die diag(__("read_manifest: %s: bad goal name %q"),
				_blame($file, $.), $name) . "\n";
			$goal{$name} and die diag(__("read_manifest: %s: "
				. "goal %q is already made"),
				_blame($file, $.), $name) . "\n";
			push @goal, $goal = $goal{$name}
				= { name => $name, need => [], want => [], line => $. };
			next;
		}
		if ($kw eq 'NEED' or $kw eq 'WANT') {
			# HEY!  the second %s is the string "NEED" or "WANT"
			$goal or die diag(__("read_manifest: %s: %s before any MAKE"),
				_blame($file, $.), $kw) . "\n";
			# HEY!  the second %s is the string "NEED" or "WANT"
			@arg == 1 or die diag(__("read_manifest: %s: %s takes exactly one file"
				. " (use # for comments)"), _blame($file, $.), $kw) . "\n";
			my $name = eval { subs_dep(undef, $arg[0],
				strict => 1, on_missing => 'croak') };
			defined $name or do {
				(my $why = $@) =~ s/\A\w+: //;
				die diag(__("read_manifest: %s: %s"), _blame($file, $.), $why);
			};
			length $name or die diag(__("read_manifest: %s: %q is no name"),
				_blame($file, $.), $arg[0]) . "\n";
			$name =~ /\0/ and die diag(__("read_manifest: %s: %q has a NUL in it"),
				_blame($file, $.), $arg[0]) . "\n";
			push @{ $goal->{lc $kw} }, { file => $name, line => $. };
			next;
		}
		die diag(__("read_manifest: %s: expected MAKE, NEED or WANT, not %q"),
			_blame($file, $.), $kw) . "\n";
	}
	close $fh or die diag(__("read_manifest: cannot read file %q: %m"), $file) . "\n";
	# HEY!  I (ethan/rc) didn't write this message.
	# I'm frankly a bit surprised Claude made it
	# a question... anyways go wild at it i don't
	# really have any idea lol :v
	@goal or die diag(__("read_manifest: %q: no goals; what should I make?"), $file) . "\n";
	bless { file => $file, goals => \@goal, goal => \%goal }, $class;
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
C<WANT>s, in order, as they were in the manifest -- unescaped.  A
goal that is not there is an error.

=cut

sub _goal
{
	my ($self, $name) = @_;
	defined $name or return $self->{goals}[0];
	$self->{goal}{$name} or die diag(__("read_manifest: %q: no goal %q"),
		$self->{file}, $name) . "\n";
}

sub needed { map { $_->{file} } @{ $_[0]->_goal($_[1])->{need} } }

sub wanted { map { $_->{file} } @{ $_[0]->_goal($_[1])->{want} } }

=item B<goals>

All goals, in order, with the lines they were on: a list of
C<< { name, line, need, want } >> hash references, where the latter two
are lists of C<< { file, line } >>.  These are copies.

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
