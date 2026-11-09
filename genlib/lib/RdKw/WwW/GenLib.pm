package RdKw::WwW::GenLib;

use 5.006;
use strict;
use warnings;
use Exporter ();

our $VERSION = '0.02_03';
$VERSION = eval $VERSION;

=head1 NAME

RdKw::WwW::GenLib - static web-site generation library

=head1 SYNOPSIS

    # in a `render' script...
    use RdKw::WwW::GenGenLib qw( read_deps load_state );
    use RdKw::WwW::GenLib qw( locate );
    use Template;
    use Template::Exception;

    my ($B, $apath, $bpath) = parse(@ARGV);

    my %S = load_state($Bdir);
    my ($D, $O) = @S{qw( config option )};

    my %I = read_deps($apath);
    (my $L = $I{HAVE}) =~ s{\A(?:\$(?:\{A\}|A)/)?(?:\$(?:\{a\}|a)|\Q$D->{a}\E)/}{}
        or $D->{a} eq '.' or die "E: $apath: HAVE $I{HAVE} is not under \${a}\n";

    my %V = (
        D => $D,
        O => $O,
        locate => {
            @_ == 1 or die Template::Exception->new(usage => "[% locate PATH %]");
                locate($O, $L, @_);
            },
        location => $me,
    );
    $tt = Template->new({
        ENCODING => 'UTF-8',
        INCLUDE_PATH => [ '.', $D->{a} ],
    )
        or die "[TT] ", $Template::ERROR, "\n";
    $tt->process($apath, \%V, $bpath)
        or die "[TT] ", $tt->error();

=head1 DESCRIPTION

This module now holds the web-specific stuff only.
See L<RdKw::WwW::GenGenLib> for the subroutines
that have moved.

=cut

use File::Basename qw( dirname basename );
use File::Compare ();
use File::Spec ();
use URI ();
use URI::Escape qw( uri_unescape );

our @ISA = qw( Exporter );
our @EXPORT_OK = qw(
	locate
	relapath joinpath
	parse_base
);

=head1 ROUTINES

Subroutines are not exported unless imported
on demand.

=over

=item B<locate> \%O, I<base>, I<spec>

Implements the synonymous TT function.

=cut

sub locate {
	my ($O, $base, $spec) = @_;

	if ($spec =~ s!\A/(/?)!!) {
		my $slash = !!$1;
		(my $burl = $O->{base_url}) =~ s/\A\///;
		return ($slash ? $O->{site_url} : "")
			. '/' . joinpath($burl, '.')
			. joinpath(
			($spec eq '.' || $spec =~ /\A\.\.(?:\/|\z)/)
			? ($base, $spec)
			: ($spec =~ /\A\.(?:\/|\z)/)
			? ($base, $spec)
			: ($spec));
	}

	# Relative path passthrough
	($spec eq '.' || $spec =~ /\A\.\.(?:\/|\z)/)
		? $spec
	# Here "./" is stripped as a prefix, since
	# without it the path would be mistaken for
	# the full URL path.  You should pass "./"
	# twice if you want it preserved literally.
	# For example, "././run.cgi" => "./run.cgi".
		: ($spec =~ s/\A\.(?:\/|\z)//)
		? $spec
		: relapath($spec => $base);
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

=item B<joinpath> I<base>, I<spec>...

Reverse operation of B<relapath>.  This is
typically called something like "resolve" in
URL libraries, but I call things my way. >:)

=cut

sub joinpath
{
	my $base = shift;
	my @base = split('/', $base, -1);
	foreach my $path (@_) {
		my @path = split('/', $path, -1);
		@path or next;
		pop @base;
		my $dot = 0;
DOT:		while (@path) {
			my $comp = $path[0];
			if ($comp eq '..') {
				pop @base;
				$dot = 1;
				shift @path;
				next DOT;
			}
			last DOT if $dot;
			if ($comp eq '.') {
				shift @path;
				last DOT;
			}
			last DOT;
		}
		if (@path) {
			# Path under directory
			push @base, @path;
		} else {
			# Directory: append trailing slash
			push @base, ('');
		}
	}
	join '/', @base;
}

=item B<parse_base> \%O

Sanitize, normalize, and whine about user-supplied
I<base_url> and I<site_url>.

=cut

sub parse_base
{
	my ($D) = @_;
	my ($base_url, $site_url);
	my $Me = "parse_base";

	# site_url cannot be derived, so it is required.
	defined $D->{site_url} and $D->{site_url} ne ''
		or die "$Me: missing site_url\n";
	$site_url = URI->new($D->{site_url});

	{
		my $proto = $site_url->scheme;
		unless (defined $proto and grep { lc($proto) eq $_ } qw( file http https )) {
			die "$Me: site_url has no file or www URI scheme: $D->{site_url}\n";
		}
	}

	# There is basically no way to see an empty base_url
	# (given how `configure' usually provides a default),
	# so we treat the case of -Obase_url=/ as a request
	# from the user to explicitly inherit from site_url.
	#
	# We lose the check on domain-wide hosts, but I think
	# it is worth the convenience.
	if (defined $D->{base_url} and $D->{base_url} ne ''
		and $D->{base_url} ne '/'
	) {
		$base_url = $D->{base_url};
		unless ($base_url =~ m!^/!) {
			die "$Me: base_url must begin with a slash\n";
		}
		unless ($site_url->path eq '' or $base_url eq $site_url->path) {
			# This is probably one of the more grave cases;
			# so report it thoroughly to the console.
			my $path = $site_url->path;
			die <<EUGH;
$Me: site_url has a nonempty path ($path), and
$Me: is inconsistent with base_url ($base_url)
EUGH
		}
	} else {
		# An empty site_url path leaves nothing to inherit,
		# which is an error -- unless base_url is literally `/',
		# the one value that is both a request to inherit and
		# a perfectly good answer on its own.  Anything else
		# that lands here (unset, or empty) has no such excuse.
		$base_url = $site_url->path;
		if ($base_url eq '') {
			defined $D->{base_url} and $D->{base_url} eq '/'
				or die <<EUGH;
$Me: base_url cannot be inferred from site_url,
$Me: as the latter has an empty path
EUGH
			$base_url = '/';
		}
	}

	$site_url->fragment(undef);
	$site_url->query(undef);
	$site_url->path('');

	# Plain strings, so that what we write to MY/option.mk
	# and what we hand over to TT2 are one and the same.
	$D->{base_url} = $base_url;
	$D->{site_url} = "$site_url";
	# All is well
	1;
}

=back

=cut

1;
