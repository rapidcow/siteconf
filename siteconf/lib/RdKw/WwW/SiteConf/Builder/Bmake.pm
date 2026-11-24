package RdKw::WwW::SiteConf::Builder::Bmake;

use 5.008;
use strict;
use warnings;

use RdKw::WwW::SiteConf::Builder::Make ();
our $VERSION = $RdKw::WwW::SiteConf::Builder::Make::VERSION;
our @ISA = qw( RdKw::WwW::SiteConf::Builder::Make );

=head1 NAME

RdKw::WwW::SiteConf::Builder::Bmake - bmake Makefile backend for siteconf

=head1 SYNOPSIS

    $siteconf->generate(q(bmake));   # siteconf -g -G bmake

=head1 DESCRIPTION

The very Makefile of L<RdKw::WwW::SiteConf::Builder::Make>, for bmake
(the make of NetBSD, and of FreeBSD as C<make>).  Make already writes
what bmake reads: it names files as bmake can (bmake reads a dependency
line twice, so that not even C<$$> is a C<$>).  So this is that
Makefile, and what to type next says C<bmake>.

=head2 Methods

Those of L<RdKw::WwW::SiteConf::Builder::Make/Methods>, which change
with siteconf too.

=cut

1;
