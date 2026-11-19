package RdKw::I18N::CodeSets;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

I18N::CodeSets - character encoding context and parser

=head1 SYNOPSIS

    use RdKw::I18N::CodeSets;
    my $CS = 'RdKw::I18N::CodeSets';

    # SITECONF_CODESETS=filesys:UTF-8,console:ascii, and then
    # -C diag:ascii -C console:locale -C argv:UTF-8 -C filesys ...
    my $cs = $CS->new;
    $cs->parse_from_env('SITECONF_CODESETS', prog => $0);
    my $offset = $cs->parse_from_argv(\@ARGV, prog => $0);
    $CS->locale($cs);

    # elsewhere
    my $cs = $CS->locale;
    $cs->initstd( stderr => Encode::FB_PERLQQ() );
    @ARGV = $cs->un_argv(@ARGV, { start => 1 + $offset });
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
Setting a category to the pseudo-encoding C<locale> unsets it, so
C<locale> alone (B<all:locale>) resets everything to a plain L</new>.
The locale is looked up when the category is used, not when it is set.

When setting, there are also the pseudo-categories B<console> (all of
the standard files), B<console_in> (B<stdin>), B<console_out>
(B<stdout> and B<stderr>) and B<all> (every category, and B<diag>
follows B<stderr> again); and B<diag>, which is not a code set but a
mode, C<unicode> or C<ascii>, for what we say (L</diag_mode>).  An
B<stderr> set to ASCII (by any of its names) makes B<diag> follow it
again, and so C<ascii>, until it is told otherwise.  C<0> is short
for C<ascii>, and C<1> for C<UTF-8> (or, for B<diag>, C<unicode>).

What cannot be spelled is an error, not mangled; but what we say is
said so that it can be (L</diag>).

=cut

use Carp ();
use Encode ();
use Encode::Locale ();
use PerlIO::encoding ();

sub _status { $! = 0; $? = shift; @_; }

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

# What 0 and 1 are short for
my %NUMBER = ( 0 => 'ascii', 1 => 'UTF-8' );
my %DIAG_NUMBER = ( 0 => 'ascii', 1 => 'unicode' );

my $CHECK = Encode::FB_CROAK() | Encode::LEAVE_SRC();

# (our, so that it may be local()ized: local $RdKw::I18N::CodeSets::LOCALE)
our $LOCALE;

=head1 METHODS

=over

=item I<CLASS>->B<new>( I<category> => I<encoding>, ... )

=item I<cs>->B<new>( I<category> => I<encoding>, ... )

A new set of code sets: I<encoding> is anything L<Encode> knows by
name, or C<locale>; B<diag> is C<unicode> or C<ascii> instead.  They
are applied in order, so that a later one overrides what came before
(a pseudo-category, the categories it sets).  Dies if a category or
an encoding is unknown.  Of a I<cs>, they are applied to a copy of
it, which is returned; I<cs> itself is left as it was.

=cut

sub new
{
	my ($proto, @pairs) = @_;
	Carp::croak('new: odd number of arguments') if @pairs % 2;
	my $self = ref $proto ? bless({ %$proto }, ref $proto) : bless({}, $proto);
	while (my ($name, $enc) = splice @pairs, 0, 2) {
		$self->_set($name, $enc);
	}
	$self;
}

=item I<cs>->B<parse>( I<spec>, ...[, { prog => I<prog> }] )

Sets I<cs> itself from what C<-C> was told, and returns it: each
I<spec> is a I<category>B<:>I<encoding>; a I<category> alone, which means
C<UTF-8> (and, for B<diag>, C<unicode>); or an I<encoding> alone,
which means B<all:>I<encoding>.  A I<spec> may also be several, split
by commas.  They are applied in order, so that a later one overrides
what came before: C<-C console:locale -C stderr:ascii>, or the same as
C<console:locale,stderr:ascii>.  Dies (with a newline, so that the
message can be said again as it is) if a I<spec> makes no sense, and
leaves I<cs> as it was; a I<prog> is who says so, before the error
(C<prog: unknown category ...>), as it is for every method here that
takes one.  There is no parse of a I<CLASS>: that is a L</new> one.

A I<spec> may also be another I<cs>, or the hash that L</all> returns,
which sets every category and B<diag> to what it says, so that one
I<cs> can be updated from another:

    $cs->parse($other);
    $cs->parse($other->all);    # the same

The hash is given by reference.  As a list (C<%{ $other-E<gt>all }>)
its keys and values would each be read as a I<spec> of their own.

    my $cs = $CS->new->parse('filesys:UTF-8,console:ascii');

    # SITECONF_CODESETS=0, =UTF-8, =filesys:UTF-8,console:ascii, ...
    $cs->parse($ENV{SITECONF_CODESETS})
        if exists $ENV{SITECONF_CODESETS};

(Which is L</parse_from_env>, but for saying what first.)

=cut

sub parse
{
	my ($self, @spec) = @_;
	Carp::croak('parse: not of an object') unless ref $self;
	# Another of us is what its all() returns.
	@spec = map { ref $_ && eval { $_->isa(__PACKAGE__) } ? $_->all : $_ } @spec;
	# A trailing hash is the options, unless it is what all() returns.
	my @last = @spec && _is_all($spec[-1]) ? pop @spec : ();
	my $prog = _who(_opt(parse => \@spec, 'prog'));
	push @spec, @last;
	my @pairs;
	for my $spec (map { defined $_ && !ref $_ ? split(/,/, $_) : $_ } @spec) {
		defined $spec or die _status 0, "${prog}undefined codeset\n";
		if (ref $spec) {
			ref $spec eq 'HASH' or die _status 0, "${prog}not a codeset: $spec\n";
			my %all = %$spec;
			# (diag last: setting stderr to ASCII would reset it)
			for my $name (@CATEGORIES, 'diag') {
				push @pairs, $name, delete $all{$name} if exists $all{$name};
			}
			for (sort keys %all) {
				die _status 0, "${prog}unknown category @{[ _qq_ascii($_) ]}\n";
			}
			next;
		}
		my ($name, $enc) = $spec =~ /\A([^:]*)(?::(.*))?\z/s;
		length $name or die _status 0, "${prog}no category in codeset @{[ _qq_ascii($spec) ]}\n";
		if (!defined $enc && !_is_category($name)) {
			_is_encoding($name)
				or die _status 0, "${prog}unknown category or encoding @{[ _qq_ascii($name) ]}\n";
			($name, $enc) = (all => $name);
		}
		$enc = $name eq 'diag' ? 'unicode' : 'UTF-8' unless defined $enc;
		push @pairs, $name, $enc;
	}
	# (to a copy first, so that we are as we were if one is bad)
	my $new = eval { $self->new(@pairs) } or die _status 0, "$prog$@";
	%$self = %$new;
	$self;
}

=item I<cs>->B<parse_from_env>( I<name>[, prog => I<prog> ] )

As L</parse>, from what the environment variable I<name> says, if it
is set; I<cs> is returned.  Dies (and leaves I<cs> as it was) if it
makes no sense, saying I<prog> and I<name> first:

    $cs->parse_from_env('SITECONF_CODESETS', prog => 'E');
    # E: SITECONF_CODESETS: unknown category or encoding "nope"

=item I<cs>->B<parse_from_argv>( I<array>[, prog => I<prog> ] )

As L</parse>, from the C<-C> I<spec>s (or C<-C>I<spec>, glued) that
I<array> (C<\@ARGV>) starts with.  They
are taken off I<array>; the rest is left as it was, from the first
argument that is not one on (C<--> too, and C<-iC0>: a C<-C> after
anything else is no longer ours).  Returns how many arguments were
taken off, so that the rest can be counted from where they were:

    my $cs = $CS->new;
    $cs->parse_from_env('SITECONF_CODESETS', prog => 'E');
    my $offset = $cs->parse_from_argv(\@ARGV, prog => 'E');
    @ARGV = $cs->un_argv(@ARGV, { start => 1 + $offset });

The arguments are bytes still, as they must be: what they say is how
to read them.  (Being options, they are ASCII.)  Dies (and leaves
I<cs> and I<array> as they were) if one makes no sense, or C<-C> is
the last argument, saying I<prog> and which argument it is, counting
from 1 (C<$0> being 0):

    # E: -C (argv 2): unknown category or encoding "nope"

=cut

sub parse_from_env
{
	my ($self, $name, @opt) = @_;
	my $prog = _prog_opt(parse_from_env => $self, \@opt);
	Carp::croak('parse_from_env: undefined environment variable name') unless defined $name;
	return $self unless exists $ENV{$name};
	eval { $self->parse($ENV{$name}); 1 } or die _status 0, "$prog$name: $@";
	$self;
}

sub parse_from_argv
{
	my ($self, $argv, @opt) = @_;
	my $prog = _prog_opt(parse_from_argv => $self, \@opt);
	Carp::croak('parse_from_argv: not an array reference') unless ref $argv eq 'ARRAY';
	# (a copy, so that we are as we were if a later one is bad)
	my ($new, $n) = ($self->new, 0);
	while ($n < @$argv && defined $argv->[$n] && $argv->[$n] =~ /\A-C(.*)\z/s) {
		my $spec = $1;
		unless (length $spec) {
			++$n < @$argv or die _status 0, "$prog-C (argv $n): no codeset after it\n";
			$spec = $argv->[$n];
		}
		eval { $new->parse($spec); 1 } or die _status 0, "$prog-C (argv @{[ $n + 1 ]}): $@";
		$n++;
	}
	splice @$argv, 0, $n;
	%$self = %$new;
	$n;
}

# prog => ..., the one option of parse_from_*: "prog: ", or ''
sub _prog_opt
{
	my ($who, $self, $opt) = @_;
	Carp::croak("$who: not of an object") unless ref $self;
	Carp::croak("$who: odd number of options") if @$opt % 2;
	my %opt = @$opt;
	for (sort keys %opt) {
		Carp::croak("$who: unknown option $_") unless $_ eq 'prog';
	}
	defined $opt{prog} ? "$opt{prog}: " : '';
}

sub _is_category
{
	my ($name) = @_;
	$name eq 'diag' || $name eq 'all' || $PSEUDO{$name} || $LOCALE{$name};
}

# Whether it is a hash as all() returns one (and not parse's options)
sub _is_all
{
	my ($spec) = @_;
	ref $spec eq 'HASH' && grep { $LOCALE{$_} || $_ eq 'diag' } keys %$spec;
}

sub _is_encoding
{
	my ($enc) = @_;
	exists $NUMBER{$enc} || $enc eq 'locale' || Encode::find_encoding($enc);
}

sub _set
{
	my ($self, $name, $enc) = @_;
	defined $name or die _status 0, "undefined category\n";
	if ($name eq 'diag') {
		$enc = $DIAG_NUMBER{$enc} if defined $enc && exists $DIAG_NUMBER{$enc};
		$self->diag_mode($enc);
	}
	elsif ($name eq 'all') {
		$self->diag_mode(undef);
		$self->_set($_, $enc) for @CATEGORIES;
	}
	elsif ($PSEUDO{$name}) {
		$self->_set($_, $enc) for @{$PSEUDO{$name}};
	}
	elsif ($LOCALE{$name}) {
		$enc = $NUMBER{$enc} if defined $enc && exists $NUMBER{$enc};
		$self->$name($enc);
		# (what is said in ASCII, we say in ASCII: diag follows it)
		$self->diag_mode(undef) if $name eq 'stderr' && _is_ascii($self->{stderr});
	}
	else {
		die _status 0, "unknown category @{[ _qq_ascii($name) ]}\n";
	}
}

# Whether an encoding, by its canonical name, is ASCII (as every name
# of it is in Encode: US-ASCII, ANSI_X3.4-1968, 646, ...)
sub _is_ascii
{
	my ($enc) = @_;
	defined $enc && $enc eq 'ascii';
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
	# (as we are asked for on the way to a diag, which may say %m)
	local ($!, $^E);
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

Returns the code set of a category, by its canonical name in
L<Encode> (C<UTF-8> is C<utf-8-strict>), or undef if it is not set.
Given an I<encoding>, sets it first; undef or C<locale> unsets it.

A category that is not set follows the locale I<of that category>,
so copying an unset one does not copy its encoding:

    $cs->stdout( $cs->argv );   # argv not set: stdout is unset too,
                                # and follows console_out, not locale

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
			if (defined $enc && $enc ne 'locale') {
				my $obj = Encode::find_encoding($enc)
					or die _status 0, "unknown encoding @{[ _qq_ascii($enc) ]}"
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

=item I<cs>->B<all>([ I<encoding> ])

Given an I<encoding>, sets every category to it and makes B<diag>
follow B<stderr> again, as the pseudo-category B<all> does; I<cs> is
left as it was if the I<encoding> is unknown.  Returns a new hash
(by reference) of every category and B<diag>, with undef for what is
not set.  B<diag> is undef there unless a mode was set explicitly.

The hash is a copy, and can be given to L</parse> to make another
I<cs> the same.  (Not to L</new> as a list: a hash has no order, and
B<stderr> set after B<diag> may reset it.)

    $other->parse($cs->all);
    my $same = $CS->new->parse($cs->all);

=cut

sub all
{
	my $self = shift;
	if (@_) {
		my ($enc) = @_;
		# (to a copy first, so that we are as we were if it is bad)
		my $new = $self->new(all => $enc);
		%$self = %$new;
	}
	+{ map { $_ => $self->{$_} } @CATEGORIES, 'diag' };
}

=item I<cs>->B<encoding>( I<category> )

Returns the code set a category is spelled in, by its canonical name
in L<Encode>, whether it is set or not: for one that is not, what it
follows (see above) is looked up, as it is when the category is used.
Unlike the accessors, it is never undef.

=cut

sub encoding
{
	my ($self, $name) = @_;
	defined $self->{$name} ? $self->{$name}
		: Encode::find_encoding($LOCALE{$name})->name;
}

# ... as people know it
sub _say_encoding
{
	my ($self, $name) = @_;
	my $obj = Encode::find_encoding($self->encoding($name));
	$obj->mime_name || $obj->name;
}

# What Encode said went wrong, on one line (_code has taken off where,
# if it could tell)
sub _encode_error
{
	my ($err) = @_;
	chomp $err;
	$err;
}

# A $SIG{__DIE__} that takes off the ` at FILE line N.' that perl puts
# after a message with no newline (and `, <FH> line N' if there was a
# read): caller says which FILE and N, so a FILE with spaces is no
# guess.  Anything else (an object, or a message that ends otherwise)
# dies as it is.
sub _die_plain
{
	my ($mesg) = @_;
	ref $mesg and die $mesg;
	my (undef, $file, $line) = caller(0);
	my $where = " at $file line $line";
	my $at = rindex($mesg, $where);
	$at >= 0 && substr($mesg, $at + length $where)
		=~ /\A(?:, <.*> (?:line|chunk) \d+)?\.\n\z/s
		and die substr($mesg, 0, $at) . "\n";
	die $mesg;
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
				or die _status 0, "unknown diag mode @{[ _qq_ascii($mode) ]}"
					. " (unicode or ascii)\n";
			$self->{diag} = $mode;
		}
		else {
			delete $self->{diag};
		}
	}
	return $self->{diag} if defined $self->{diag};
	_is_ascii($self->encoding('stderr')) ? 'ascii' : 'unicode';
}

=item I<cs>->B<initstd>([ I<file> => I<fallback>, ... ][, { prog => I<prog> }])

Configures the standard files (B<stdin>, B<stdout> and B<stderr>) to
use the current code sets, in place of whatever layers they had.  A
I<fallback> is what L<PerlIO::encoding> does with what cannot be spelled
(C<$PerlIO::encoding::fallback>, which is left as it is for the rest).
Dies if one cannot be.

=item I<cs>->B<reinitstd>([ I<file> => I<fallback>, ... ][, { prog => I<prog> }])

The same as B<initstd> except that streams that are not explicitly
spelled are left alone.

=cut

sub initstd
{
	my ($self, @pairs) = @_;
	my $prog = _who(_opt(initstd => \@pairs, 'prog'));
	Carp::croak('initstd: odd number of arguments') if @pairs % 2;
	my %dfl = map { $_ => undef } qw( stdin stdout stderr );
	$self->_initstd($prog, %dfl, @pairs);
}

sub reinitstd
{
	my ($self, @pairs) = @_;
	my $prog = _who(_opt(reinitstd => \@pairs, 'prog'));
	Carp::croak('reinitstd: odd number of arguments') if @pairs % 2;
	$self->_initstd($prog, @pairs);
}

sub _initstd
{
	my ($self, $prog, %fallback) = @_;
	for (sort keys %fallback) {
		Carp::croak("${prog}not a standard file: $_") unless $STD{$_};
	}
	for my $name (qw( stdin stdout stderr )) {
		next unless exists $fallback{$name};
		my $enc = $self->encoding($name);
		local $PerlIO::encoding::fallback = $fallback{$name}
			if defined $fallback{$name};
		binmode $STD{$name}, ":raw:encoding($enc)"
			or die "${prog}cannot configure $name to use the $enc encoding: $!\n";
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

Who could not, said before the error (C<prog: cannot encode file
name ...>): the method's name (C<to_fs> or C<un_fs>) unless given;
undef or empty says no one.  The error ends with what L<Encode> said,
but for where perl says it said it.

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
	my $who = _who($opt, $sub);
	my $enc = $self->encoding('filesys');
	my @new;
	for my $name (@names) {
		my ($new, $err) = _code($code, $enc, $name, $opt->{check});
		defined $new or die _status 0, $who
			. "cannot $what file name @{[ _qq_ascii($name) ]}"
			. " in @{[ $self->_say_encoding('filesys') ]}: $err\n";
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

=item B<prog> => I<prog>

Who could not, said before the error (C<prog: cannot decode argv 1:
...>): the method's name (C<un_argv> or C<to_argv>) unless given;
undef or empty says no one.

=item B<check> => I<check>

What to do with what cannot be spelled, as L<Encode> takes it
(C<FB_CROAK>).

=back

    my $prog = $cs->un_argv($0);
    my @args = $cs->un_argv(@ARGV, { start => 1, prog => $prog });

=cut

sub un_argv
{
	my $self = shift;
	$self->_argv(\&Encode::decode, decode => un_argv => @_);
}

sub to_argv
{
	my $self = shift;
	$self->_argv(\&Encode::encode, encode => to_argv => @_);
}

sub _argv
{
	my ($self, $code, $what, $sub, @args) = @_;
	my $opt = _opt($sub => \@args, qw( start prog check ));
	my $start = exists $opt->{start} ? $opt->{start} : 0;
	Carp::croak("$sub: start is not a number")
		unless defined $start && $start =~ /\A[0-9]+\z/;
	my $enc = $self->encoding('argv');
	my @new;
	for my $i (0 .. $#args) {
		my ($new, $err) = _code($code, $enc, $args[$i], $opt->{check});
		defined $new or die _status 0, _who($opt, $sub)
			. "cannot $what argv @{[ $start + $i ]}: $err\n";
		push @new, $new;
	}
	wantarray ? @new : $new[0];
}

=item I<cs>->B<decode_argv>([ I<check> ])

=item I<cs>->B<decode_argv>({ I<option> => I<value>, ... })

=item I<cs>->B<encode_argv>([ I<check> ])

=item I<cs>->B<encode_argv>({ I<option> => I<value>, ... })

Decodes C<@ARGV> (as B<argv>), or encodes it, as B<un_argv> and
B<to_argv> would from B<argv> C<1>; or dies, leaving it as it was, if
one argument cannot be.  (As L<Encode::Locale/decode_argv>.)  The
options are theirs, but for B<start>: B<prog> (here C<decode_argv> or
C<encode_argv> unless given) and B<check>.

=cut

sub decode_argv
{
	my ($self, @arg) = @_;
	@ARGV = $self->un_argv(@ARGV, { _argv_opt(decode_argv => @arg), start => 1 });
	return;
}

sub encode_argv
{
	my ($self, @arg) = @_;
	@ARGV = $self->to_argv(@ARGV, { _argv_opt(encode_argv => @arg), start => 1 });
	return;
}

# A check alone, or the options, of decode_argv and encode_argv
sub _argv_opt
{
	my ($who, @arg) = @_;
	return (check => $arg[0], prog => $who) unless ref $arg[0] eq 'HASH';
	my %opt = %{ _opt($who => \@arg, qw( prog check )) };
	exists $opt{prog} or $opt{prog} = $who;
	%opt;
}

=item I<cs>->B<getenv>( I<name>, ...[, { I<option> => I<value>, ... }] )

The values of the environment variables (B<env>) by those names,
undef for each that is not set; the first one, in scalar context.
Dies if a name or a value cannot be spelled, saying which, and what
L<Encode> said.  The options are B<prog>, who could not (said before
the error: the method's name unless given; undef or empty says no
one), and B<check>, which is for the values; a name is always spelled
as it is, or not at all.

=item I<cs>->B<setenv>( I<name> => I<value>, ...[, { I<option> => I<value>, ... }] )

Sets the environment variables; a I<value> of undef unsets it.  Sets
none of them if one cannot be spelled.  The options are those of
B<getenv>.

=item I<cs>->B<unsetenv>( I<name>, ...[, { prog => I<prog> }] )

Unsets them.

=cut

sub getenv
{
	my ($self, @names) = @_;
	my $opt = _opt(getenv => \@names, qw( prog check ));
	my $who = _who($opt, 'getenv');
	my $enc = $self->encoding('env');
	my @values;
	for my $name (@names) {
		my $value = $ENV{ $self->_env_key($enc, $name, $who) };
		if (defined $value) {
			(my $new, my $err) = _code(\&Encode::decode, $enc, $value, $opt->{check});
			defined $new or die _status 0, $who . "cannot decode environment variable"
				. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}: $err\n";
			$value = $new;
		}
		push @values, $value;
	}
	wantarray ? @values : $values[0];
}

sub setenv
{
	my ($self, @pairs) = @_;
	my $opt = _opt(setenv => \@pairs, qw( prog check ));
	Carp::croak('setenv: odd number of arguments') if @pairs % 2;
	my $who = _who($opt, 'setenv');
	my $enc = $self->encoding('env');
	my %set;
	while (my ($name, $value) = splice @pairs, 0, 2) {
		my $key = $self->_env_key($enc, $name, $who);
		if (defined $value) {
			my ($bytes, $err) = _code(\&Encode::encode, $enc, $value, $opt->{check});
			defined $bytes or die _status 0, $who . "cannot encode the value of"
				. " environment variable @{[ _qq_ascii($name) ]}"
				. " in @{[ $self->_say_encoding('env') ]}: $err\n";
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
	my $opt = _opt(unsetenv => \@names, 'prog');
	$self->setenv((map { $_ => undef } @names),
		{ prog => exists $opt->{prog} ? $opt->{prog} : 'unsetenv' });
	return;
}

sub _env_key
{
	my ($self, $enc, $name, $who) = @_;
	Carp::croak('undefined environment variable name') unless defined $name;
	my ($key, $err) = _code(\&Encode::encode, $enc, $name);
	defined $key or die _status 0, $who . "cannot encode environment variable name"
		. " @{[ _qq_ascii($name) ]} in @{[ $self->_say_encoding('env') ]}: $err\n";
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

# prog => ..., of those options: "prog: ", or ''; if there is no
# prog => at all, the $default (a method's own name), if given
sub _who
{
	my ($opt, $default) = @_;
	my $prog = exists $opt->{prog} ? $opt->{prog} : $default;
	defined $prog && length $prog ? "$prog: " : '';
}

# What Encode makes of the source (which it is not given to modify),
# or undef and why not
sub _code
{
	my ($code, $enc, $src, $check) = @_;
	$check = $CHECK unless defined $check;
	my $copy = $src;
	my $res = eval {
		local $SIG{__DIE__} = \&_die_plain;
		$code->($enc, $copy, $check);
	};
	return ($res) if defined $res;
	(undef, $@ ne '' ? _encode_error($@) : 'undefined');
}

=item I<cs>->B<diag_name>( I<name>, soft => 0 )

I<name>, for diagnostics C<`name'> if it is all printable ASCII
but for C<`> and C<'> (which would confuse the quotes), and
quoted as Perl would otherwise, with escapes (C<\n>, C<\x{a0}>) for
what would not show.  Under C<diag_mode> C<ascii>, that is all but
printable ASCII; under C<unicode>, it is only controls, separators
and the like (C<\p{C}> and C<\p{Z}>, but for the ASCII space), and
what B<stderr> cannot spell.

If C<soft> is true, whole words are interpolated verbatim without
quoting.

=cut

sub diag_name
{
	my ($self, $name, %opt) = @_;
	return undef unless defined $name;
	if ($opt{soft}) {
		# colons are usually separators and are
		# therefore "too dangerous" to be included
		# here :c
		#
		# Backslashes are alright though... (also
		# because DOS uses them for file sep, so)
		# A more practical reason though: PERLQQ-
		# fallback ASCII strings are preserved.
		if ($self->diag_mode eq 'ascii'
			? $name =~ /\A[A-Za-z0-9_\.\-\\\/]+\z/
			: $name =~ /\A[\w\.\-\\\/]+\z/)
		{
			return $name;
		}
	}
	return "`$name'" if $name =~ /\A(?:(?![`'])[\x20-\x7e])*\z/;
	$self->diag_mode eq 'ascii' ? _qq_ascii($name)
		: _qq_unicode($name, $self->encoding('stderr'));
}

=item I<cs>->B<diag>( I<format>, I<arg>, ... )

The I<format>, as L<perlfunc/sprintf> would have it, with each C<%q>
replaced by the L</diag_name> of its I<arg>, each C<%s> by its I<arg>
as it is (or nothing, if it is undef), C<%d>, C<%i>, C<%u>, C<%o>,
C<%x> and C<%X> as sprintf says, each C<%m> by C<$!> (as it was when
we were called; it takes no I<arg>), and each C<%%> by C<%>.  An
I<arg> may be named by number (C<%2$s %1$q>, for a translation that
says them in another order), and the others are taken in order, as
sprintf takes them; and flags, widths and precisions are as sprintf
says (C<%-10q>).  Dies on any other C<%>, or an I<arg> that is not
there.

C<$!> is said in the language of the locale, as perl says it in the
scope of C<use locale> (from 5.22; before, always), and is decoded
from the locale's code set (L<Encode::Locale>), if perl has not.

What B<stderr> cannot spell, in the I<format> or in an I<arg> of
C<%s>, or C<%m>, is escaped (C<\x{7092}>), as C<FB_PERLQQ> would have
it; so that the message can be said, whatever B<stderr> was opened
with, and the more so if it dies.

=cut

sub diag
{
	my ($self, $format, @args) = @_;
	my $errno = 0 + $!;
	my $enc = $self->encoding('stderr');
	# What sprintf is given: the format, with what we say ourselves
	# (%m, %%) said, and every other conversion numbered, and the
	# arguments of those, one each (as %1$q and %1$s are not the same)
	my $out = '';
	my @out;
	my $next = 0;
	pos $format = 0;
	while ($format =~ /\G([^%]*)%(?:([1-9][0-9]*)\$)?([-+ 0#]*[0-9]*(?:\.[0-9]+)?)(.?)/gcs) {
		my ($text, $pos, $flags, $conv) = ($1, $2, $3, $4);
		$out .= _perlqq($enc, $text);
		my $spec = '%' . (defined $pos ? "$pos\$" : '') . $flags . $conv;
		if ($conv eq '%' || $conv eq 'm') {
			$spec eq "%$conv" or Carp::croak("diag: unknown conversion $spec");
			(my $said = $conv eq '%' ? '%' : _perlqq($enc, _strerror($errno))) =~ s/%/%%/g;
			$out .= $said;
		}
		elsif ($conv =~ /\A[sqdiuoxX]\z/) {
			my $i = defined $pos ? $pos - 1 : $next++;
			$i < @args or Carp::croak("diag: missing argument for $spec");
			my $arg = $args[$i];
			if ($conv eq 'q') {
				my $name = $self->diag_name($arg, soft => 0 + ($flags =~ /#/));
				($arg, $conv) = ($name, 's');
			}
			elsif ($conv eq 's') {
				$arg = defined $arg ? _perlqq($enc, $arg) : '';
			}
			push @out, $arg;
			$out .= '%' . @out . '$' . $flags . $conv;
		}
		else {
			Carp::croak("diag: unknown conversion $spec");
		}
	}
	sprintf $out . _perlqq($enc, substr($format, pos $format)), @out;
}

=item I<cs>->B<tagmsg>( I<prog>, I<mesg> )

Prepend each line of the message with C<< diag("%#q: ", I<prog>) >>,
and end it with a newline (just one: a newline already at the end of
I<mesg> is not another line).  This seems common enough to warrant a
special method; I<mesg> is typically the result of L</diag>.

If I<prog> is missing or empty, return the message itself (ended by
a newline).

Since I<mesg> is chomped, calls can be chained:
C<< tagmsg(E => tagmsg(prog => ...)) >>.

=cut

sub tagmsg
{
	my ($self, $prog, $mesg) = @_;
	chomp $mesg;
	return "$mesg\n" unless defined $prog && length $prog;
	my $tag = $self->diag("%#q: ", $prog);
	$mesg =~ s/^/$tag/gm;
	"$mesg\n";
}

# $! of `errno', as characters: in the language of the locale, as perl
# says it in the scope of `use locale' (from 5.22; before, always), and
# decoded from the locale's code set if perl has not (which it does
# only from 5.22, and only if that is UTF-8)
sub _strerror
{
	my ($errno) = @_;
	local $! = $errno;
	my $msg = do { use if $] >= 5.022, locale => ':messages'; "$!" };
	return $msg if Encode::is_utf8($msg) || $msg !~ /[^\x00-\x7f]/;
	my ($s) = _code(\&Encode::decode, 'locale', $msg);
	defined $s ? $s : Encode::decode('locale', $msg, Encode::FB_PERLQQ());
}

# Whether the encoding can spell all of the string
sub _spellable
{
	my ($enc, $s) = @_;
	defined((_code(\&Encode::encode, $enc, $s))[0]);
}

# The string, with what the encoding cannot spell escaped as \x{...}
sub _perlqq
{
	my ($enc, $s) = @_;
	return $s if $s =~ /\A[\x00-\x7f]*\z/ || _spellable($enc, $s);
	$s =~ s/([^\x00-\x7f])/_spellable($enc, $1) ? $1 : sprintf('\x{%x}', ord $1)/ge;
	$s;
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

# Ditto, but with only what would not show, or could not be spelled
# in the encoding, escaped
# (This is inspired by Python str.isprintable())
sub _qq_unicode
{
	my ($s, $enc) = @_;
	(my $q = $s) =~ s{((?! )[\p{C}\p{Z}]|["\\\$\@])|([^\x00-\x7f])}{
		defined $1 ? _qq_char($1) : _spellable($enc, $2) ? $2 : _qq_char($2)
	}ge;
	qq{"$q"};
}

=back

=head1 SEE ALSO

L<Encode>, L<Encode::Locale>, L<PerlIO::encoding>

=cut

1;
