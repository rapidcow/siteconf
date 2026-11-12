package RdKw::WwW::GenGenLib::L10N;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

=head1 NAME

WwW::GenGenLib::L10N - gengenlib locale directory config

=head1 SYNOPSIS

    require RdKw::WwW::GenGenLib::L10N;
    Locale::Messages::bindtextdomain(gengenlib =>
        $RdKw::WwW::GenGenLib::L10N::LOCALEDIR);

=head1 DESCRIPTION

B<$LOCALEDIR> is the directory the message catalogs of the
C<gengenlib> text domain are installed in
(I<LOCALEDIR>F</>I<lang>F</LC_MESSAGES/gengenlib.mo>), as the system
spells it: bytes, not characters.  L<RdKw::WwW::GenGenLib> reads it,
if this module is there; if it is not, or there is no catalog for the
language of the locale, its messages are said as they are written.

It is set when this module is built: by default,
F<share/locale> under C<INSTALL_BASE> or C<PREFIX>, or else

    perl Makefile.PL LOCALEDIR=/usr/local/share/locale

The catalogs are installed with it, by

    perl Makefile.PL LINGUAS="en zh"

or by themselves, by F<mkintl.pl> (which must be told the same
I<LOCALEDIR>; see there).

=cut

# (filled in by pm_filter.pl; this is no Perl until it is built)
our $LOCALEDIR = @localedir@;

=head1 SEE ALSO

L<Locale::Messages>, L<RdKw::WwW::GenGenLib>

=cut

1;
