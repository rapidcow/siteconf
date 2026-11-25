package RdKw::WwW::GenGenLib;

use 5.008;
use strict;
use warnings;

use version;
our $VERSION = '0.01_00';
$VERSION = version->parse( $VERSION );

use Exporter ();
our @ISA = qw( Exporter );

=head1 NAME

WwW::GenGenLib - general-purpose generation utilities

=head1 SYNOPSIS

    use RdKw::WwW::GenGenLib qw( load_state );

    my %S = load_state($B);        # ${B}/MY/{config,option}.mk
    my $D = $S{config};
    my $O = $S{option};

=head1 DESCRIPTION

This module has been stripped down to the core of the build
system and now operates without web-specific libraries (i.e.,
L<URI> and L<URI::Escape>).  For the web-specific parts see
L<RdKw::WwW::GenLib>.

File names are character strings, as is everything else: they are
spelled as L<RdKw::I18N::CodeSets> says (L<RdKw::I18N::CodeSets/filesys>
of C<< RdKw::I18N::CodeSets->locale >>) only on their way to the system,
and a name that cannot be spelled there is an error.
What is I<in> the files is always UTF-8.

What we say (when we die) is said in the language of the locale, from
the catalogs of the C<siteconf> text domain, if
L<RdKw::WwW::SiteConf::L10N> says where they are and
L<Locale::Messages> is there to read them; and as it is written, if
not, or if no catalog has it.  The names in it are said as
L<RdKw::I18N::CodeSets> says: C<< RdKw::I18N::CodeSets->locale >>, or

    local $RdKw::I18N::CodeSets::LOCALE
        = RdKw::I18N::CodeSets->new(diag => 'ascii');

=cut

use Encode ();
use File::Basename qw( basename dirname );
use File::Compare ();
use File::Spec;
use File::Temp ();
use IO::Handle ();

# Import locale and set up gettext.
use RdKw::I18N::CodeSets ();
use RdKw::I18N::CodeSets::Functions qw( diag to_fs tagmsg );
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

sub _status { $! = 0; $? = shift; @_; }

our @EXPORT_OK = qw(
	read_make write_make update_file load_state
	read_deps norm_deps norm_dep subs_deps subs_dep
	escape_vars escape_var
	escape_deps escape_dep
	unescape_vars unescape_var
	scan_string
	unescape_deps unescape_deps
	split_dep walk_deps follow_ok
	enroot uproot
	read_manifest
);

# POSIX white space since [[:space:]] is too broad.
# (This is the same character set used in SiteConf.pm)
my $SP = '\t\n\cK\f\r ';

=head1 ROUTINES

=over

=item B<read_make> I<file>[, prog => 'read_make']

This reads user-configured B<MY/*.mk> files.
They're kind of like DOS-INI / GNU libconfini, but
well... dumber.  Namely, there is no line continuation,
and whitespaces are heartlessly stripped.  And
certainly no comments but whole lines.  We also want to
see C<=>, which is admittedly unnecessary, but
that's what we call ourselves: read L<make(1)>-like
declarations.  Helps keep the mind sane. ;D

A value says the characters it cannot spell, as a header does:
C<${U+0020}> is a space and C<${$}> a C<$> (see L</unescape_vars>).
Code points above U+10FFFF are accepted as-is; invalidate them if you care
about only the valid Unicode code points.

Errors are prefixed with I<prog>, else C<'read_make'>.
The I<prog> option and escaped values were added in 0.0100.

=cut

{
	my $nil = +{};

	sub _getkwds
	{
		my ($args) = @_;
		@$args && ref($args->[-1]) eq 'HASH' ? pop @$args : $nil;
	}

	sub _getprog
	{
		my ($kwds, $default) = @_;
		exists $kwds->{prog} ? $kwds->{prog} : $default;
	}
}

sub read_make
{
	local ($_, $.);
	my ($file, %opt) = @_;
	my $prog = _getprog(\%opt, 'read_make');
	my $kwds = { prog => $prog };

	open my $fh, '<', to_fs($file, $kwds)
		or die tagmsg($prog => diag(__(
			"cannot open file %q: %m"), $file));
	binmode $fh, ':encoding(UTF-8)';

	my %O;
	while (<$fh>) {
		next if /^\s*#/ or /^\s*$/;
		my ($k, $v) = split /=/, $_, 2;
		defined $v or die _status 0, tagmsg($prog => diag(__(
			"%#q line %d: missing `='"), $file, $.));
		$k =~ s/^[$SP]+|[$SP]+$//g;
		$v =~ s/^[$SP]+|[$SP]+$//g;
		my $text = unescape_vars($v);  # no $kwds
		$O{$k} = $text;
	}

	close $fh;
	%O;
}

=item B<write_make> I<file>, \%vars[, prog => 'write_make']

The reverse of L</read_make>, through L</update_file>.  Keys are
sorted by length, then alphabetically.  Values are escaped by
L</escape_vars>.  There is no header: I<prog> is only for errors.

Errors are prefixed with I<prog>, else C<'write_make'>.
The I<prog> option and escaped values were added in 0.0100.

=cut

sub write_make
{
	my ($file, $H, %opt) = @_;
	my $prog = _getprog(\%opt, 'write_make');
	# quoting with $cs->diag in case $prog contains
	# a newline, and breaks the whole file for us.
	my $text = "";
	for my $k (sort { length($a) <=> length($b) || $a cmp $b } keys %$H) {
		my $v = defined $H->{$k} ? $H->{$k} : '';
		$k =~ /\A[^\s=#]+\z/ or die _status 0, tagmsg(
			# HEY!  by bad we mean the make variable name contains
			# metacharacters which should not exist in a legal name.
			# (Not your "legal name", of course, i mean a name that
			# is allowed... like IL-legal in the sense of invalid.
			# (but let's not get into the topic of identity crisis...
			# we're talking about SYNTACTICALLY invalid names here.))
			$prog => diag(__("bad name: %q"), $k));
		$text .= "$k=\t" . escape_vars($v) . "\n";  # no $opt
	}
	update_file($file, $text, prog => $prog);
}

=item B<escape_vars> I<value>, ...

=item B<escape_var> I<value>

I<value> as one line of a B<MY/*.mk> file can hold it, which is as it is
but for what a line, a shell reading it, or a person reading it could
take for something else.  A character that is a control, a format
character (a zero-width joiner, a bidirectional override), a private use
or surrogate code point, or any white space (even a no-break space)
is C<${U+XXXX}>, and so is a space at either end of the value or next to
another space.  A space with something else on both sides is just a space,
and every other character, including those of any script, is itself.
A C<$> is C<${$}> if a C<{> comes next, so that it cannot be taken for the
start of an escape; any other C<$> is just a C<$>.

This is much less than what L</escape_deps> does, which escapes whatever
means something to make, a shell or a header, because a file made for
L</read_make> (and a shell loop that reads a line at a time) does not
need to say any of that.  Names are never escaped.

Added in 0.0100.  EXPERIMENTAL.

=cut

sub escape_vars
{
	my $opt = _getkwds(\@_);
	wantarray ? map { escape_var($_, %$opt) } @_ : escape_var($_[0], %$opt);
}

sub escape_var
{
	my ($v) = @_;
	return undef unless defined $v;
	my $n = length $v;
	my $out = '';
	for my $i (0 .. $n - 1) {
		my $c = substr $v, $i, 1;
		if ($c eq ' ') {
			$out .= $i > 0 && $i < $n - 1
				&& substr($v, $i - 1, 1) ne ' ' && substr($v, $i + 1, 1) ne ' '
				? ' ' : '${U+0020}';
		} elsif ($c eq '$') {
			$out .= substr($v, $i + 1, 1) eq '{' ? '${$}' : '$';
		} elsif ($c =~ /[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Z}]/) {
			$out .= sprintf '${U+%04X}', ord $c;
		} else {
			$out .= $c;
		}
	}
	$out;
}

=item B<unescape_vars> I<text>, ...

=item B<unescape_var> I<text>

The inverse of L</escape_vars>: C<${U+XXXX}> (one to eight hexadecimal
digits, and C<u+> will do) is the character of that code point, and
C<${$}> is a C<$>.  Anything else, a C<$> that comes before a C<{>
included, is itself.

Code points above U+10FFFF are accepted as-is;
invalidation of invalid Unicode code points
would have to be done externally.

Added in 0.0100.

=cut

sub unescape_vars
{
	# Ignore up to one trailing HASH.  (See escape_vars)
	my %opt = @_ && ref($_[-1]) eq 'HASH' ? %{+pop} : ();
	wantarray ? map { unescape_var($_, %opt) } @_ : unescape_var($_[0], %opt);
}

sub unescape_var
{
	my ($text) = @_;
	$text =~ s{\$\{(?:(\$)|[Uu]\+([0-9A-Fa-f]{1,8})|"((?:[^"\\]|\\.)*)")\}}{
		my $all = $&;
		defined $1 ? '$'
		: defined $2 ? chr hex $2
		: do { my $s = _decode_string($3); defined $s ? $s : $all }
	}gesx;
	$text;
}

=item B<scan_string> I<text>[, prog => 'scan_string']

If I<text> starts with a string literal, return its characters and what
follows its closing quote; else return nothing.  A string is in double
quotes, and a backslash begins one of these:

    \a \b \t \n \v \f \r \e   the control characters of C
    \s                        a space
    \x{hex}                   a code point (1 to 8 hex digits)
    \\ \"                     a backslash, a double quote

Anything else after a backslash, a code point above U+10FFFF, and a
string that is not closed are errors.  Nothing else is special in
there, so C<$> and C<}> are as they are.

A string is spelled C<${"...">C<}> in a value or a name, where it is the
same as C<${U+...}> for each of its characters, or the C<"..."> alone,
where the caller says it is one.  L</unescape_vars> and L</norm_deps>
read C<${"...">C<}>; a string that is malformed is left as it is by
the former.  The code point of C<\x{...}> may be written
C<\x{3b1}> as well as C<\x{03B1}>.

Added in 0.0100.

=cut

my %ESCAPE = (
	a => "\a", b => "\b", t => "\t", n => "\n", v => "\cK", f => "\f",
	r => "\r", e => "\e", s => ' ', '\\' => '\\', '"' => '"',
);

# The characters of the inside of a string literal, or undef if it
# has an escape that is not one
sub _decode_string
{
	my ($body) = @_;
	my $bad;
	$body =~ s{\\(?:x\{([0-9A-Fa-f]{1,8})\}|(.))}{
		defined $1 ? (hex($1) <= 0x10FFFF ? chr hex $1 : ($bad = 1, ''))
		: exists $ESCAPE{$2} ? $ESCAPE{$2}
		: ($bad = 1, '')
	}gesx;
	$bad ? undef : $body;
}

sub scan_string
{
	my ($text, %opt) = @_;
	my $prog = _getprog(\%opt, 'scan_string');
	$text =~ /\A"/ or return;
	$text =~ /\A"((?:[^"\\]|\\.)*)"/s or die _status 0, tagmsg($prog => diag(__(
		"unterminated string: %q"), $text));
	my ($body, $end) = ($1, $+[0]);
	my $s = _decode_string($body);
	defined $s or die _status 0, tagmsg($prog => diag(__(
		"bad escape or code point in string: %q"), substr($text, 0, $end)));
	($s, substr($text, $end));
}

=item B<update_file> I<file>, I<text>[, prog => I<prog>, raw => 1]

Replace I<file> with I<text> (characters, written as UTF-8) -- but
only if that would change anything.  Preserving the mtime means a
reconfiguration that changes nothing will not rebuild the world.
Return 2 if the file is created, 1 if updated, and 0 if not modified.

With C<< raw => 1 >>, I<text> is bytes.  They are written as they are.
Use this for a Makefile: its names are spelled by
L<RdKw::I18N::CodeSets/to_fs>, and make reads them as bytes.

This function is not compatible with the original B<update_file>
in genlib 0.0000; use
C<< $r > 1 ? 'created' : $r ? 'updated' : 'unchanged' >>.

The I<prog> and raw options were added in 0.0100.

=cut

sub update_file
{
	my ($file, $text, %opt) = @_;
	my $prog = _getprog(\%opt, 'update_file');
	my $layer = $opt{raw} ? ':raw' : ':encoding(UTF-8)';
	#
	# The temporary file is in the same directory, so that the rename
	# is atomic.  File::Temp gives it a name that no file has (a redo
	# file, say, which a fixed name like tmp-Makefile could be), and
	# creates it with O_EXCL.
	#
	my $dir = dirname($file);
	my $file_fs = to_fs($file, { prog => $prog });
	my $dir_fs = to_fs($dir, { prog => $prog });
	# (the template is ASCII, so the name is the same in bytes; but it
	# must be bytes, or perl would upgrade $dir_fs when it joins them)
	(my $template = '.' . basename($file)) =~ s/[^A-Za-z0-9._-]/_/g;
	utf8::downgrade($template);
	my ($fh, $tmp_fs) = eval {
		File::Temp::tempfile("$template.XXXXXXXX", DIR => $dir_fs, UNLINK => 0)
	} or die tagmsg($prog => diag(__(
		"cannot create file %q: %m"), File::Spec->catfile($dir, "$template.XXXXXXXX")));
	my $tmp = File::Spec->catfile($dir, basename($tmp_fs));
	my $fail = sub {
		my $msg = diag(@_);
		# (close and unlink may change $!; die with the first error)
		my $errno = 0 + $!;
		close $fh;
		unlink $tmp_fs;
		$! = $errno;
		die tagmsg($prog => $msg);
	};
	# File::Temp makes it 0600; a file we write is as open() would make it
	chmod 0666 & ~umask, $tmp_fs
		or $fail->(__("cannot write file %q: %m"), $tmp);
	binmode $fh, $layer
		or $fail->(__("cannot write file %q: %m"), $tmp);
	print $fh $text
		or $fail->(__("cannot write file %q: %m"), $tmp);
	close $fh
		or $fail->(__("cannot write file %q: %m"), $tmp);

	my $exists = -e $file_fs;
	if ($exists && File::Compare::compare($tmp_fs, $file_fs) == 0) {
		unlink $tmp_fs;
		return 0;  # make it numeric so `>' isn't upset
	}
	rename $tmp_fs, $file_fs
		or $fail->(__("cannot rename %q to %q: %m"), $tmp, $file);
	$exists ? 1 : 2;
}

=item B<load_state> I<B>[, prog => 'load_state']

Read F<${B}/MY/config.mk> and F<${B}/MY/option.mk> and return
an associative map of hashes, keyed by I<config> and I<option>.
Dies kindly if you have not configured.

This function not compatible with the original B<load_state>
in genlib 0.0000.  Namely, you must obtain C<\%D> and C<\%O>
by name.

The I<prog> option was added in 0.0100.

=cut

sub load_state
{
	my ($Bdir, %opt) = @_;
	my $prog = _getprog(\%opt, 'load_state');
	$Bdir = '.' unless defined $Bdir and length $Bdir;

	my %S;
	foreach (qw( config option )) {
		my $file = File::Spec->catfile($Bdir, "MY/$_.mk");
		$file = File::Spec->canonpath($file);
		unless (-f to_fs($file, { prog => $prog })) {
			die _status 0, tagmsg($prog => diag(__(
			# HEY!  Keep a winky face in the translation ;)
			# This message is likely to get seen by newbies,
			# so we want to keep it fun.
			"You have not configured! (no %q)\n"
			. "You should ./configure first. ;)"), $file));
		}
		$S{$_} = { read_make($file, prog => $prog) };
	}
	%S;
}

=item B<read_deps> I<file>[, forgive_missing => 0, prog => 'read_deps', lines => \%lines]

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

=item *

B<JUST-NEED> and B<JUST-WANT> are the same two, but what they name
is only a name: its own header is not read, and what it declares
is not followed.  They are for files that are not text (a pickled
binary, say), or whose header is none of our business.
(Added in 0.0100.)

=back

This function returns a hash map.  So:

   [%#
   # HAVE: ethan
   # WANT: art music
   # WANT: 2-draw
   # NEED: puterz!!!
   -%]
   # WANT: jork-off :,<

becomes

   (
      HAVE => "ethan",
      WANT => [ "art", "music", "2-draw" ],
      NEED => [ "puterz!!!" ],
   )

The header is found within the first few lines, and ends at the
first line that is not another header line.  For this reason,
you won't see my evil desires following the TT2 closing tag...

A header line is a comment (in any of the styles listed in the
source, after anything at all, as in C<x = 1  # NEED: ...>), blanks, a field
name and a colon.  The fields are C<HAVE>, C<NEED> and C<WANT>, in
capitals; a field of any other name (C<USE:>, C<vim:>, C<Have:>)
is someone else's, and is skipped: it neither ends the header nor
begins one.  The names a field lists are separated by blanks (spaces
and tabs) and by nothing else, so a no-break space is part of a name.
A line with C<${"> may have a string, C<${"...">C<}>, in a name, with
blanks and colons in it: C<NEED: ${"two words"}> is one name.  Names
end at the end of the line, or at a colon (touching the last
name or not), as a vim modeline does; what follows is not read.
That is what makes a block comment work:

   <!-- NEED: to-get-some-sleep: -->
   /*** WANT: evil${U+0020}file: ***/
   [%# HAVE: ${a}/abc :  # and anything else at all -%]

and so a colon in a name is C<${U+003A}> (see L</escape_deps>).

The names undergo no parameter expansions.  So:

   # HAVE: ${a}/index.html
   # NEED: ${B}/${b}/style.css

becomes

   (
     HAVE => '${a}/index.html',
     NEED => '${B}/${b}/index.html',
   )

But you may use L</norm_deps> and L</subs_deps> to
interpret those.

The scan for header goes on for a while (about 32 lines)
but stops at the first line that is malformed UTF-8.
This means that B<read_deps> is safe to call on binary
files.  (Prior to 0.0001, B<read_deps> would choke on
malformed UTF-8.)

I<file> is a character string (see L</DESCRIPTION>);
one that cannot be named on the file system is an error,
forgiven or not.

I<forgive_missing> is an optional boolean that decides
whether a file that cannot be opened to begin with can
be forgiven.  Defaults to 0 (false; do not forgive).

C<lines> is an optional reference to a hash, which is filled with
the line numbers of what is read, in the shape of the result: a
number for C<HAVE>, and for each other field a list as long as its
names, the line of each.  For example, a C<NEED> of two names on
line 3 and one on line 4 gives C<< NEED => [3, 3, 4] >>.  What it
held before is gone.

The I<forgive_missing> option was added in 0.0002.
The I<prog> and I<lines> options were added in 0.0100.

=cut

# A header line, as read_deps sees it: a comment, then a field
# name and a colon.  What other tools put in their headers looks like
# this too, and should, so that the one does not end the other's.
my $header_field = qr{
	\A .*?			# anything at all before the comment,
				# as in `x = 1  # NEED: ...' -- but stop
				# first comment that works is the one,
				# so we're not chasing the comments after
				# this comment.
	(?:
		\#		# UNIX sh, scripting languages
	|	;		# BIND zone, DOS-INI, Lisp, ledger
	|	\*		# C89/ANSI/K&R /* ... */
	|	//		# C++, Java, C99 line-comment
	|	"		# vimscript
	|	'		# VBScript (aughhhhhh!!! >n<!)
	|	--		# lua, SQL (also covers SGML!)
	|	%		# TeX, lilypond
	|	(?<![A-Za-z0-9_])
		\@?(?i:rem)	# BASIC, DOS batch; any case (but a word
				# of its own; e.g. not theorem or harem.)
	|	::		# DOS batch, the empty label?
	)			# This one is powerful beyond DOS,
		# actually, since you can end with the same sequence at the
		# end; so this gives you symmetry on even the esoteric block
		# comments not listed here!  e.g.:
		#
		#    {-:: HAVE: file.hs  ::-}     Haskell
		#    #=:: HAVE: file.jl  ::=#     Julia
		#    #|:: HAVE: file.scm ::|#     Scheme
		#
		# (Of course, you could also just use the line comment
		# syntax in those respective languages. ;)
	[\t ]+			# Blanks are necessary both due to my
				# subjective aesthetics and preventing
				# false positives (e.g. a quoted string or
				# part of a word, in the case of REMember.)
	([A-Za-z._-]+)		# The field: any name, in any case (ours
				# are HAVE, NEED, WANT, and only so)
	[\t ]* : [\t ]*		# ... and then what it says.
}x;

sub read_deps
{
	local ($_, $.);
	my ($file, %opt) = @_;
	my $missing_ok = $opt{forgive_missing};
	my $prog = _getprog(\%opt, 'read_deps');
	my $onit = 0;
	my %I = ();
	my $L = $opt{lines} || {};
	%$L = ();

	# (A name we cannot even spell is not missing: it is an error.)
	open (my $fh, '<', to_fs($file, { prog => $prog })) or ($missing_ok
		? return ()
		: die tagmsg($prog => diag(__("cannot open file %q: %m"), $file)));

	while (<$fh>) {
		# Not UTF-8 is not text, and so has no header: give up on the
		# spot, and quietly (the :encoding layer would warn per line).
		# A line break is never inside a character, so this is safe.
		eval { $_ = Encode::decode('UTF-8', $_, Encode::FB_CROAK()); 1 }
			or last;
		# (a CR of a CRLF is not part of the last name)
		s/\r?\n\z//;
		if (/$header_field/gc) {
			my $type = $1;
			# What is not ours (USE:, vim:, NEED-ONLY: for now,
			# and HAVE in any other case) is skipped: it does not
			# end the header, nor does it begin one.
			unless ($type =~ /\A(?:HAVE|WANT|NEED|JUST-WANT|JUST-NEED)\z/) {
				last if !$onit and $. >= 32;
				next;
			}
			# Names are split at blanks (space and tab), and only
			# at blanks: anything else is part of a name, but for
			# a colon, which ends them (as it does a vim modeline),
			# so that what closes a comment is not one.
			my @list = /\$\{"/
				? _words(substr($_, pos), blank => '\t ', colon => 1)
				: /\G[\t ]*([^\t :]+)/gc;
			$onit = 1;
			next unless @list;

			if ($type eq 'HAVE') {
				die _status 0, tagmsg($prog => diag(__(
					# HEY!  Keep the second-person pronoun.
					# It's mildly sarcastic (with that period
					# at the end) -- imagine a "wtf" stare as
					# in... "you HAVE too many.  The hell are
					# you tryin' to be, the whole universe?"
					# Like that.
					"%#q line %d: You HAVE too many."), $file, $.))
					if @list > 1 or exists $I{$type};
				$I{HAVE} = $list[0];
				$L->{HAVE} = $.;
			} else {
				push @{$I{$type}}, @list;
				push @{$L->{$type}}, ($.) x @list;
			}
			next;
		}
		# Not a header line: that is the end of it,
		# or we never found one, and it is a long
		# way down to look for one.
		last if $onit or $. >= 32;
	}

	if ($fh->error()) {
		die tagmsg($prog => diag(__("cannot read file %q: %m"), $file));
	}

	close $fh;
	%I;
}

=item B<enroot> I<root>, I<path>...

Plant I<path> onto the I<root> directory.  Up to one
trailing slash is removed from I<root> (provided the
slash isn't the only character), and the empty string
or C<"."> is the identity which preserves I<path>.

The variadic form is defined by a left-fold on the
binary form.  That is, C<enroot(A, B, C)> is computed
as C<enroot(enroot(A, B), C)>.  When no paths are
provided, B<enroot> simply appends a trailing slash
to I<root>.

Added in 0.0002.

=item B<uproot> I<root>, I<path>

Un-plant I<path> from the I<root> directory, if
possible.  This function returns the empty string
if I<root> and I<path> are equivalent modulo at
most one trailing slash, undef if I<root> and
I<path> are unrelated, and a non-empty string if
I<root> is a prefix of I<path> such that
C<enroot(root, uproot(root, path))> equals
C<path>.  A leading slash is part of the root: a
relative root never contains an absolute path, nor
the other way around.  (What is returned is merely
the rest, and may begin with a slash itself, as in
C<uproot('a', 'a//x')>.)

Added in 0.0002.

=cut

sub enroot
{
	my ($path, @path) = @_;
	@path or @path = ("");
	foreach my $comp (@path) {
		if ($path eq '' || $path eq '.') {
			unless ($comp =~ /\A\//) {
				$path = $comp;
				next;
			}
			$path = '.';
		}
		$path =~ s/\/\z//;
		$path .= '/' . $comp;
	}
	return $path;
}

sub uproot
{
	my ($base, $path) = @_;
	if ($base eq '' || $base eq '.') {
		return $path unless $path =~ /\A\//;
		return;
	}
	$base =~ s/\/\z//;
	# The lone root slash "/" may be mistaken for a
	# courteous trailing slash, but it's really not.
	if ($base eq '' && $path !~ /\A\//) {
		return;
	}
	return "" if ($path eq $base);
	if ($path =~ s/\A\Q$base\E\///) {
		return $path;
	}
	return;
}

=item B<norm_dep> I<spec>, [ strict => 0, pass_thru => 0 ]

=item B<norm_deps> I<spec>... { strict => 0, pass_thru => 0 }

Symbolically normalize dependency specification,
as read by L</read_deps>.  Variables are demarcated
with braces, and the C<'${A}/'> prefix is stripped.

In the case that I<spec> is literally C<'${A}'>,
return the empty string.

In list context; in scalar context, normalize just
the first argument.

A variable is C<${name}>, where the name is anything up to
the closing brace (there are no escapes in there), or C<$n>
for a single word character as it is in L<siteconf(1)>; and
C<$$> is a literal C<$>.  C<${U+>I<hex>C<}> is not a variable
but a character, by its code point: 1 to 8 hex digits, in any
case (and so is the C<U>), up to C<FFFFFFFF> (it fits an unsigned
32-bit int; Unicode validity is not checked); it is normalized to
C<${U+>I<hex>C<}>, in capitals and of at least 4 digits, and the
character is what L</subs_deps> gives (see L</escape_deps>).  A string,
C<${"...">C<}>, is spelled as L</escape_deps> would spell its characters:
C<${"hello world"}> is C<hello${U+0020}world>.  Any
other C<$> is malformed: a trailing one, an unterminated C<${>,
an empty C<${}>, a C<${U+>I<hex>C<}> that is no code point, a C<$>
before a C<}> or a C<.>, and so on.  The optional C<strict>
option decides whether to die on malformed input, or to
replace unpaired dollar signs
with literal dollar signs.  Defaults to C<< strict => 0 >>.

With C<< pass_thru => 1 >>, unrecognized dollar signs are
left unchanged, for example C<$@>, rather than escaped.
Recognized variables and the project root are still normalized.
C<strict> takes precedence: malformed input still dies even
with C<pass_thru> enabled.  Defaults to C<< pass_thru => 0 >>.

Added in 0.0002.  The option C<pass_thru> was added in 0.0003,
and the C<${U+>I<hex>C<}> escapes were added in 0.0100.

=cut

# The code point that `U+hex' is, if it is one
#
# (We can accept leading zeros provided that
# they don't overflow a 32-bit int.)
sub _code_point
{
	my ($name) = @_;
	# 8 hex digits caps this at 0xFFFFFFFF, i.e. it always
	# fits in an unsigned 32-bit int; Unicode validity is
	# not our concern here, so nothing above this is checked.
	return unless $name =~ /\A[Uu]\+0*([0-9A-Fa-f]{1,8})\z/;
	hex $1;
}

sub norm_deps
{
	my $kwds = _getkwds(\@_);
	my $prog = _getprog($kwds, 'norm_deps');
	my $keep = $kwds->{pass_thru};
	my (@ret);
	foreach (@_) {
		my $out = '';
		pos($_) = 0;
		for (;;) {
			if (/\G([^\$]+)/gc) {
				$out .= $1;
			} elsif (/\G\$\{([Uu]\+[^}]*)\}/gc) {
				# Unicode character, not a variable.
				# (I never liked variables with + anyways. >:P)
				my $name = $1;
				my $n = _code_point($name);
				if (defined $n) {
					$out .= sprintf '${U+%04X}', $n;
				} else {
					$kwds->{strict} and die _status 0, tagmsg($prog => diag(__(
						"cannot normalize %q: bad Unicode code point %s"),
						$_, "\${$name}"));
					$out .= ($keep ? '$' : '${$}') . "{$name}";
				}
			} elsif (/\G\$\{("(?:[^"\\]|\\.)*")\}/gc) {
				# string literal
				my $str = $1;
				my $s = _decode_string(substr $str, 1, -1);
				if (defined $s) {
					# Typically these guys are good citizens
					# with occasional dangerous characters,
					# so give them a second chance and only
					# re-escape the specials and wide chars.
					$out .= escape_deps($s);
				} else {
					$kwds->{strict} and die _status 0, tagmsg($prog => diag(__(
						"cannot normalize %q: bad escape or code point in string %s"),
						$_, $str));
					$out .= ($keep ? '$' : '${$}') . "{$str}";
				}
			} elsif (/\G\$\{"/gc) {
				# Runaway string literal?
				$kwds->{strict} and die _status 0, tagmsg($prog => diag(__(
					"cannot normalize %q: bad string after \${"), $_));
				$out .= ($keep ? '$' : '${$}') . '{"';
			} elsif (/\G\$\{([^}]+)\}/gc) {
				$out .= "\${$1}";
			} elsif (/\G\$([\w\$])/gc) {
				# includes "$$"
				$out .= "\${$1}";
			} elsif (/\G\$/gc) {
				# Anything else is not a variable we recognize.
				if ($kwds->{strict}) {
					die _status 0, tagmsg($prog => diag(__(
						"cannot normalize %q: trailing \$"), $_))
						if /\G\z/gc;
					die _status 0, tagmsg($prog => diag(__(
						"cannot normalize %q: unterminated or empty \${"), $_))
						if /\G\{/gc;
					die _status 0, tagmsg($prog => diag(__("stray \$ in %q"), $_));
				}
				$out .= ($keep ? '$' : '${$}');
			} else {
				last;
			}
		}
		my $path = uproot('${A}', $out);
		$out = $path if defined $path;
		return $out unless wantarray;
		push @ret, $out;
	}
	@ret;
}

sub norm_dep
{
	my ($spec, %kwds) = @_;
	scalar norm_deps($spec, \%kwds);
}

=item B<subs_dep> \%D, I<spec>, [ strict => 0, on_missing => 'vanish' ]

=item B<subs_deps> \%D, I<spec>... { strict => 0, on_missing => 'vanish' }

Substitute dependency specifications with
the given definitions.  L</norm_deps> is
called to normalize the specification (and
is given the options, if any).  The map is
optional since 0.0100, so this could be an
inverse operation of L</escape_deps>.
C<strict> is passed to L</norm_deps>.
The C<on_missing> option (added in 0.0100) may be one of:

=over

=item C<"croak">

Missing variables result in an error.

=item C<"vanish"> (default)

Missing variables are the empty string.

=item a unary callback

Missing variables invoke the callback to get
a string suitable for substitution.

=back

A variable that makes up a whole path segment
and is followed by a slash is a directory, and
is planted like L</enroot> does: it keeps one
trailing slash, so C<${a}/x> is F<site/x> when
C<${a}> is either C<site> or C<site/>, and a
C<.> or empty one vanishes altogether (just
F<x>).  Everywhere else it is plain text, and
nothing is special about C<.> there: C<x-${a}/y>
is F<x-./y>, and C<${B}/${p}> is just
C<< enroot($B) . $p >>.

A C<${U+...}> is its character, and is nothing more:
C<${U+002E}${U+002E}/> is F<../> as much as C<../> is,
and C<${U+002F}> is a slash like any other.
These character escapes were added in 0.0100.

Added in 0.0002.

=cut

sub _bad_subs
{
	my ($prog) = @_;
	sub {
		# HEY!  "bad" means undefined in the substitution
		# map here -- think `set -u' in your Bourne shell.
		# It is technically also double entendre, since
		# the map-less version of subs_deps is used as a
		# pure decode operation... in which case a named
		# substitution that is not an escape at all as "bad"
		# as in, "wait.... that's illegal."
		die _status 0, tagmsg($prog, diag(__("bad substitution: %s"), "\${$_[0]}"));
	};
}

sub subs_deps
{
	my $kwds = _getkwds(\@_);
	my $prog = _getprog($kwds, 'subs_deps');
	my $D = shift;
	# pass_thru is not for us :)  Unpaired $s
	# will round-trip when we substitute them.
	if ($kwds->{pass_thru}) {
		$kwds = +{ %$kwds };
		delete $kwds->{pass_thru};
	}
	my $fb;
	if (defined $kwds->{on_missing}) {
		$kwds = +{ %$kwds };
		my $missing = delete $kwds->{on_missing};
		if (ref($missing) eq 'CODE') {
			$fb = $missing;
		} elsif ($missing eq 'croak') {
			$fb = _bad_subs($prog);
		} else {
			# $missing could be "vanish"
			# but i don't really care.
		}
	}
	my @ret;
	foreach my $spec (norm_deps(@_, $kwds)) {
		my $out = '';
		# Whether we are at the start of a path segment
		my $seg = 1;
		# Normalized: every "$" that is left is followed by "{name}"
SSS:		while ($spec =~ /\G([^\$]*)\$\{([^}]+)\}/gc) {
			my $name = $2;
			if (length $1) {
				$out .= $1;
				$seg = ($1 =~ /\/\z/);
			}
			if ($name eq '$') {
				# "$$" escapes "$"
				$out .= $name;
				$seg = 0;
				next SSS;
			}
			if ($name =~ /\AU\+([0-9A-F]+)\z/) {
				# a character (normalized: it is a code point)
				my $c = chr hex $1;
				$out .= $c;
				$seg = $c eq '/';
				next SSS;
			}
			my $value = $D ? $D->{$name} : undef;
			# Undefined = empty to us.
			unless (defined $value) {
				$value = $fb ? $fb->($name) : '';
			}
			if ($seg && $spec =~ /\G\//gc) {
				# A whole directory: it brings its own trailing slash
				# (or none, if it is the current directory)
				$out .= enroot($value);
				next SSS;
			}
			# Anything else is just text
			$out .= $value;
			$seg = 0;
		}
		$out .= substr($spec, pos($spec) || 0);
		return $out unless wantarray;
		push @ret, $out;
	}
	@ret;
}

sub subs_dep
{
	my ($D, $spec, %opt) = @_;
	scalar subs_deps($D, $spec, \%opt);
}

=item B<escape_deps> I<name>... { unicode => 0, unicode_space => 0 }

=item B<escape_dep> I<name>, [ unicode => 0, unicode_space => 0 ]

Quote a literal name as a spec that is read as that name and
nothing else: L</subs_deps> (without definitions, or with any)
gives it back, L</split_dep> finds no root in it, and
L</read_deps> reads it as one name, whatever is in it.  The
escaped dependency specifications are returned as a copy (in
scalar context, the first).

What is safe is left as it is: letters and digits (in ASCII), and
C</ . _ - + @>.  A C<$> is C<${$}>, and anything else is
C<${U+>I<hex>C<}>, its code point (as in C<${U+0020}> for a space,
or C<${U+003A}> for a colon).  That is any metacharacter (of the
shell, make, a header line) and any comment character, whether or
not it means anything where the name is going: C<;>, C<#>, C<:>,
C<%>, quotes, globs, braces and the like.  It is uglier than it has
to be, but it does not need to know where it is going.

With C<< unicode => 1 >>, what is above C<~> is safe too, but for
controls (C<DEL> and the C1s), surrogates, the line and
paragraph separators, and white space (such as the no-break
space).  C<< unicode_space => 1 >> leaves that white space alone
as well, though there is little good in a name that looks like
it is two; a space, tab or vertical space is escaped regardless.

Added in 0.0100.

=cut

# What is left as it is: what a file name is made of, and nothing
# that means anything to a shell, make or a header line
my $ESCAPE = qr/[^A-Za-z0-9\/._+\@-]/;

sub _escape_char
{
	my ($c, $opt) = @_;
	return '${$}' if $c eq '$';
	return $c if $opt->{unicode} && ord($c) > 0x7E
		&& $c !~ /[\p{Cc}\p{Cs}\x{2028}\x{2029}]/
		&& ($opt->{unicode_space} || $c !~ /\p{Space}/);
	sprintf '${U+%04X}', ord $c;
}

sub escape_deps
{
	my $opt = ref($_[-1]) eq 'HASH' ? pop : {};
	my @s = @_;
	s/($ESCAPE)/_escape_char($1, $opt)/ge for @s;
	wantarray ? @s : $s[0];
}

sub escape_dep
{
	my ($s, %opt) = @_;
	scalar escape_deps($s, \%opt);
}

=item B<split_dep> I<spec>

Split a dependency specification into its symbolic
root and the remainder of the path.  The symbolic
root consists of C</>-separated segments entirely
derived from a variable.

Added in 0.0002.

=cut

sub split_dep
{
	my $spec = norm_deps($_[0]);
#	pos($spec) = 0;
	my $root = '';
	# (an escaped $, ${$}, is no variable, and so no root; nor
	# is any other character, ${U+...})
	while ($spec =~ /\G(\$\{(?!\$\}|U\+)[^}]+\})(\/|\z)/gc) {
		$root .= '/' if length($root);
		$root .= $1;
	}
	my $rest = substr($spec, pos($spec) || 0);
	($root, $rest);
}

=item B<walk_deps> \%D, I<spec>... { graph => \%G, follow => \&ok, mandatory => 0, terminal => 0 }

Enumerate all dependencies of a path specification.
C<\%D> is a required map of variable definitions.
C<\%G> is an optional map for normalized path
specifications associated with their header values.
Every specification is normalized (see L</norm_deps>)
on its way in, so the list returned and the keys of
C<\%G> are normalized too, and C<$a/x> and C<${a}/x>
are the same entry.

Return the dependencies (NEEDs, JUST-NEEDs, WANTs and
JUST-WANTs) of the given path specifications pooled,
recursively with the dependents of all relative
non-build dependents, and update C<\%G> as a side-effect.
This list is deduplicated symbolically, and files that
are either not regular files, are build dependents, or
lack headers are returned without their dependents.

Note that build dependents are solely identified
symbolically by the C<${B}> prefix.

A C<JUST-NEED> or C<JUST-WANT> lists the file without
opening it or adding it to C<\%G>.  An ordinary dependency
on the same file can still expand it.
With C<< mandatory => 1 >>, C<WANT> and C<JUST-WANT>
lines are dropped.  With C<< terminal => 1 >>, only
leaf nodes are returned.  These are nodes with no outgoing
edges in the walk, including files reached only through
C<JUST-NEED> or C<JUST-WANT>.

Every specification reached for expansion is a key of C<\%G>,
so the graph is a negative cache too.  Its value is:

=over

=item *

the header (what L</read_deps> returns, as a hash
reference), for a regular file that was read;

=item *

an empty hash, for what has no header to read: a file
without one, or one that is not a regular file, or is
not there at all (so a WANT that is missing is still in
the list, and is not looked for again);

=item *

C<undef>, for what C<follow> denied: it is listed, but
was never read (see L</follow_ok>).

=back

So C<exists> says only that the walk came to it; whether
it was read is whether the value is defined.  A graph
passed to another walk is taken as it is, and what it
holds is not read or followed again.

Added in 0.0002.  The options C<mandatory> and C<terminal>
were added in 0.0100.

=item B<follow_ok> \%D, I<spec>

Default implementation of the C<follow> option.
Entries denied this way are permanently cached
as C<undef> in the graph.

Added in 0.0002.

=cut

sub follow_ok
{
	my ($D, $spec) = @_;
	my ($root, $path) = split_dep($spec);
	# Build dependents are terminal
	return if $root =~ /\A\$\{B\}(?:\/|\z)/;
	my $name = subs_deps($D, $path);
	# Nor does a path that has left the root lead anywhere safe,
	# however it got there: not just "/etc" but also ${a}//etc
	return if $name =~ m{\A/};
	# Directory traversal is bad: this part we must
	# also expand fully ahead of time, since it may be
	# concatenated from seemingly innocent components
	# (e.g. ${A}${A} when ${A} is (almost) always ".")
	return if $name =~ /(?:\A|\/)\.\.(?:\/|\z)/;
	1;
}

sub walk_deps
{
	my $kwds = _getkwds(\@_);
	my $D = shift;
	my $G = $kwds->{graph} || +{};
	my $ok = $kwds->{follow} || \&follow_ok;
	# Put NEEDs before WANTs.  (The fields are
	# listed in reverse since @todo is a FIFO.)
	#
	# And non-JUST before JUST, since they are
	# typically non-derivative / binary assets.
	my @fields = reverse qw( NEED JUST-NEED ),
		($kwds->{mandatory} ? () : qw( WANT JUST-WANT ));

	# Everything is kept in normalized form, so that $a/x and ${a}/x
	# are one and the same node, whichever way a header spells it.
	# A spec is listed (in @pool) once, but it is expanded (read, and
	# its own deps followed) the first time it is met as anything but
	# a JUST: it may be met as one first, and as a NEED later.
	my (@pool, %pool, %expanded, %inner);
	my @todo = map { [ $_, 0 ] } reverse norm_deps(@_);

	while (@todo) {
		my ($spec, $term) = @{ pop @todo };
		push @pool, $spec unless $pool{$spec}++;
		next if $term or $expanded{$spec}++;
		my $Imap = do {
			if (exists $G->{$spec}) {
				$G->{$spec};
			} elsif ($ok->($D, $spec)) {
				# Only a regular file has a header to read: a directory
				# opens fine but cannot be read, and a FIFO would hang
				my $file = subs_deps($D, $spec);
				$G->{$spec} = -f to_fs($file, { prog => 'walk_deps' })
					? { read_deps($file, forgive_missing => 1) }
					: {};
			} else {
				$G->{$spec} = undef;
			}
		};
		if (defined $Imap) {
			for my $field (@fields) {
				my @dep = norm_deps(@{ $Imap->{$field} || [] }) or next;
				$inner{$spec} = 1;
				my $just = ($field =~ /\AJUST-/);
				push @todo, map { [ $_, $just ] } reverse @dep;
			}
		}
	}

	$kwds->{terminal} ? grep({ !$inner{$_} } @pool) : @pool;
}

# `${"..."}' as one unit, with whatever is in it
my $STRING_UNIT = qr/\$\{"(?:[^"\\]|\\.)*"\}/s;

# The words of a line that has a `${"', where a string may have blanks
# (and a colon, and a #) in it.  `blank' is the inside of a character
# class; with `colon', a colon ends the words; with `hash', so does a
# # that begins a word.
sub _words
{
	my ($text, %o) = @_;
	my $b = $o{blank};
	my $word = $o{colon} ? qr/(?:$STRING_UNIT|[^$b:])+/ : qr/(?:$STRING_UNIT|[^$b])+/;
	my @w;
	pos($text) = 0;
	for (;;) {
		$text =~ /\G[$b]+/gc;
		last if $o{hash} && $text =~ /\G#/gc;
		$text =~ /\G($word)/gc or last;
		push @w, $1;
	}
	@w;
}

=item B<read_manifest> \%D, I<file>[, { prog => 'read_manifest' }]

The goals in I<file> (a name, or a reference to the text), as an
L<RdKw::WwW::GenGenLib::Manifest>, which says what that looks like.
The names in it are unescaped, as L</subs_dep> does without definitions:
C<${U+0020}> is a space, and C<${$}> a C<$>.  C<\%D> is required, as
for L</walk_deps>, and is substituted in the paths of C<INCLUDE> only;
those are opened from the current directory, which is taken to be
C<${A}>.  An empty map reads a manifest that includes nothing that
needs a definition.

Errors are prefixed with I<prog>, else C<'read_manifest'>.

Added in 0.0100.

=cut

sub read_manifest
{
	require RdKw::WwW::GenGenLib::Manifest;
	RdKw::WwW::GenGenLib::Manifest->read(@_);
}

=back

=cut

1;
