package TestDiag;

# What siteconf says, a sentence per line, for tests to match.
#
# siteconf says a sentence over several lines: what, then where (in
# parentheses), then why, each indented one more than the first.
# fold() joins a line to the next while the line does not end the
# sentence (in `.', `!', `?' or `:', after a face ` :(' at the end,
# which is dropped) and the next line has the same tag (`W: ') and is
# indented deeper than the first line of the sentence: a line that is
# not is a sentence of its own, ended or not.  The joined lines lose
# their tag and indentation, and are joined by one space; the first
# keeps its own, so that what is said under what (a cause under what
# it breaks) still shows.  What has no tag is left as it is.
#
#   W: goal `a' WANTs `b'
#   W:  (in MANIFEST line 2),
#   W:   but cannot be made:
#   W:   no rule to make it
#   W:    (`Makefile.in').
#
# is
#
#   W: goal `a' WANTs `b' (in MANIFEST line 2), but cannot be made:
#   W:   no rule to make it (`Makefile.in').

use strict;
use warnings;

use Exporter ();
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( fold );

sub fold
{
	my ($text) = @_;
	return undef unless defined $text;
	my @out;
	# The tag and the indentation of the sentence the last line left
	# open, if it did
	my ($tag, $indent);
	for my $line (split /\n/, $text, -1) {
		(my $s = $line) =~ s/ :\(\z//;
		my ($t, $sp, $rest) = $s =~ /\A([A-Z]: )( *)(.*)\z/s;
		if (defined $tag && defined $t && $t eq $tag && length $sp > $indent && length $rest) {
			$out[-1] .= " $rest";
		} else {
			push @out, $s;
			($tag, $indent) = defined $t ? ($t, length $sp) : ();
		}
		$tag = undef if $s =~ /[.!?:]\z/;
	}
	join "\n", @out;
}

1;
