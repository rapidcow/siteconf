package RdKw::WwW::GenLib;

use 5.006;
use strict;
use warnings;
use parent qw( Exporter );

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

=head1 NAME

RdKw::WwW::GenLib - static web-site generation library

=head1 SYNOPSIS

    use RdKw::WwW::GenLib qw( load_state location locator );

    # in a `render' script: what the template sees is up to you
    my ($D, $O) = load_state($B);       # ${B}/MY/{config,option}.mk
    my $where = location($D, $bpath);   # where in the site this page is

    my %O = (%$O, location => $where);  # [% O.location %]
    my %V = (
    	D => $D,                        # [% D.b %]
    	O => \%O,                       # [% O.base_url %]
    	locate => locator(\%O, $where), # [% locate('x') %]
    );
    unless ($tt->process($if, \%V, $of)) {
    	die "[TT] ", $tt->error();
    }

=cut

use File::Basename qw( dirname basename );
use File::Compare ();
use File::Spec ();
use URI ();
use URI::Escape qw( uri_unescape );

our @EXPORT_OK = qw(
	locate locator relapath
	parse_base
	read_make write_make update_file load_state
	read_deps
	location
);

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

=item B<locator> \%O, I<location>

Returns a function, to be handed to TT2 as C<locate>, that is B<locate>
as seen from the page at I<location> (see B<location>), taking just
I<spec>.  Nothing else is done to I<spec>; whatever else a site wants
done to its URLs (such as spelling out C<index.html>) is for it to wrap
around this.

=cut

sub locator {
	my ($O, $location) = @_;
	sub {
		@_ == 1 or die "usage: [% locate PATH %]\n";
		locate($O, $location, @_);
	};
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
$Me: site_url has an nonempty path ($path), and
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

=item B<read_make> I<file>

This reads user-configured B<MY/*.mk> files.
They're kind of like DOS-INI / GNU libconfini, but
well... dumber.  Namely, we implement no escapes,
and whitespaces are heartlessly stripped.  And
certainly no line continuation.  We also want to
see C<=>, which is admittedly unnecessary, but
that's what we call ourselves: read L<make(1)>-like
declarations.  Helps keep the mind sane. ;D

=cut

sub read_make
{
	local ($_, $.);
	my ($file) = @_;

	open my $fh, '<', $file or die "read_make: open <$file: $!\n";
	binmode $fh, ':encoding(UTF-8)';

	my %O;
	while (<$fh>) {
		next if /^\s*#/ or /^\s*$/;
		my ($k, $v) = split /=/, $_, 2;
		defined $v or die "read_make: $file line $.: no `='\n";
		$k =~ s/^\s+|\s+$//g;
		$v =~ s/^\s+|\s+$//g;
		$O{$k} = $v;
	}

	close $fh;
	%O;
}

=item B<update_file> I<file>, I<text>

Replace I<file> with I<text> (characters, written as UTF-8) -- but
only if that would change anything.  Preserving the mtime means a
reconfiguration that changes nothing will not rebuild the world.
Returns C<"created">, C<"updated"> or the empty string (unchanged).

=cut

sub update_file
{
	my ($file, $text) = @_;
	my $tmp = File::Spec->catfile(dirname($file), 'tmp-' . basename($file));

	open my $fh, '>:encoding(UTF-8)', $tmp
		or die "update_file: open >$tmp: $!\n";
	print $fh $text or die "update_file: write >$tmp: $!\n";
	close $fh or die "update_file: write >$tmp: $!\n";

	my $exists = -e $file;
	if ($exists && File::Compare::compare($tmp, $file) == 0) {
		unlink $tmp;
		return '';
	}
	rename $tmp, $file or die "update_file: mv $tmp $file: $!\n";
	$exists ? 'updated' : 'created';
}

=item B<write_make> I<file>, \%vars, I<prog>

The reverse of B<read_make>, through B<update_file>.  Keys are
sorted by length, then alphabetically.  I<prog> is credited in the
header comment.

=cut

sub write_make
{
	my ($file, $H, $prog) = @_;
	my $text = "#\n# configured by `$prog'\n#\n";
	for my $k (sort { length($a) <=> length($b) || $a cmp $b } keys %$H) {
		my $v = defined $H->{$k} ? $H->{$k} : '';
		$k =~ /\A[^\s=#]+\z/ or die "write_make: bad name: $k\n";
		$v =~ /[\r\n]/ and die "write_make: $k: value has a newline\n";
		$text .= "$k=\t$v\n";
	}
	update_file($file, $text);
}

=item B<load_state> I<B>

Reads C<${B}/MY/config.mk> and C<${B}/MY/option.mk> and returns
two hash references, I<D> and I<O>.  Dies kindly if you have not
configured.

=cut

sub load_state
{
	my ($B) = @_;
	$B = '.' unless defined $B and length $B;
	my @h;
	for my $f (qw( config option )) {
		my $file = "$B/MY/$f.mk";
		-f $file or die <<RUSH;
error: You have not configured! (no $file)
error: You should ./configure first. ;)
RUSH
		push @h, { read_make($file) };
	}
	@h;
}

=item B<location> \%D, I<bpath>

Where in the site the file I<bpath> is, i.e. its path relative to
C<${B}/${b}>.  This is what C<O.location> is.  I<bpath> is spelled
as the rules spell it, as seen from the source tree.

=cut

sub location
{
	my ($D, $bpath) = @_;
	my $root = File::Spec->canonpath("$D->{B}/$D->{b}");
	my $path = File::Spec->canonpath($bpath);
	$root = '' if $root eq '.';
	if (length $root) {
		index($path, "$root/") == 0
			or die "location: $bpath is not under $root\n";
		substr($path, 0, length($root) + 1) = '';
	}
	$path;
}

=item B<read_deps> I<file>

This is an ambitious one.  Essentially, we're trying
to propose a framework for a lean, but robust build
dependency specification.  This function itself doesn't
do much, but it reads/parses outgoing edges of what's
conceptually a I<dependency graph>.  Here's how.

=over

=item *

We have the reflexive node name called B<HAVE>.
This is a unique value; you cannot be Heisenberg.

=item *

Dependency B<NEED> is just normal dependency.
Its absence would cause any attempts at building
the target explode on the spot.  Such fellas are
called hard-dependency retronymically due to...

=item *

Soft-dependency B<WANT> conceptually means that the
transformation rule responsible for producing some
target from this node I<can> utilize this resource
but will degrade accordingly if it is absent.  In
practice, soft-dependencies are checked at configuration
time, and if it is missing, it is removed from the
dependency list, optionally emitting a warning.

=back

The names are returned as written: they are paths from the project
root, in which C<${a}> and C<${b}> and the like mean what they mean
to L<siteconf(1)>, which does the expanding.  So a page may say

   # HAVE: ${a}/index.html
   # NEED: ${b}/style.css

This function returns a hash map:

   [%#
   # HAVE: ethan
   # WANT: art music
   # WANT: 2-draw
   # NEED: puterz!!!
   -%]
   # WANT: jork-off :,<

becomes

   {
      HAVE => "ethan",
      WANT => [ "art", "music", "2-draw" ],
      NEED => [ "puterz!!!" ],
   }

The header is found within the first few lines, and ends at the
first line that is not another header line.  For this reason,
you won't see my evil desires following the TT2 closing tag...

=cut

sub read_deps {
	local ($_, $.);
	my ($file) = @_;
	my $onit = 0;
	my $I = {};

	open my $fh, '<', $file or die "read_deps: open $file: $!\n";
	binmode $fh, ':encoding(UTF-8)';

	while (<$fh>) {
		chomp;
		# Common comment chars:
		#   #  (UNIX sh, scripting languages)
		#   ;  (BIND zone, DOS-INI, Lisp, ledger)
		#   *  (C89/ANSI/K&R /* ... */)
		#   // (C++, Java, C99 line-comment)
		#   "  (vimscript)
		#   '  (VBScript (aughhhhhh!!! >n<!))
		#   -- (lua)
		#   %  (TeX, lilypond)
		#   REM, @REM  (BASIC, DOS batch; any case)
		#   :: (DOS batch, the label that is not)
		# A space is necessary both due to my
		# subjective aesthetics and preventing
		# false positives (e.g. a quoted string)
		if (/^\s*(?:#|;|\*|\/\/|"|'|--|%|\@?(?i:rem)|::) (HAVE|WANT|NEED):/g) {
			my $type = $1;
			my @list = /\S+/g;
			$onit = 1;
			next unless @list;

			if ($type eq 'HAVE') {
				die "read_deps: $file line $.: You HAVE too many.\n"
					if @list > 1 or exists $I->{$type};
				$I->{HAVE} = $list[0];
			} else {
				push @{$I->{$type}}, @list;
			}
			next;
		}
		# Not a header line: that is the end of it,
		# or we never found one, and it is a long
		# way down to look for one.
		last if $onit or $. >= 32;
	}

	close $fh;
	%$I;
}

=back

=cut

1;
