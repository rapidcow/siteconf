package RdKw::WwW::SiteConf::Modifiers;

use 5.008;
use strict;
use warnings;

=head1 NAME

RdKw::WwW::SiteConf::Modifiers - Makefile.in variable modifiers

=head1 SYNOPSIS

    use RdKw::WwW::SiteConf::Modifiers;

    my $end = RdKw::WwW::SiteConf::Modifiers::_expr_end($text, $i);

    my $new = RdKw::WwW::SiteConf::Modifiers::_apply(
        'blog/a.md.html', 'R:S/blog/post/',
        expand => sub { ... },      # for $... inside :S
        quote  => sub { ... },      # for :Q
    );                              # post/a.md

=head1 DESCRIPTION

Modifiers are applied from left to right, each to what the one before
it made.  Except for C<:Q>, they work on a value one word (a run of
non-whitespace) at a time, and the words are put back together with
single spaces.

=over

=item C<:E>, C<:H>, C<:R>, C<:T>

The suffix of each word (without the dot; empty if there is none), its
directory (C<.> if there is none), everything but its suffix, and its
last component.  Like L<bmake(1)>, except that only the last component
may have a suffix: C<:R> of F<a.b/c> is F<a.b/c>, not F<a>.

=item C<:S/old/new/[1gW]>

Replaces the first C<old> in each word with C<new>.  C<^old> only
matches at the start of a word, and C<old$> only at its end.  C<&> in
C<new> is C<old>.  The delimiter may be any character; it, C<^>, C<$>,
C<&> and C<\> are literal after a backslash.  Both parts may have
C<${...}> in them.  This is I<not> a regular expression.

Dollar signs are read as everywhere else in F<Makefile.in>: C<$$> is a
C<$>, and C<${x}> or C<$x> is a variable.  The only C<$> that is not
expanded is the last one, if it comes right before the delimiter, in
C<old>: that one anchors.  (In C<new> it is just a C<$>.)  So C<a$$/>
is the text C<a$>, C<a$$$/> is that text at the end of a word (as is
C<a\$$/>), and C<a$$$$/> is C<a$$>.  A C<$> that is left over with
nothing after it is an error.

!!! L<bmake(1)> differs here: any run of C<$> before the delimiter
only anchors, and a literal C<$> must be C<\$>.  That works here too,
but C<$$> is a C<$> as well.

The flags are C<1> (stop after the first word that matched), C<g> (every
occurrence in a word) and C<W> (the value is a single word).

=item C<:Q>

Shell-quotes the value as a whole, unless that is needless.

=back

=cut

# Word at a time.  Each takes and returns a word.
my %WORD = (
	E => sub { $_[0] =~ m!\.([^./]*)\z! ? $1 : '' },
	H => sub {
		$_[0] =~ m!\A(.*)/! ? (length $1 ? $1 : '/') : '.';
	},
	R => sub { $_[0] =~ m!\A(.*?)\.[^./]*\z!s ? $1 : $_[0] },
	T => sub { $_[0] =~ m!([^/]*)\z! ? $1 : $_[0] },
);

# The end (one past the last character) of the expression that begins
# at the `$' at `pos' of `str': ${...} with its braces balanced
# (a backslash protects the next character), or `$' and one character.
# A `$' with nothing to follow is no expression, and the end is undef.
sub _expr_end
{
	my ($str, $pos) = @_;
	my $len = length $str;
	return undef if $pos + 1 >= $len;
	return $pos + 2 if substr($str, $pos + 1, 1) ne '{';
	my $depth = 0;
	for (my $i = $pos + 1; $i < $len; $i++) {
		my $c = substr($str, $i, 1);
		if ($c eq '\\') {
			$i++;
		} elsif ($c eq '{') {
			$depth++;
		} elsif ($c eq '}') {
			return $i + 1 unless --$depth;
		}
	}
	die "unterminated `" . substr($str, $pos) . "'\n";
}

# One part of :S/old/new/, from `pos' of `str' up to its delimiter.
# Returns the new position (just past the delimiter) and the part:
# old comes as ($text, $anchor_start, $anchor_end), and new as a list
# of strings in which undef stands for `&'.
sub _part
{
	my ($str, $pos, $delim, $is_new, $expand) = @_;
	my $len = length $str;
	my ($lit, $bol, $eol) = ('');
	my @parts;
	my $first = $pos;
	while ($pos < $len) {
		my $c = substr($str, $pos, 1);
		if ($c eq $delim) {
			push @parts, $lit;
			return ($pos + 1, $is_new ? @parts : (join('', @parts), $bol, $eol));
		} elsif ($c eq '\\') {
			my $n = $pos + 1 < $len ? substr($str, $pos + 1, 1) : '';
			if ($n eq $delim or $n =~ /\A[\\^\$&}]\z/ and length $n) {
				$lit .= $n;
				$pos += 2;
			} else {
				$lit .= $c;
				$pos++;
			}
		} elsif ($c eq '$') {
			my $n = $pos + 1 < $len ? substr($str, $pos + 1, 1) : '';
			if ($n eq $delim or $pos + 1 >= $len) {
				# An anchor in old, but only a dollar in new
				if ($is_new) { $lit .= $c } else { $eol = 1 }
				$pos++;
			} else {
				my $end = _expr_end($str, $pos);
				$lit .= $expand->(substr($str, $pos, $end - $pos));
				$pos = $end;
			}
		} elsif ($c eq '^' && $pos == $first && !$is_new) {
			$bol = 1;
			$pos++;
		} elsif ($c eq '&' && $is_new) {
			push @parts, $lit, undef;
			$lit = '';
			$pos++;
		} else {
			$lit .= $c;
			$pos++;
		}
	}
	die "unterminated :S modifier\n";
}

# :S on one word: the new word, or undef if `old' is not in it.
sub _replace
{
	my ($word, $old, $new, $bol, $eol, $global) = @_;
	my $sub = join '', map { defined $_ ? $_ : $old } @$new;
	my $olen = length $old;
	if ($bol or $eol) {
		my $wlen = length $word;
		return undef if $olen > $wlen;
		return undef if $bol && substr($word, 0, $olen) ne $old;
		return undef if $eol && substr($word, $wlen - $olen) ne $old;
		return undef if $bol && $eol && $olen != $wlen;
		return $bol ? $sub . substr($word, $olen) : substr($word, 0, $wlen - $olen) . $sub;
	}
	return undef unless $olen;   # there is nothing to find, so nothing found
	my $at = index($word, $old);
	return undef if $at < 0;
	my $out = '';
	my $from = 0;
	while ($at >= 0) {
		$out .= substr($word, $from, $at - $from) . $sub;
		$from = $at + $olen;
		last unless $global;
		$at = index($word, $old, $from);
	}
	$out . substr($word, $from);
}

=head1 FUNCTIONS

Private; for L<RdKw::WwW::SiteConf>.

=cut

# _apply VALUE, MODS, expand => CODE, quote => CODE
# MODS is what is after the first colon: `R:S/x/y/:Q'.  `expand' is
# given the text of an expression (`${x}') and returns its value,
# `quote' a string and returns it quoted.  Dies, without a location,
# on what it cannot understand.
sub _apply
{
	my ($val, $mods, %o) = @_;
	my $pos = 0;
	my $len = length $mods;
	$len or die "empty modifier\n";
	while ($pos < $len) {
		my $start = $pos;
		my $c = substr($mods, $pos++, 1);
		if ($WORD{$c}) {
			$val = join ' ', map { $WORD{$c}->($_) } split ' ', $val;
		} elsif ($c eq 'Q') {
			$val = $o{quote}->($val);
		} elsif ($c eq 'S') {
			$pos < $len or die "unterminated :S modifier\n";
			my $delim = substr($mods, $pos++, 1);
			$delim =~ /\A[\\\$:]\z/ and die "bad delimiter `$delim' for :S\n";
			my ($old, $bol, $eol, @new);
			($pos, $old, $bol, $eol) = _part($mods, $pos, $delim, 0, $o{expand});
			($pos, @new) = _part($mods, $pos, $delim, 1, $o{expand});
			my %flag;
			while ($pos < $len && substr($mods, $pos, 1) ne ':') {
				my $f = substr($mods, $pos++, 1);
				$f =~ /\A[1gW]\z/ or die "unknown flag `$f' for :S\n";
				$flag{$f} = 1;
			}
			my $done;
			my @word = $flag{W} ? ($val) : split ' ', $val;
			for my $w (@word) {
				next if $flag{1} && $done;
				my $r = _replace($w, $old, \@new, $bol, $eol, $flag{g});
				defined $r or next;
				$w = $r;
				$done = 1;
			}
			$val = join ' ', @word;
		} else {
			(my $name = substr($mods, $start)) =~ s/:.*//s;
			die "unknown modifier :$name\n";
		}
		if ($pos < $len) {
			if (substr($mods, $pos, 1) ne ':') {
				(my $name = substr($mods, $start)) =~ s/:.*//s;
				die "unknown modifier :$name\n";
			}
			$pos++;
			$pos < $len or die "empty modifier\n";
		}
	}
	$val;
}

1;
