package RdKw::WwW::SiteConf::L10N;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = version->parse( $VERSION );

=head1 NAME

WwW::SiteConf::L10N - siteconf locale directory config

=head1 SYNOPSIS

    require RdKw::WwW::SiteConf::L10N;
    Locale::Messages::bindtextdomain($RdKw::WwW::SiteConf::L10N::DOMAIN,
        $RdKw::WwW::SiteConf::L10N::LOCALEDIR);

=head1 DESCRIPTION

B<$DOMAIN> is the text domain, C<siteconf>.

B<$LOCALEDIR> is the directory its message catalogs are installed in
(I<LOCALEDIR>F</>I<lang>F</LC_MESSAGES/siteconf.mo>), as the system
spells it: bytes, not characters.  L<siteconf>, L<RdKw::WwW::SiteConf>,
L<RdKw::WwW::GenLib>, L<RdKw::WwW::GenGenLib> (and so
L<RdKw::WwW::GenGenLib::Template::Provider>), and the F<configure>
and F<render> that siteconf writes read it, if this module is there;
if it is not, or there is no catalog for the language of the locale,
their messages are said as they are written.

It is set when this module is built: by default,
F<share/locale> under C<INSTALL_BASE> or C<PREFIX>, or else

    perl Makefile.PL LOCALEDIR=/usr/local/share/locale

The catalogs are installed with it, by

    perl Makefile.PL LINGUAS="en zh"

or by themselves, by F<mkintl.pl> (which must be told the same
I<LOCALEDIR>; see there).

=cut

our $DOMAIN = 'siteconf';

# (filled in by pm_filter.pl; this is no Perl until it is built)
our $LOCALEDIR = @localedir@;

=head1 SEE ALSO

L<Locale::Messages>, L<RdKw::L10N::TextDomain>, L<RdKw::WwW::SiteConf>

=cut

1;
