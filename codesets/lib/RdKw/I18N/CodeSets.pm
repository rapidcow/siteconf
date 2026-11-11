package RdKw::I18N::CodeSets;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

=head1 NAME

I18N::CodeSets - what the process speaks, and to whom

=head1 SYNOPSIS

    use RdKw::I18N::CodeSets;
    my $CS = 'RdKw::I18N::CodeSets';

    # -C diag:ascii -C console:locale -C argv:UTF-8 -C filesys
    Getopt::Long::GetOptions( 'C=s@' => \my @C );
    my $cs = eval { $CS->parse(@C) } or die "E: codeset error: $@";
    $CS->locale($cs);

    # elsewhere
    my $cs = $CS->locale;
    $cs->initstd( stderr => Encode::FB_PERLQQ() );
    $cs->un_argv;
    open my $fh, '<', $cs->to_fs($file)
        or die $cs->diag("cannot open file %q: %s\n", $file, "$!");

=head1 DESCRIPTION

Everything in here is a character string; a code set says how it is
spelled where it leaves the process, and where it comes back from,
for each of these categories:

=over

=item B<stdin>, B<stdout>, B<stderr>

The standard files (L</initstd>).

=item B<argv>

The arguments (L</un_argv>, L</to_argv>).

=item B<env>

The environment (L</getenv>, L</setenv>, L</unsetenv>).

=item B<filesys>

File names (L</to_fs>, L</un_fs>), as they are passed to and returned
by the system.

=back

A category that is not set is spelled as L<Encode::Locale> says:
C<console_in> for B<stdin>, C<console_out> for B<stdout> and
B<stderr>, C<locale_fs> for B<filesys>, and C<locale> for the rest.
The pseudo-encoding C<locale> means exactly that, for whichever
category it is given to.

When setting, there are also the pseudo-categories B<console> (all of
the standard files), B<console_in> (B<stdin>) and B<console_out>
(B<stdout> and B<stderr>); and B<diag>, which is not a code set but a
mode, C<unicode> or C<ascii>, for what we say (L</diag_mode>).

What cannot be spelled is an error, never a guess.

=cut

use Carp ();
use Encode ();
use Encode::Locale ();
use PerlIO::encoding ();

# category => the Encode::Locale alias that `locale' means for it
my %LOCALE = (
	stdin   => 'console_in',
	stdout  => 'console_out',
	stderr  => 'console_out',
	argv    => 'locale',
	env     => 'locale',
	filesys => 'locale_fs',
);
my @CATEGORIES = qw( stdin stdout stderr argv env filesys );

# pseudo-category => what it sets
my %PSEUDO = (
	console     => [qw( stdin stdout stderr )],
	console_in  => [qw( stdin )],
	console_out => [qw( stdout stderr )],
);

my %STD = ( stdin => \*STDIN, stdout => \*STDOUT, stderr => \*STDERR );

my $CHECK = Encode::FB_CROAK() | Encode::LEAVE_SRC();

my $LOCALE;

=head1 METHODS

=over

=item I<CLASS>->B<new>( I<category> => I<encoding>, ... )

A new set of code sets: I<encoding> is anything L<Encode> knows by
name, or C<locale>; B<diag> is C<unicode> or C<ascii> instead.  They
are applied in order, so that a later one overrides what came before
(a pseudo-category, the categories it sets).  Dies if a category or
an encoding is unknown.

=cut

sub new
{
	my ($class, @pairs) = @_;
	Carp::croak('new: odd number of arguments') if @pairs % 2;
	my $self = bless {}, $class;
	while (my ($name, $enc) = splice @pairs, 0, 2) {
		$self->_set($name, $enc);
	}
	$self;
}

=item I<CLASS>->B<parse>( I<spec>, ... )

As L</new>, from what C<-C> was told: each I<spec> is a
I<category>B<:>I<encoding>, or a I<category> alone, which means
C<UTF-8> (and, for B<diag>, C<unicode>).  They are applied in order,
so that a later one overrides what came before:
C<-C console:locale -C stderr:ascii>.  Dies (with a newline, so that
the message can be said again as it is) if a I<spec> makes no sense.

=cut

sub parse
{
	my ($class, @spec) = @_;
	my @pairs;
	for my $spec (@spec) {
		defined $spec or die "undefined codeset\n";
		my ($name, $enc) = $spec =~ /\A([^:]*)(?::(.*))?\z/s;
		length $name or die "no category in codeset @{[ _qq_ascii($spec) ]}\n";
		$enc = $name eq 'diag' ? 'unicode' : 'UTF-8' unless defined $enc;
		push @pairs, $name, $enc;
	}
	$class->new(@pairs);
}

sub _set
{
	my ($self, $name, $enc) = @_;
	defined $name or die "undefined category\n";
	if ($name eq 'diag') {
		$self->diag_mode($enc);
	}
	elsif ($PSEUDO{$name}) {
		$self->_set($_, $enc) for @{$PSEUDO{$name}};
	}
	elsif ($LOCALE{$name}) {
		$self->$name($enc);
	}
	else {
		die "unknown category @{[ _qq_ascii($name) ]}\n";
	}
}

=item I<CLASS>->B<locale>([ I<codesets> ])

The process's code sets, which are those of a plain L</new> until
they are set.  Returns them (the new ones, if set).

=cut

sub locale
{
	my $class = shift;
	if (@_) {
		my ($cs) = @_;
		Carp::croak('locale: not a ' . __PACKAGE__)
			unless ref $cs && eval { $cs->isa(__PACKAGE__) };
		$LOCALE = $cs;
	}
	$LOCALE = $class->new unless defined $LOCALE;
	$LOCALE;
}

=item I<cs>->B<stdin>([ I<encoding> ])

=item I<cs>->B<stdout>([ I<encoding> ])

=item I<cs>->B<stderr>([ I<encoding> ])

=item I<cs>->B<argv>([ I<encoding> ])

=item I<cs>->B<env>([ I<encoding> ])

=item I<cs>->B<filesys>([ I<encoding> ])

The code set of a category, by its canonical name in L<Encode>
(C<UTF-8> is C<utf-8-strict>), or undef if it is not set; or, given
an I<encoding>, set it (undef unsets it).  What is got means the same
to every category, C<locale> having been resolved already, so that
one may be set from another:

    $cs->stdout( $cs->argv ) if !defined $cs->stdout;

=item I<cs>->B<console>([ I<encoding> ])

=item I<cs>->B<console_in>([ I<encoding> ])

=item I<cs>->B<console_out>([ I<encoding> ])

Sets the categories of the pseudo-category; or gets their code set,
if they all have the same one (otherwise undef).

=cut

for my $name (@CATEGORIES) {
	no strict 'refs';
	*$name = sub {
		my $self = shift;
		if (@_) {
			my ($enc) = @_;
			if (defined $enc) {
				$enc = $LOCALE{$name} if $enc eq 'locale';
				my $obj = Encode::find_encoding($enc)
					or die "unknown encoding @{[ _qq_ascii($enc) ]}"
						. " for $name\n";
				$self->{$name} = $obj->name;
			}
			else {
				delete $self->{$name};
			}
		}
		$self->{$name};
	};
}

for my $name (keys %PSEUDO) {
	no strict 'refs';
	*$name = sub {
		my $self = shift;
		my @of = @{$PSEUDO{$name}};
		$self->$_(@_) for @_ ? @of : ();
		my ($enc, @rest) = map { $self->$_ } @of;
		for (@rest) {
			return undef unless defined $enc && defined $_ && $enc eq $_;
		}
		$enc;
	};
}

# What a category is spelled in, set or not
sub _encoding
{
	my ($self, $name) = @_;
	defined $self->{$name} ? $self->{$name}
		: Encode::find_encoding($LOCALE{$name})->name;
}

# ... as people know it
sub _say_encoding
{
	my ($self, $name) = @_;
	my $obj = Encode::find_encoding($self->_encoding($name));
	$obj->mime_name || $obj->name;
}

# What Encode said went wrong, without where
sub _encode_error
{
	my ($err) = @_;
	$err =~ s/ at \S+ line \d+\.?\n\z//;
	$err;
}

=item I<cs>->B<diag_mode>([ I<mode> ])

How we say things (L</diag_name>): C<unicode>, or C<ascii>; or,
given a I<mode>, set it (undef unsets it).  If it is not set, it is
C<unicode>, unless B<stderr> is spelled in ASCII, in which case it is
C<ascii>; which is only a default, as this is for whatever we say,
wherever we say it.

=cut

sub diag_mode
{
	my $self = shift;
	if (@_) {
		my ($mode) = @_;
		if (defined $mode) {
			$mode eq 'unicode' || $mode eq 'ascii'
				or die "unknown diag mode @{[ _qq_ascii($mode) ]}"
					. " (unicode or ascii)\n";
			$self->{diag} = $mode;
		}
		else {
			delete $self->{diag};
		}
	}
	return $self->{diag} if defined $self->{diag};
	$self->_encoding('stderr') eq 'ascii' ? 'ascii' : 'unicode';
}

=item I<cs>->B<initstd>([ I<file> => I<fallback>, ... ])

Spells the standard files (B<stdin>, B<stdout> and B<stderr>) in
their code sets, in place of whatever layers they had.  A I<fallback>
is what L<PerlIO::encoding> does with what cannot be spelled
(C<$PerlIO::encoding::fallback>, which is left as it is for the rest).

=cut

sub initstd
{
	my ($self, %fallback) = @_;
	for (sort keys %fallback) {
		Carp::croak("initstd: not a standard file: $_") unless $STD{$_};
	}
	for my $name (qw( stdin stdout stderr )) {
		my $enc = $self->_encoding($name);
		local $PerlIO::encoding::fallback = $fallback{$name}
			if exists $fallback{$name};
		binmode $STD{$name}, ":raw:encoding($enc)"
			or die "cannot spell $name in $enc: $!\n";
	}
	return;
}

=item I<cs>->B<to_fs>( I<name>[, I<who>] )

=item I<cs>->B<un_fs>( I<bytes>[, I<who>] )

I<name>, a character string, as the file system spells it
(B<filesys>), or the other way around.  Dies (saying I<who> did it,
if given) if that cannot be done: we do not make up names for files.

=cut

sub to_fs
{
	my ($self, $name, $who) = @_;
	my $fs = eval { Encode::encode($self->_encoding('filesys'), $name, $CHECK) };
	defined $fs or die +(defined $who ? "$who: " : "")
		. "cannot encode @{[ _qq_ascii($name) ]}"
		. " in @{[ $self->_say_encoding('filesys') ]}\n";
	$fs;
}

sub un_fs
{
	my ($self, $fs, $who) = @_;
	my $name = eval { Encode::decode($self->_encoding('filesys'), $fs, $CHECK) };
	defined $name or die +(defined $who ? "$who: " : "")
		. "cannot decode @{[ _qq_ascii($fs) ]}"
		. " in @{[ $self->_say_encoding('filesys') ]}\n";
	$name;
}

=item I<cs>->B<un_argv>( I<bytes>, ...[, { start => I<n> }] )

=item I<cs>->B<to_argv>( I<arg>, ...[, { start => I<n> }] )

The arguments, decoded (as B<argv>) or encoded; the first one, in
scalar context.  Dies, saying which one could not be, if one cannot
be: B<argv> I<n> is the first (C<0> unless given, as for C<$0>),
and so on.

    my $prog = $cs->un_argv($0);
    my @args = $cs->un_argv(@ARGV, { start => 1 });

=cut

sub un_argv
{
	my $self = shift;
	$self->_argv(\&Encode::decode, decode => @_);
}

sub to_argv
{
	my $self = shift;
	$self->_argv(\&Encode::encode, encode => @_);
}

sub _argv
{
	my ($self, $code, $what, @args) = @_;
	my %opt = @args && ref $args[-1] eq 'HASH' ? %{ pop @args } : ();
	my $start = exists $opt{start} ? delete $opt{start} : 0;
	Carp::croak("${what}_argv: unknown option $_") for sort keys %opt;
	Carp::croak("${what}_argv: start is not a number")
		unless defined $start && $start =~ /\A[0-9]+\z/;
	my $enc = $self->_encoding('argv');
	my @new;
	for my $i (0 .. $#args) {
		my $new = eval { $code->($enc, $args[$i], $CHECK) };
		defined $new or die "cannot $what argv @{[ $start + $i ]}: "
			. (defined $args[$i] ? _encode_error($@) : 'undefined') . "\n";
		push @new, $new;
	}
	wantarray ? @new : $new[0];
}

=item I<cs>->B<decode_argv>

=item I<cs>->B<encode_argv>

Decodes C<@ARGV> (as B<argv>), or encodes it; or dies, leaving it as
it was, if one argument cannot be.

=cut

sub decode_argv
{
	my $self = shift;
	@ARGV = $self->un_argv(@ARGV, { start => 1 });
	return;
}

sub encode_argv
{
	my $self = shift;
	@ARGV = $self->to_argv(@ARGV, { start => 1 });
	return;
}

=item I<cs>->B<getenv>( I<name>, ... )

The values of the environment variables (B<env>) by those names,
undef for each that is not set; the first one, in scalar context.
Dies if a name or a value cannot be spelled.

=item I<cs>->B<setenv>( I<name> => I<value>, ... )

Sets the environment variables; a I<value> of undef unsets it.

=item I<cs>->B<unsetenv>( I<name>, ... )

Unsets them.

=cut

sub getenv
{
	my ($self, @names) = @_;
	my $enc = $self->_encoding('env');
	my @values;
	for my $name (@names) {
		my $key = $self->_env_key($enc, $name);
		my $value = $ENV{$key};
		if (defined $value) {
			my $chars = eval { Encode::decode($enc, $value, $CHECK) };
			defined $chars or die "cannot decode environment variable"
				. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}\n";
			$value = $chars;
		}
		push @values, $value;
	}
	wantarray ? @values : $values[0];
}

sub setenv
{
	my ($self, @pairs) = @_;
	Carp::croak('setenv: odd number of arguments') if @pairs % 2;
	my $enc = $self->_encoding('env');
	my %set;
	while (my ($name, $value) = splice @pairs, 0, 2) {
		my $key = $self->_env_key($enc, $name);
		if (defined $value) {
			my $bytes = eval { Encode::encode($enc, $value, $CHECK) };
			defined $bytes or die "cannot encode the value of"
				. " environment variable @{[ _qq_ascii($name) ]}"
				. " in @{[ $self->_say_encoding('env') ]}\n";
			$value = $bytes;
		}
		$set{$key} = $value;
	}
	# All or none
	while (my ($key, $value) = each %set) {
		if (defined $value) { $ENV{$key} = $value }
		else { delete $ENV{$key} }
	}
	return;
}

sub unsetenv
{
	my ($self, @names) = @_;
	$self->setenv(map { $_ => undef } @names);
	return;
}

sub _env_key
{
	my ($self, $enc, $name) = @_;
	Carp::croak('undefined environment variable name') unless defined $name;
	my $key = eval { Encode::encode($enc, $name, $CHECK) };
	defined $key or die "cannot encode environment variable name"
		. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}\n";
	$key;
}

=item I<cs>->B<diag_name>( I<name> )

I<name>, for people: C<`name'> if it is all printable ASCII, and
quoted as Perl would otherwise, with escapes (C<\n>, C<\x{a0}>) for
what would not show.  Under C<diag_mode> C<ascii>, that is all but
printable ASCII; under C<unicode>, it is only controls, separators
and the like (C<\p{C}> and C<\p{Z}>, but for the ASCII space).

=cut

sub diag_name
{
	my ($self, $name) = @_;
	return 'undef' unless defined $name;
	return "`$name'" if $name =~ /\A[\x20-\x7e]*\z/;
	$self->diag_mode eq 'ascii' ? _qq_ascii($name) : _qq_unicode($name);
}

=item I<cs>->B<diag>( I<format>, I<arg>, ... )

The I<format>, with each C<%q> replaced by the L</diag_name> of its
I<arg>, each C<%s> by its I<arg> as it is, and each C<%%> by C<%>.
Dies on any other C<%>.

=cut

sub diag
{
	my ($self, $format, @args) = @_;
	my $out = '';
	pos $format = 0;
	while ($format =~ /\G([^%]*)%(.?)/gcs) {
		my ($text, $conv) = ($1, $2);
		$out .= $text;
		if ($conv eq '%') {
			$out .= '%';
		}
		elsif ($conv eq 's' || $conv eq 'q') {
			Carp::croak('diag: missing argument for %' . $conv) unless @args;
			my $arg = shift @args;
			$out .= $conv eq 'q' ? $self->diag_name($arg)
				: defined $arg ? $arg : '';
		}
		else {
			Carp::croak("diag: unknown conversion %$conv");
		}
	}
	$out . substr($format, pos $format);
}

# "..." as Perl would quote it, with what is not printable ASCII
# escaped.  (Data::Dumper Useqq, but with \x{...} for every code
# point that is no named escape, rather than octal for some of them:
# the same string comes out the same, however it is stored.)
my %NAMED = ("\t" => '\t', "\n" => '\n', "\r" => '\r', "\f" => '\f',
	"\b" => '\b', "\a" => '\a', "\e" => '\e');

sub _qq_char
{
	my ($c) = @_;
	return "\\$c" if $c =~ /["\\\$\@]/;
	return $NAMED{$c} if exists $NAMED{$c};
	sprintf '\x{%x}', ord $c;
}

sub _qq_ascii
{
	my ($s) = @_;
	(my $q = $s) =~ s/([^\x20-\x7e]|["\\\$\@])/_qq_char($1)/ge;
	qq{"$q"};
}

# Ditto, but with only what would not show escaped
sub _qq_unicode
{
	my ($s) = @_;
	(my $q = $s) =~ s/((?! )[\p{C}\p{Z}]|["\\\$\@])/_qq_char($1)/ge;
	qq{"$q"};
}

=back

=head1 SEE ALSO

L<Encode>, L<Encode::Locale>, L<PerlIO::encoding>

=cut

1;
