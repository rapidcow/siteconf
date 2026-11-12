package RdKw::L10N::TextDomain;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

=head1 NAME

L10N::TextDomain - UTF-8 gettext text domain

=head1 SYNOPSIS

    # The domain and where its catalogs are, as a module of its
    # own says ($DOMAIN, $LOCALEDIR), if it is there:
    use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

    # or as they are given:
    use RdKw::L10N::TextDomain 'siteconf', '/usr/local/share/locale';

    die _diag(__("cannot open file %q: %m"), $file) . "\n";
    print __n("one file", "%d files", $n);
    our @HELP = ( N__("This help message"), ... );   # __ them later

=head1 DESCRIPTION

Puts B<__>, B<__n> and B<N__> in the package that uses it, for the
messages of one text domain: what L<Locale::Messages> (libintl-perl)
says of them, in the language of the locale, if it is there; and as
they are written, if it is not, or no catalog has them.  So that what
says something need not care whether it is said in another language,
and this needs nothing but what comes with Perl.

Messages are character strings, both ways.  The domain is bound to
UTF-8 (whatever C<OUTPUT_CHARSET> or the locale's code set would say),
the message IDs are encoded as such on their way in, and what gettext
gives back is decoded as such; both of them strictly, as a catalog that
is not UTF-8 is a mistake, not something to guess at.  B<$!> (and
B<$^E>) are as they were after any of them, as gettext may have failed
to open a catalog on the way, and the message may be on its way to say
C<%m> (see L<RdKw::I18N::CodeSets/diag>).

=over

=item C<use RdKw::L10N::TextDomain ':module' =E<gt> I<module>;>

The domain is I<module>'s C<$DOMAIN>, and its catalogs are in its
C<$LOCALEDIR> (as the system spells it: bytes, not characters).  If
I<module> cannot be loaded (it is not installed, or not built), or
does not say C<$DOMAIN>, there are no catalogs: the messages are said
as they are written.

=item C<use RdKw::L10N::TextDomain> I<domain>[, I<localedir>]C<;>

The domain is I<domain>, and its catalogs are in I<localedir>, or
wherever gettext looks for them, if that is not given (or undef).

=back

Dies on anything else.

=head1 FUNCTIONS

In all of the following, I<msgid> is a UTF-8 string whose encoded
bytes will constitute the real msgid.  The distinction is subtle,
but will matter if non-ASCII characters are used.

=over

=item B<__>( I<msgid> )

The message, in the language of the locale.

=item B<__n>( I<msgid>, I<msgid_plural>, I<n> )

The message for I<n> of something, in the language of the locale: by
default, I<msgid> if I<n> is 1, and I<msgid_plural> if not.

=item B<N__>( I<msgid> )

I<msgid>, as it is, but marked for B<xgettext>(1) (C<-kN__>) to know of,
for a message that is said later, by B<__>.

=back

The keywords for B<xgettext>(1) are C<-k__ -k__n:1,2 -kN__>.

=cut

use Carp ();
use Encode ();

my $CHECK = Encode::FB_CROAK() | Encode::LEAVE_SRC();

sub import
{
	my $class = shift;
	my $pkg = caller;
	my $usage = "usage: use $class DOMAIN[, LOCALEDIR] | ':module' => MODULE";
	my ($domain, $dir);
	if (@_ && defined $_[0] && $_[0] =~ /\A:/) {
		my ($opt, $mod) = @_;
		$opt eq ':module' && @_ == 2 or Carp::croak($usage);
		defined $mod && $mod =~ /\A\w+(?:::\w+)*\z/
			or Carp::croak("$class: bad module name for :module");
		($domain, $dir) = _of_module($mod);
	}
	else {
		@_ == 1 || @_ == 2 or Carp::croak($usage);
		($domain, $dir) = @_;
		defined $domain && length $domain
			or Carp::croak("$class: no domain");
	}
	my %sub = _subs($domain, $dir);
	no strict 'refs';
	*{"${pkg}::$_"} = $sub{$_} for keys %sub;
}

# The domain and where its catalogs are, as the module says; or
# nothing, if it cannot be loaded
sub _of_module
{
	my ($mod) = @_;
	(my $file = "$mod.pm") =~ s{::}{/}g;
	# (what it warns of is said if it loads, and is no news if it does
	# not: an unbuilt one is no Perl, and says so)
	my @warn;
	my $ok = do {
		local $SIG{__WARN__} = sub { push @warn, @_ };
		eval { require $file; 1 };
	};
	$ok or return;
	warn @warn if @warn;
	no strict 'refs';
	my $domain = ${"${mod}::DOMAIN"};
	defined $domain && length $domain or return;
	($domain, ${"${mod}::LOCALEDIR"});
}

# __, __n and N__ of the domain (as they are written, if there is no
# domain, or nothing to read its catalogs with)
sub _subs
{
	my ($domain, $dir) = @_;
	my %sub = ( N__ => sub { $_[0] } );
	if (defined $domain && eval {
		require Locale::Messages;
		Locale::Messages::bindtextdomain($domain, $dir) if defined $dir;
		Locale::Messages::bind_textdomain_codeset($domain, 'UTF-8');
		1;
	}) {
		$sub{__} = sub {
			local ($!, $^E);
			Encode::decode('UTF-8', Locale::Messages::dgettext($domain,
				Encode::encode('UTF-8', $_[0], $CHECK)), $CHECK);
		};
		$sub{__n} = sub {
			local ($!, $^E);
			Encode::decode('UTF-8', Locale::Messages::dngettext($domain,
				Encode::encode('UTF-8', $_[0], $CHECK),
				Encode::encode('UTF-8', $_[1], $CHECK), $_[2]), $CHECK);
		};
	}
	else {
		$sub{__} = sub { $_[0] };
		$sub{__n} = sub { $_[2] == 1 ? $_[0] : $_[1] };
	}
	%sub;
}

=head1 SEE ALSO

L<Locale::Messages>, L<Locale::TextDomain> (which this is not: it
says messages in the locale's code set, and has no fallbacks)

=cut

1;
