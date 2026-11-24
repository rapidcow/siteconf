package RdKw::WwW::SiteConf::GMake;

use 5.008;
use strict;
use warnings;

use RdKw::WwW::SiteConf::Make ();
our $VERSION = $RdKw::WwW::SiteConf::Make::VERSION;
our @ISA = qw( RdKw::WwW::SiteConf::Make );

=head1 NAME

RdKw::WwW::SiteConf::GMake - GNU Makefile backend for siteconf

=head1 SYNOPSIS

    my $text = RdKw::WwW::SiteConf::GMake->_emit($plan);

=head1 DESCRIPTION

The very Makefile of L<RdKw::WwW::SiteConf::Make>, but for GNU Make
(4.0 or newer for a C<:>, which older versions do not unescape in
a prerequisite), which can name more
files: a C<$> is C<$$>; blanks, C<#> and C<:> are escaped with
a backslash (and so is a backslash before them); a wildcard is in
brackets (C<a[*]b>), so that it only ever matches itself; and a C<~>
in front is C<./~>.

A C<;> is escaped twice, as C<\\\;>, with C<4k+3> backslashes for
C<k> before it: GNU Make looks for the C<;> that begins a recipe
before it unescapes a rule line.  A C<|> is escaped (C<\|>) among the
prerequisites before the order-only ones, and only there: in a target,
or after the C<|> that begins the order-only prerequisites, it is as
it is, and so is a backslash before it.  GNU Make 3.81 and 4.4.1 both
read them so.

What it cannot name is an error still: a vertical space (a line
break, CR, form feed, ...), a C<=>, a C<\> at the end, or a name that
ends in parentheses, which would be an archive member.
With C<-Sorder=1>, a directory marker is an order-only prerequisite
(after a C<|>), so that what is made in a directory does not wait on how
new its marker is.  Any other value of C<order> (C<0>, empty or none)
leaves it as in L<RdKw::WwW::SiteConf::Make>.
The escaped name is then spelled as the file system spells it, as in
L<RdKw::WwW::SiteConf::Make>.

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

sub _options { ( $_[0]->SUPER::_options, 'order' ) }

# GNU make: with -Sorder=1, the directory markers are after a `|'
# (-Sorder=0, -Sorder= and -Sorder alone do not)
sub _order_only { $_[1] && $_[1]{order} ? 1 : 0 }

# A name, as GNU make reads it where it is: a `target', an `order'-only
# prerequisite, or (if neither) a prerequisite before those
sub _name
{
	my ($class, $s, $where) = @_;
	$where ||= '';
	$s =~ /([\n\cK\f\r\x{85}\x{2028}\x{2029}=]|\\\z)/
		# HEY!  the %s is a character, as `=' or U+000A
		and die _status 0, tagmsg(E => diag(__(
			"GNU Make cannot name %q (with inescapable %s)"),
			$s, $class->_char($1)));
	$s =~ /\(.*\)\z/s
		# HEY!  lib(member.o) is how make names a member of an archive
		and die _status 0, tagmsg(E => diag(__(
			"GNU Make cannot name %q (reserved for archive members)"),
			$s));
	$s =~ s/\$/\$\$/g;
	$s =~ s{(\\*)([\t #:;|])}{
		my ($bs, $c) = ($1, $2);
		$c eq ';' ? '\\' x (4 * length($bs) + 3) . ';'
		: $c eq '|' && $where ne '' ? "$bs|"
		: "$bs$bs\\$c"
	}ge;
	$s =~ s/(\\*)([*?\[])/$1$1\[$2\]/g;
	$s =~ s/\A~/.\/~/;
	$class->_fs($s);
}

1;
