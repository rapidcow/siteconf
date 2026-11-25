package RdKw::WwW::GenLib;

use 5.008;
use strict;
use warnings;

use version;
our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

use Exporter ();
our @ISA = qw( Exporter );

=head1 NAME

RdKw::WwW::GenLib - static web site generation library

=head1 SYNOPSIS

    # in a `render' script...
    use RdKw::WwW::GenGenLib 0.0002 qw(
        read_deps load_state
        norm_deps subs_deps uproot );
    use RdKw::WwW::GenLib 0.0203 qw(
        parse_base locate );
    use Template;

    # (Parser omitted...)
    my ($Bdir, $apath, $bpath) = parse(@ARGV);

    my %S = load_state($Bdir);
    my ($D, $O) = @S{qw( config option )};

    # Usually this is checked at `./configure -O'
    # time, but it doesn't hurt to check again...
    parse_base($O);

    my %I = read_deps($apath);
    # relapath doesn't do well with the leading slash,
    # though people may have a habit of including it...
    (my $target = do {
        my ($name, $norm, $real);
        # Try symbolic prefix
        if (defined ($name = uproot('${a}',
            $norm = norm_deps($I{HAVE}))))
            { subs_deps($D, $name); }
        # Try literal prefix
        elsif (defined ($name = uproot($D->{a},
            $real = subs_deps($D, $norm))))
            { $name; }
        else
        {
            my $aka = $real eq $I{HAVE} ? "" : " (aka `$real')";
            die "E: $apath: HAVE `$I{HAVE}'$aka not "
                . "under \${a} (aka `$D->{a}')\n";
        }
    }) =~ s/\A\/+//;

    my %v = (
        D => $D,
        O => $O,
        locate => sub { locate($O, $target, @_); },
        location => $target,
    );
    my $tt = Template->new({
        ENCODING => 'UTF-8',
        INCLUDE_PATH => [ '.', $D->{a} ],
    })
        or die "[TT] ", $Template::ERROR, "\n";
    $tt->process($apath, \%v, $bpath,
        { binmode => ':encoding(UTF-8)' })
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
use URI::file ();
use URI::Escape qw( uri_unescape );

# Import locale and set up gettext.
use RdKw::I18N::CodeSets ();
use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

our @EXPORT_OK = qw(
	locate
	relapath joinpath
	file2uri uri2file
	parse_base
);

=head1 ROUTINES

Subroutines are not exported unless imported
on demand.

=over

=item B<locate> \%O, I<base>, I<spec>...

A link from the page at I<base> to I<spec>.  This is the C<locate>
function of the web preset's renderer (see
L<RdKw::WwW::SiteConf::Render/WEB PRESET>), which passes the options
as C<\%O> and the page's location as I<base>.

I<base> and I<spec> are URI paths, so a character that is not ASCII
must be escaped (L</file2uri> does this).  I<base> is from the root of
the site, such as C<blog/post.html>.  What I<spec> is from depends on
how it begins:

=over

=item C<x> (none of the below)

From the root of the site.  The result is relative to I<base>:
C<locate($O, 'blog/post.html', 'index.html')> is C<../index.html>.

=item C<./x> or C<../x>

From I<base>, and the result is relative to I<base>: from
C<blog/post.html>, C<./pic.png> is C<pic.png>.

=item C</x>

From C<base_url>, as an absolute path: with C<base_url> C</~me/>,
C</x> is C</~me/x>.

=item C<//x>

From C<site_url> and C<base_url>, as a full URL: with C<site_url>
C<https://example.org> as well, C<//x> is C<https://example.org/~me/x>,
and C<//> is C<https://example.org/~me/>.

=back

A trailing slash names a directory, and none names a file, as in a web
browser.  From C<blog/post.html>, C<blog/> is C<.>, the directory the
page is in, while C<blog> is C<../blog>, a file named C<blog> in the root of
the site.  Link to a directory with its slash.  The empty I<spec>
is the root of the site: C<..> from C<blog/post.html>, and C<.> from
C<index.html>.

When I<spec> is I<base> itself, the result is the empty string.  That
is a link to the same page, and it stays one when a query or a
fragment follows it: C<locate($O, $here, $here) . '?page=2'> is
C<?page=2>, which asks this page again with another query, wherever
the page is.  A page with a form, or one made by a CGI script, can link
to itself this way.

More than one I<spec> are joined in order: each is resolved against
the one before it, as a relative link would be.  So C<a/>, C<b> is
C<a/b>, while C<a>, C<b> is C<b>, and C<locate($O, $base, '//',
'blog/')> is the URL of F<blog/>.

Relative specifications are preserved since 0.0202.  Variadic
specifications, an optional options hash (defaulting C<site_url>
to the empty string and C<base_url> to C</>), and relative components following an absolute
or site-relative specification are supported since 0.0203.

=cut

sub locate {
	my ($O, $base, $spec, @spec) = @_;
	defined $spec or $spec = '';

	if ($spec =~ s!\A/(/?)!!) {
		my $slash = !!$1;
		# aurl = absolute
		# burl = base URL
		my ($aurl, $burl);
		defined ($burl = $O ? $O->{base_url}
			: undef) or $burl = "/";
		$burl =~ s/\A\///;
		my $path = '/' . joinpath($burl, '.')
			. joinpath(($spec =~ /\A\.\.?(?:\/|\z)/)
				? ($base, $spec, @spec)
				: ($spec, @spec));
		if ($slash) {
			defined ($aurl = $O ? $O->{site_url}
				: undef) or $aurl = "";
			return $aurl . $path;
		}
		return $path;
	}

	# Relative path passthrough
	my $path = ($spec =~ /\A\.\.?(?:\/|\z)/)
		? joinpath($base, $spec, @spec)
		: joinpath("", $spec, @spec);
	relapath($path => $base);
}

=item B<relapath> I<path>, I<base>

Write a path to I<path> relative to I<base>.  It's as
simple as that.  Of course, like web browsers, there is
the notion of the "current directory".  That is, the
trailing slash (all of them!) will be honored, and the
lack of one will be taken to indicate a directory
(formally a path with an empty trailing segment).

Since 0.0203, leading C<./> has no special treatment and trailing
slashes are no longer collapsed.

Since 0.03_00, if I<path> is the directory that I<base> is in, the
result is C<.> rather than the empty string (which, like in a web
browser, means I<base> itself).  So I<base> joined with the result
is always I<path>.

=cut

sub relapath
{
	my ($path, $base) = @_;
	# split gives () for an empty string; that is one empty segment.
	my @path = length $path ? split('/', $path, -1) : ('');
	my @base = length $base ? split('/', $base, -1) : ('');

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
	pop @rest if $upupup && @rest && !grep { length } @rest;
	#
	# Empty means "this very document": every segment matched,
	# and @rest is ().  With no `..', a lone empty segment means
	# $path is the directory $base is in, so say so with a dot.
	#
	@rest = ('.') if !$upupup && @rest == 1 && $rest[0] eq '';
	join '/', ('..') x $upupup, @rest;
}

=item B<joinpath> I<base>, I<spec>...

Reverse operation of L</relapath>.  This is
typically called something like "resolve" in
URL libraries, but I call things my way. >:)

Added in 0.0203.

=cut

sub joinpath
{
	my $base = shift;
	my @base = split('/', $base, -1);
	foreach my $spec (@_) {
		my @path = split('/', $spec, -1);
		@path or next;
		# All segments in the base path
		# are semantically significant.
		# We won't question that...
		pop @base if @base;
		my $dot = 0;
COMP:		while (@path) {
			my $comp = $path[0];
			if ($comp eq '..') {
				pop @base;
				shift @path;
				$dot = 1;
				next;
			}
			if ($comp eq '.') {
				shift @path;
				$dot = 1;
				next;
			}
			while (@path
				&& $path[0] ne '..'
				&& $path[0] ne '.')
			{
				# Keep $dot set only while the last non-
				# empty segment was `.' or `..'.  Empty
				# segments preserve it, but must not set
				# it again.  Any intervening non-empty
				# segment resets this permanently.
				$dot = $dot && $path[0] eq '';
				push @base, shift @path;
			}
		}
		# Path under directory
		push @base, ('') if $dot && @base;
	}
	join '/', @base;
}

=item B<file2uri> I<file>[, os => 'Unix', prog => 'file2uri' ]

Write the file name I<file> as a URI.  A relative name gives a
relative URI path; an absolute one gives a C<file:> URI.  I<file>
is a Unicode string (not the octets the file system uses), and
its characters are written as UTF-8 escapes: C<r\x{e9}> gives
C<r%C3%A9>.  It dies if I<file> cannot be encoded as UTF-8
(e.g. a lone surrogate).

I<os> is the system whose file names I<file> follows, as
in L<URI::file>; it defaults to C<'Unix'>; pass C<$^O>
or C<undef> if you explicitly want it in your operating system's
representation (though this may break various parts of GenGenLib).
For example, C<a\b> on C<MSWin32> gives C<a/b>.

Added in 0.03_00.

=cut

# The code sets of URIs (file names in UTF-8, whatever the file system
# says), for file2uri and uri2file only; made when first needed
my $cs_utf8;
sub _cs_utf8 { $cs_utf8 ||= RdKw::I18N::CodeSets->new(filesys => 'UTF-8') }

sub file2uri
{
	my ($file, %kwds) = @_;
	my $os = !exists $kwds{os} ? 'Unix' :
		defined $kwds{os} ? $kwds{os} : $^O;
	my $prog = exists $kwds{prog} ? $kwds{prog} : 'file2uri';
	# URI::file->new alone escapes Latin-1 characters
	# as one Latin-1 octet or as UTF-8, depending on the
	# internal utf8 flag (see URI::Escape::escape_char).
	# We have control over what we accept.  Encode it to
	# UTF-8 so it is safe for URI::file->new to consume.
	# (Notably, this does not obey the filesys codeset,
	# since this is a URI and URIs are always UTF-8. ;)
	my $octets = _cs_utf8()->to_fs($file, { prog => $prog });
	URI::file->new($octets, $os)->as_string;
}

=item B<uri2file> I<uri>[, os => 'Unix', prog => 'uri2file' ]

Reverse operation of L</file2uri>: the file name, as a Unicode
string, that I<uri> names on I<os> (default C<'Unix'> like
L</file2uri>.  Pass C<$^O> or C<undef> if you explicitly want it
in your operating system's representation.)
Escapes are decoded as UTF-8, in either case of hex digits.
Die if I<uri> names no file on I<os> (e.g. C<a%2Fb>, a name
with a slash in it), or if the escapes are not UTF-8 (e.g. C<r%E9>).

Added in 0.03_00.

=cut

sub uri2file
{
	my ($uri, %kwds) = @_;
	my $os = !exists $kwds{os} ? 'Unix' :
		defined $kwds{os} ? $kwds{os} : $^O;
	my $prog = exists $kwds{prog} ? $kwds{prog} : 'uri2file';
	my $octets = URI->new($uri, 'file')->file($os);
	defined $octets or die _status 0, tagmsg($prog => diag(__(
		# HEY! %#q is the operating system.
		"%q: URI not representable in %#q"),
		$uri, $os));
	_cs_utf8()->un_fs($octets, { prog => $prog });
}

=item B<parse_base> \%O[, prog => 'parse_base' ]

Sanitize, normalize, and whine about user-supplied
I<base_url> and I<site_url>.

Optionally I<prog> supplies a prefix for error messages,
which was previously hard-coded to the string C<'parse_base'>.
The I<prog> option was added in 0.0300.

=cut

sub parse_base
{
	my ($D, %kwds) = @_;
	my $prog = exists $kwds{prog} ? $kwds{prog} : 'parse_base';
	my ($base_url, $site_url);

	# site_url cannot be derived, so it is required.
	defined $D->{site_url} and $D->{site_url} ne ''
		or die _status 0, tagmsg($prog => __("missing site_url"));
	$site_url = URI->new($D->{site_url});

	# Any scheme will do (http, file, gemini, ...),
	# but there must be one.
	defined $site_url->scheme
		or die _status 0, tagmsg($prog => diag(__(
		"site_url has no URI scheme: %q"),
		$D->{site_url}));

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
			die _status 0, tagmsg($prog => __("base_url must begin with a slash"));
		}
		unless ($site_url->path eq '' or $base_url eq $site_url->path) {
			# This is probably one of the more grave cases;
			# so report it thoroughly to the console.
			die _status 0, tagmsg($prog => diag(__(
				# HEY!  the first %q is the path of site_url, and the
				# second is base_url
				"site_url has a nonempty path (%q), and\n"
				. "is inconsistent with base_url (%q)"),
				$site_url->path, $base_url));
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
				or die _status 0, tagmsg($prog => __(
					"base_url cannot be inferred from site_url,\n"
					. "as the latter has an empty path"));
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
