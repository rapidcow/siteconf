#!perl
#
# pm_filter.pl LOCALEDIR < in.pm > out.pm
#
# The PM_FILTER of Makefile.PL: @localedir@ is LOCALEDIR, as a Perl
# string literal (of bytes, as the file system spells it).

use strict;
use warnings;

@ARGV == 1 or die "usage: pm_filter.pl LOCALEDIR < in.pm > out.pm\n";
(my $dir = shift) =~ s/([\\'])/\\$1/g;

binmode STDIN;
binmode STDOUT;
while (<STDIN>) {
	s/\@localedir\@/'$dir'/g;
	print or die "pm_filter.pl: write: $!\n";
}
close STDOUT or die "pm_filter.pl: write: $!\n";
