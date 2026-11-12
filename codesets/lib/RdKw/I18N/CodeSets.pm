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

What cannot be spelled is an error, not mangled.

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

# (our, so that it may be local()ized: local $RdKw::I18N::CodeSets::LOCALE)
our $LOCALE;

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
They are C<$RdKw::I18N::CodeSets::LOCALE>, which may be set for a
while, and no longer:

    local $RdKw::I18N::CodeSets::LOCALE = $CS->new(diag => 'ascii');

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

=item I<cs>->B<to_fs>( I<name>, ...[, { I<option> => I<value>, ... }] )

=item I<cs>->B<un_fs>( I<bytes>, ...[, { I<option> => I<value>, ... }] )

The I<name>s, character strings, as the file system spells them
(B<filesys>), or the other way around; the first one, in scalar
context.  Dies if one cannot be: we do not make up names for files,
unless told to.  The options are:

=over

=item B<prog> => I<prog>

Who could not, said before the error (C<prog: cannot encode ...>).

=item B<check> => I<check>

What to do with what cannot be spelled, as L<Encode> takes it
(C<FB_CROAK>).  The source is never modified, whatever it says.

=back

    open my $fh, '<', $cs->to_fs($file, { prog => $prog }) or die ...;
    my @names = $cs->un_fs(readdir $dh);

=cut

sub to_fs
{
	my $self = shift;
	$self->_fs(\&Encode::encode, encode => to_fs => @_);
}

sub un_fs
{
	my $self = shift;
	$self->_fs(\&Encode::decode, decode => un_fs => @_);
}

sub _fs
{
	my ($self, $code, $what, $sub, @names) = @_;
	my $opt = _opt($sub => \@names, qw( prog check ));
	my $enc = $self->_encoding('filesys');
	my @new;
	for my $name (@names) {
		my ($new) = _code($code, $enc, $name, $opt->{check});
		defined $new or die +(defined $opt->{prog} ? "$opt->{prog}: " : '')
			. "cannot $what @{[ _qq_ascii($name) ]}"
			. " in @{[ $self->_say_encoding('filesys') ]}\n";
		push @new, $new;
	}
	wantarray ? @new : $new[0];
}

=item I<cs>->B<un_argv>( I<bytes>, ...[, { I<option> => I<value>, ... }] )

=item I<cs>->B<to_argv>( I<arg>, ...[, { I<option> => I<value>, ... }] )

The arguments, decoded (as B<argv>) or encoded; the first one, in
scalar context.  Dies, saying which one could not be, if one cannot
be: B<argv> I<n> is the first (C<0> unless given, as for C<$0>),
and so on.  The options are:

=over

=item B<start> => I<n>

What the first argument is called (C<0>).

=item B<check> => I<check>

What to do with what cannot be spelled, as L<Encode> takes it
(C<FB_CROAK>).

=back

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
	my $opt = _opt("${what}_argv" => \@args, qw( start check ));
	my $start = exists $opt->{start} ? $opt->{start} : 0;
	Carp::croak("${what}_argv: start is not a number")
		unless defined $start && $start =~ /\A[0-9]+\z/;
	my $enc = $self->_encoding('argv');
	my @new;
	for my $i (0 .. $#args) {
		my ($new, $err) = _code($code, $enc, $args[$i], $opt->{check});
		defined $new or die "cannot $what argv @{[ $start + $i ]}: $err\n";
		push @new, $new;
	}
	wantarray ? @new : $new[0];
}

=item I<cs>->B<decode_argv>([ I<check> ])

=item I<cs>->B<encode_argv>([ I<check> ])

Decodes C<@ARGV> (as B<argv>), or encodes it, as B<un_argv> and
B<to_argv> would from B<argv> C<1>; or dies, leaving it as it was, if
one argument cannot be.  (As L<Encode::Locale/decode_argv>.)

=cut

sub decode_argv
{
	my ($self, $check) = @_;
	@ARGV = $self->un_argv(@ARGV, { start => 1, check => $check });
	return;
}

sub encode_argv
{
	my ($self, $check) = @_;
	@ARGV = $self->to_argv(@ARGV, { start => 1, check => $check });
	return;
}

=item I<cs>->B<getenv>( I<name>, ...[, { check => I<check> }] )

The values of the environment variables (B<env>) by those names,
undef for each that is not set; the first one, in scalar context.
Dies if a name or a value cannot be spelled.  A I<check> is for the
values; a name is always spelled as it is, or not at all.

=item I<cs>->B<setenv>( I<name> => I<value>, ...[, { check => I<check> }] )

Sets the environment variables; a I<value> of undef unsets it.  Sets
none of them if one cannot be spelled.

=item I<cs>->B<unsetenv>( I<name>, ... )

Unsets them.

=cut

sub getenv
{
	my ($self, @names) = @_;
	my $opt = _opt(getenv => \@names, 'check');
	my $enc = $self->_encoding('env');
	my @values;
	for my $name (@names) {
		my $value = $ENV{ $self->_env_key($enc, $name) };
		if (defined $value) {
			($value) = _code(\&Encode::decode, $enc, $value, $opt->{check});
			defined $value or die "cannot decode environment variable"
				. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}\n";
		}
		push @values, $value;
	}
	wantarray ? @values : $values[0];
}

sub setenv
{
	my ($self, @pairs) = @_;
	my $opt = _opt(setenv => \@pairs, 'check');
	Carp::croak('setenv: odd number of arguments') if @pairs % 2;
	my $enc = $self->_encoding('env');
	my %set;
	while (my ($name, $value) = splice @pairs, 0, 2) {
		my $key = $self->_env_key($enc, $name);
		if (defined $value) {
			my ($bytes) = _code(\&Encode::encode, $enc, $value, $opt->{check});
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
	my ($key) = _code(\&Encode::encode, $enc, $name);
	defined $key or die "cannot encode environment variable name"
		. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}\n";
	$key;
}

# The options at the end of a list, { name => value }, by these names
sub _opt
{
	my ($who, $args, @names) = @_;
	return {} unless @$args && ref $args->[-1] eq 'HASH';
	my $opt = pop @$args;
	my %ok = map { $_ => 1 } @names;
	for (sort keys %$opt) {
		Carp::croak("$who: unknown option $_") unless $ok{$_};
	}
	$opt;
}

# What Encode makes of the source (which it is not given to modify),
# or undef and why not
sub _code
{
	my ($code, $enc, $src, $check) = @_;
	$check = $CHECK unless defined $check;
	my $copy = $src;
	my $res = eval { $code->($enc, $copy, $check) };
	return ($res) if defined $res;
	(undef, $@ ne '' ? _encode_error($@) : 'undefined');
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
# (This is inspired by Python str.isprintable())
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
