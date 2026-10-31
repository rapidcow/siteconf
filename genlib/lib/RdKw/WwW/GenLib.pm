package RdKw::WwW::GenLib;

use 5.006;
use strict;
use warnings;
use parent qw( Exporter );

our $VERSION = '0.00_00';  # NOT DONE
$VERSION = eval $VERSION;

=head1 NAME

RdKw::WwW::GenLib - static web-site generation library

=head1 SYNOPSIS

    use RdKw::WwW::GenLib qw( locate );

    my $if = "${a}/file.ext";
    my $of = "${B}/${b}/file.ext";

    my %D = read_make("${B}/MY/config.mk");
    my %O = read_make("${B}/MY/option.mk");
    my %F = ( locate => sub {
    	@_ == 1 or die Template::Exception->new(
    		"usage" => "[% locate PATH %]");
    	my $where = $_[0];
    	if ($O{base_url} !~ m{^https?://}i) {
    		$_[0] .= 'index.html' if $_[0] =~ m{/$};
    	}
    	locate(\%O, $O{location}, $where);
    } );

    my %V = ( D => \%D, O => \%O, %F );
    unless ($tt->process($if, \%V), $of) {
    	die "[TT] ", $tt->error();
    }

=cut

use URI::Escape qw( uri_unescape );
our @EXPORT_OK = qw( locate relapath );

=head1 ROUTINES

Subroutines are not exported unless imported
on demand.

=over

=item B<locate> \%D, I<base>, I<spec>

Implements the synonymous TT2 function.

=cut

sub locate {
	my ($D, $base, $spec) = @_;

	if ($spec =~ s!^//!!) {
		return join '', (
			$D->{site_url},
			$D->{base_url},
			$spec);
	}

	if ($spec =~ s!^/!!) {
		return join '', (
			$D->{base_url},
			$spec);
	}

	relapath($spec => $base);
}

=item B<relapath> I<path>, I<base>

Write a path to I<path> relative to I<base>.  It's as
simple as that.  Of course, like web browsers, there is
the notion of the "current directory".  That is, the
trailing slash will be honored, and the lack of one
will be taken to indicate an omissible filename.

Two conveniences on top of that:

=over

=item *

A leading C<.> segment on I<path> is dropped, once.  So
C<.> and C<./> both mean the root (as does the empty string),
and C<./x> means C<x>.  Only the first dot is special:
C<./.> and C<a/./b> keep the dot that comes later.

=item *

A C<..> is already a directory, so a lone trailing slash
after the last C<..> is redundant and is omitted: C<../..>
rather than C<../../>.  A second slash asks for it back
(C<../>).  Any subsequent slashes are idempotent.

=back

=cut

sub relapath {
	my ($path, $base) = @_;
	#
	# (contributed by Anthropic Claude)
	# Done as a pre-processing step so that `.//'
	# leaves `/' behind, i.e., one empty segment
	# per extra slash.  (This is also so that a
	# `./' prefix serves as a no-op prefix -- but
	# only when it is spelled as . and not %2F.)
	#
	$path =~ s!^[.](?:/|$)!!;
	my @path = split('/', $path, -1);
	my @base = split('/', $base, -1);

	my $comm = 0;
COMM:	while () {
		#
		# (adapted from Anthropic Claude's patch)
		# When the operands are related by being
		# strict sub-paths, only the last index we
		# visited was actually common, not where
		# $comm is at presently.  The one exception
		# being if we never checked any path at all
		# (i.e. $comm == 0, and one operand is root).
		#
		unless ($comm < @path) {
			--($comm) if $comm && $comm < @base;
			last COMM;
		}
		unless ($comm < @base) {
			--($comm) if $comm && $comm < @path;
			last COMM;
		}
		my $pathpart = uri_unescape ($path[$comm]);
		my $basepart = uri_unescape ($base[$comm]);
		last COMM if $pathpart ne $basepart;
	}
	continue {
		++($comm);
	}

	#
	# This accounts for the trailing slash in @base, where
	# we're "leaving" a directory with a single file whose
	# name is the empty string, e.g. ('dir', 'path', '').
	#
	# And of course Perl is forgiving when it comes to
	# @list x $NEGATIVE, but in the case where all paths
	# line up, make $upupup at least 0.
	#
	my $upupup = (@base - $comm || 1) - 1;
	#
	# The next bit is self-explanatory.  We just append the
	# non-common parts after the common part is over...
	# (again, trailing slash will be dealt with, if it ever
	# shows up in $path -- that will just be an empty
	# component concatenated with a bunch of "/"'s.)
	#
	my @rest = @path[$comm..$#path];
	#
	# (contributed by Anthropic Claude)
	# Only `..'s and empty segments: the first empty segment
	# is the trailing slash that `..' does not need.
	#
	if (grep { length } @rest) {
		# After a name, a trailing slash is only a hint that it
		# is a directory; asking for it twice changes nothing.
		pop @rest while @rest > 1 && !length($rest[-1])
			&& !length($rest[-2]);
	}
	elsif ($upupup && @rest) {
		# Just `..'s: the first slash is the one `..' does not
		# need, and any more than one are the same as one.
		@rest = @rest > 1 ? ('') : ();
	}
	join '/', ('..') x $upupup, @rest;
}

=back

=cut

1;
