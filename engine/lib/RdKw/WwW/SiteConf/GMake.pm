package RdKw::WwW::SiteConf::GMake;

use 5.008;
use strict;
use warnings;
use RdKw::WwW::SiteConf::Make ();

our @ISA = qw( RdKw::WwW::SiteConf::Make );

=head1 NAME

RdKw::WwW::SiteConf::GMake - GNU Makefile backend for siteconf

=head1 SYNOPSIS

    my $text = RdKw::WwW::SiteConf::GMake->_emit($plan);

=head1 DESCRIPTION

The very Makefile of L<RdKw::WwW::SiteConf::Make>, but for GNU make
(newer than 3.81, which cannot escape a C<:>), which can name more
files: a C<$> is C<$$>; blanks, C<#>, C<:> and C<|> are escaped with
a backslash (and so is a backslash before them); a wildcard is in
brackets (C<a[*]b>), so that it only ever matches itself; and a C<~>
in front is C<./~>.

What it cannot name is an error still: a vertical space (a line
break, CR, form feed, ...), a C<;> or C<=>, a C<\> at the end, or a
name that ends in parentheses, which would be an archive member.

=cut

# A name, as GNU make reads it
sub _name
{
	my ($class, $s) = @_;
	$s =~ /([\n\cK\f\r\x{85}\x{2028}\x{2029};=]|\\\z)/
		and die "E: GNU make cannot name `$s' (with "
			. $class->_char($1) . " in it)\n";
	$s =~ /\(.*\)\z/s
		and die "E: GNU make cannot name `$s' (it would be an archive member)\n";
	$s =~ s/\$/\$\$/g;
	$s =~ s/(\\*)([\t #:|])/$1$1\\$2/g;
	$s =~ s/(\\*)([*?\[])/$1$1\[$2\]/g;
	$s =~ s/\A~/.\/~/;
	$s;
}

1;
