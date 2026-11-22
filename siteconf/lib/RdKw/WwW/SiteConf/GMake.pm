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
(newer than 3.81, which cannot escape a C<:>), which can name more
files: a C<$> is C<$$>; blanks, C<#> and C<:> are escaped with
a backslash (and so is a backslash before them); a wildcard is in
brackets (C<a[*]b>), so that it only ever matches itself; and a C<~>
in front is C<./~>.

What it cannot name is an error still: a vertical space (a line
break, CR, form feed, ...), a C<;>, C<=> or C<|>, a C<\> at the end,
or a name that ends in parentheses, which would be an archive member.
(GNU make 4.4.1 reads C<a\|b> as C<a|b> in a prerequisite, and as
C<a\|b> in a target.)
The escaped name is then spelled as the file system spells it, as in
L<RdKw::WwW::SiteConf::Make>.

=cut

use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
# (Same gettext setup as SiteConf.pm.)
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

# A name, as GNU make reads it
sub _name
{
	my ($class, $s) = @_;
	$s =~ /([\n\cK\f\r\x{85}\x{2028}\x{2029};=|]|\\\z)/
		# HEY!  the %s is a character, as `;' or U+000A
		and die _status 0, tagmsg(E => diag(__(
			"GNU Make cannot name %q (with inescapable %s)"),
			$s, $class->_char($1)));
	$s =~ /\(.*\)\z/s
		# HEY!  lib(member.o) is how make names a member of an archive
		and die _status 0, tagmsg(E => diag(__(
			"GNU Make cannot name %q (reserved for archive members)"),
			$s));
	$s =~ s/\$/\$\$/g;
	$s =~ s/(\\*)([\t #:])/$1$1\\$2/g;
	$s =~ s/(\\*)([*?\[])/$1$1\[$2\]/g;
	$s =~ s/\A~/.\/~/;
	$class->_fs($s);
}

1;
