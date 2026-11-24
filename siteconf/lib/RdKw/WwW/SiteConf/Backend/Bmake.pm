package RdKw::WwW::SiteConf::Backend::Bmake;

use 5.008;
use strict;
use warnings;

use RdKw::WwW::SiteConf::Backend::Make ();
our $VERSION = $RdKw::WwW::SiteConf::Backend::Make::VERSION;
our @ISA = qw( RdKw::WwW::SiteConf::Backend::Make );

=head1 NAME

RdKw::WwW::SiteConf::Backend::Bmake - bmake Makefile backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(bmake));   # siteconf -g -G bmake

=head1 DESCRIPTION

The very Makefile of L<RdKw::WwW::SiteConf::Backend::Make>, for bmake
(the make of NetBSD, and of FreeBSD as C<make>).  Make already writes
what bmake reads: it names files as bmake can (bmake reads a dependency
line twice, so that not even C<$$> is a C<$>).  So this is that
Makefile, and what to type next says C<bmake>.

=head2 Methods

Those of L<RdKw::WwW::SiteConf::Backend::Make/Methods>, which change
with siteconf too.

=cut

1;
