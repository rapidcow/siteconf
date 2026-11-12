package RdKw::WwW::GenGenLib;

use 5.008;
use strict;
use warnings;
use Exporter ();

our $VERSION = '0.01_00';
$VERSION = eval $VERSION;

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
encoded to the file system's locale (see L<Encode::Locale>) only on
their way to the system, and a name that cannot be spelled there is
an error, never a guess.  What is I<in> the files is always UTF-8.

What we say (when we die) is said in the language of the locale, from
the catalogs of the C<gengenlib> text domain, if
L<RdKw::WwW::GenGenLib::L10N> says where they are and
L<Locale::Messages> is there to read them; and as it is written, if
not, or if no catalog has it.  The names in it are said as
L<RdKw::I18N::CodeSets> says: C<< RdKw::I18N::CodeSets->locale >>, or

    local $RdKw::I18N::CodeSets::LOCALE
        = RdKw::I18N::CodeSets->new(diag => 'ascii');

=cut

use utf8;
use Encode ();
use Encode::Locale ();
use IO::Handle ();
use File::Basename qw( basename dirname );
use File::Compare ();
use File::Spec;
use RdKw::I18N::CodeSets ();

# What we say is said in the language of the locale, if
# RdKw::WwW::GenGenLib::L10N says where the catalogs are (and
# Locale::Messages is there to read them); else, and for what no
# catalog has, as it is written.  What gettext gives back is UTF-8
# (we bind the domain so, whatever OUTPUT_CHARSET or the locale's
# codeset would say), and is decoded as such: as for the file
# system, CodeSets is not asked.  (The source is left as it is, or
# Encode would empty it -- and a literal cannot be emptied.)
BEGIN {
	my $CHECK = Encode::FB_CROAK() | Encode::LEAVE_SRC();
	my $domain;
	if (eval {
		require Locale::Messages;
		require RdKw::WwW::GenGenLib::L10N;
		$domain = $RdKw::WwW::GenGenLib::L10N::DOMAIN;
		Locale::Messages::bindtextdomain($domain,
			$RdKw::WwW::GenGenLib::L10N::LOCALEDIR);
		Locale::Messages::bind_textdomain_codeset($domain, 'UTF-8');
		1;
	}) {
		*__ = sub {
			Encode::decode('UTF-8', Locale::Messages::dgettext($domain,
				Encode::encode('UTF-8', $_[0], $CHECK)), $CHECK);
		};
		*__n = sub {
			Encode::decode('UTF-8', Locale::Messages::dngettext($domain,
				Encode::encode('UTF-8', $_[0], $CHECK),
				Encode::encode('UTF-8', $_[1], $CHECK), $_[2]), $CHECK);
		};
	}
	else {
		*__ = sub { $_[0] };
		*__n = sub { $_[2] == 1 ? $_[0] : $_[1] };
	}
}

# A message: %q is a name, %s as it is (see RdKw::I18N::CodeSets)
sub _diag
{
	RdKw::I18N::CodeSets->locale->diag(@_);
}

our @ISA = qw( Exporter );
our @EXPORT_OK = qw(
	read_make write_make
	update_file load_state
	read_deps
	norm_deps norm_dep
	subs_deps subs_dep
	escape_deps escape_dep
	split_dep walk_deps follow_ok
	enroot uproot
	to_fs un_fs
	read_manifest
);

=head1 ROUTINES

=over

=item B<to_fs> I<name>[, I<who>]

=item B<un_fs> I<bytes>[, I<who>]

I<name>, a character string, as the file system spells it
(C<locale_fs> of L<Encode::Locale>), or the other way around.  Dies
(saying I<who> did it, if given) if that cannot be done: we do not
make up names for files.

Added in 0.0100.

=cut

sub to_fs
{
	my ($name, $who) = @_;
	my $fs = eval { Encode::encode(locale_fs => $name,
		Encode::FB_CROAK() | Encode::LEAVE_SRC()) };
	defined $fs or die +(defined $who ? "$who: " : "")
		. _diag(__("cannot encode %s in current locale (%s)"),
			_perlqq($name), $Encode::Locale::ENCODING_LOCALE_FS) . "\n";
	$fs;
}

sub un_fs
{
	my ($fs, $who) = @_;
	my $name = eval { Encode::decode(locale_fs => $fs,
		Encode::FB_CROAK() | Encode::LEAVE_SRC()) };
	defined $name or die +(defined $who ? "$who: " : "")
		. _diag(__("cannot decode %s in current locale (%s)"),
			_perlqq($fs), $Encode::Locale::ENCODING_LOCALE_FS) . "\n";
	$name;
}

sub _perlqq
{
	require Data::Dumper;
	Data::Dumper->new(\@_)->Terse(1)->Indent(0)->Useqq(1)->Dump();
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

	open my $fh, '<', to_fs($file, 'read_make')
		or die _diag(__("read_make: cannot open file %q: %s"), $file, "$!") . "\n";
	binmode $fh, ':encoding(UTF-8)';

	my %O;
	while (<$fh>) {
		next if /^\s*#/ or /^\s*$/;
		my ($k, $v) = split /=/, $_, 2;
		defined $v or die _diag(__("read_make: %q line %s: no `='"), $file, $.) . "\n";
		$k =~ s/^\s+|\s+$//g;
		$v =~ s/^\s+|\s+$//g;
		$O{$k} = $v;
	}

	close $fh;
	%O;
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
		# HEY!  by bad we mean the make variable name contains
		# metacharacters which should not exist in a legal name.
		# (Not your "legal name", of course, i mean a name that
		# is allowed... like IL-legal in the sense of invalid.
		# (but let's not get into the topic of identity crisis...
		# we're talking about SYNTACTICALLY invalid names here.))
		$k =~ /\A[^\s=#]+\z/ or die _diag(__("write_make: bad name: %q"), $k) . "\n";
		$v =~ /[\r\n]/ and die _diag(__("write_make: %q: value has a newline"), $k) . "\n";
		$text .= "$k=\t$v\n";
	}
	update_file($file, $text);
}

=item B<update_file> I<file>, I<text>

Replace I<file> with I<text> (characters, written as UTF-8) -- but
only if that would change anything.  Preserving the mtime means a
reconfiguration that changes nothing will not rebuild the world.
Return 2 if the file is created, 1 if updated, and 0 if not modified.

This function is not compatible with the original B<update_file>
in genlib 0.0000; use
C<< $r > 1 ? 'created' : $r ? 'updated' : 'unchanged' >>.

=cut

sub update_file
{
	my ($file, $text) = @_;
	#
	# Try writing to the same file system to ensure atomicity.
	# Polluting directory is fine, since we usually own the
	# whole directory (MY/ over MY/*.mk) anyways...
	#
	my $tmp = File::Spec->catfile(dirname($file), 'tmp-' . basename($file));

	my ($tmp_fs, $file_fs) = map { to_fs($_, 'update_file') } $tmp, $file;

	open my $fh, '>:encoding(UTF-8)', $tmp_fs
		or die _diag(__("update_file: cannot create file %q: %s"), $tmp, "$!") . "\n";
	print $fh $text
		or die _diag(__("update_file: cannot write file %q: %s"), $tmp, "$!") . "\n";
	close $fh
		or die _diag(__("update_file: cannot write file %q: %s"), $tmp, "$!") . "\n";

	my $exists = -e $file_fs;
	if ($exists && File::Compare::compare($tmp_fs, $file_fs) == 0) {
		unlink $tmp_fs;
		return 0;  # make it numeric so `>' isn't upset
	}
	rename $tmp_fs, $file_fs or die _diag(__("update_file: cannot rename %q to %q: %s"),
		$tmp, $file, "$!") . "\n";
	$exists ? 1 : 2;
}

=item B<load_state> I<B>

Read C<${B}/MY/config.mk> and C<${B}/MY/option.mk> and return
an associative map of hashes, keyed by I<config> and I<option>.
Dies kindly if you have not configured.

This function not compatible with the original B<load_state>
in genlib 0.0000.  Namely, you must obtain C<\%D> and C<\%O>
by name.

=cut

sub load_state
{
	my ($Bdir) = @_;
	$Bdir = '.' unless defined $Bdir and length $Bdir;
	my %S;
	for my $f (qw( config option )) {
		my $file = "$Bdir/MY/$f.mk";
		-f to_fs($file, 'load_state')
			# HEY!  Keep a winky face in the translation ;)
			# This message is likely to get seen by newbies,
			# so we want to keep it fun.
			or die _diag(__(
			"error: You have not configured! (no %q)\n"
			. "error: You should ./configure first. ;)"), $file) . "\n";
		$S{$f} = { read_make($file) };
	}
	%S;
}

=item B<read_deps> I<file>, { forgive_missing => 0 }

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
They end at the end of the line, or at a colon (touching the last
name or not), as a vim modeline does; what follows is not read.
That is what makes a block comment work:

   <!-- NEED: to-get-some-sleep: -->
   /*** WANT: evil${U+0020}file: ***/
   [%# HAVE: ${a}/abc :  # and anything else at all -%]

and so a colon in a name is C<${U+003A}> (see B<escape_dep>).
(Since 0.0100; before, only C<HAVE>, C<NEED> and C<WANT> after
exactly one space were header lines, names were split at any
white space, and a colon was part of a name.)

The names undergo no parameter expansions.  So:

   # HAVE: ${a}/index.html
   # NEED: ${B}/${b}/style.css

becomes

   (
     HAVE => '${a}/index.html',
     NEED => '${B}/${b}/index.html',
   )

But you may use B<norm_deps> and B<subs_deps> to
interpret those.

The scan for header goes on for a while (about 32 lines)
but stops at the first line that is malformed UTF-8.
This means that B<read_deps> is safe to call on binary
files.  (This feature was added in 0.0001.)

I<file> is a character string (see B<to_fs>); one that cannot be
named in this locale is an error, forgiven or not.

C<forgive_missing> is an optional boolean that decides
whether a file that cannot be opened to begin with can
be forgiven.  Defaults to 0 (false; do not forgive).
(This option was added in 0.0002.)

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
	my ($file, $opt) = @_;
	my $missing_ok = $opt && $opt->{forgive_missing};
	my $onit = 0;
	my %I = ();

	# (A name we cannot even spell is not missing: it is an error.)
	open (my $fh, '<', to_fs($file, 'read_deps')) or ($missing_ok
		? return ()
		: die _diag(__("read_deps: cannot open file %q: %s"), $file, "$!") . "\n");

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
			unless ($type =~ /\A(?:HAVE|WANT|NEED)\z/) {
				last if !$onit and $. >= 32;
				next;
			}
			# Names are split at blanks (space and tab), and only
			# at blanks: anything else is part of a name, but for
			# a colon, which ends them (as it does a vim modeline),
			# so that what closes a comment is not one.
			my @list = /\G[\t ]*([^\t :]+)/gc;
			$onit = 1;
			next unless @list;

			if ($type eq 'HAVE') {
				# HEY!  Keep the second-person pronoun.
				# It's mildly sarcastic (with that period
				# at the end) -- imagine a "wtf" stare as
				# in... "you HAVE too many.  The hell are
				# you tryin' to be, the whole universe?"
				# Like that.
				die _diag(__("read_deps: %q line %s: You HAVE too many."), $file, $.) . "\n"
					if @list > 1 or exists $I{$type};
				$I{HAVE} = $list[0];
			} else {
				push @{$I{$type}}, @list;
			}
			next;
		}
		# Not a header line: that is the end of it,
		# or we never found one, and it is a long
		# way down to look for one.
		last if $onit or $. >= 32;
	}

	if ($fh->error()) {
		die _diag(__("read_deps: cannot read file %q: %s"), $file, "$!") . "\n";
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
as read by B<read_deps>.  Variables are demarcated
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
case (and so is the C<U>), up to C<10FFFF>; it is normalized to
C<${U+>I<HEX>C<}>, in capitals and of at least 4 digits, and the
character is what B<subs_deps> gives (see B<escape_deps>).  Any
other C<$> is malformed: a trailing one, an unterminated C<${>,
an empty C<${}>, a C<${U+...}> that is no code point, a C<$>
before a C<}> or a C<.>, and so on.  The optional C<strict>
option decides whether to die on malformed input, or to
replace unpaired dollar signs
with literal dollar signs.  Defaults to C<< strict => 0 >>.

With C<< pass_thru => 1 >>, unrecognized dollar signs are
left unchanged, for example C<$@>, rather than escaped.
Recognized variables and the project root are still normalized.
C<strict> takes precedence: malformed input still dies even
with C<pass_thru> enabled.  Defaults to C<< pass_thru => 0 >>.

Added in 0.0002.  C<pass_thru> added in 0.0003.  C<${U+...}>
added in 0.0100 (before, it was a variable of that name).

=cut

# The code point that `U+hex' is, if it is one
sub _code_point
{
	my ($name) = @_;
	$name =~ /\A[Uu]\+([0-9A-Fa-f]{1,8})\z/ or return;
	my $n = hex $1;
	$n <= 0x10FFFF ? $n : undef;
}

sub norm_deps
{
	my $opt = ref($_[-1]) eq 'HASH' ? pop : {};
	my (@ret);
	foreach (@_) {
		my $spec = $_;
		my $out = '';
		for (;;) {
			if ($spec =~ /\G([^\$]+)/gc) {
				$out .= $1;
			} elsif ($spec =~ /\G\$\{([Uu]\+[^}]*)\}/gc) {
				# A character, not a variable
				my $name = $1;
				my $n = _code_point($name);
				if (defined $n) {
					$out .= sprintf '${U+%04X}', $n;
				} else {
					$opt->{strict}
						and die _diag(__("norm_deps: %s is no code point in %q"),
							"\${$name}", $_) . "\n";
					$out .= ($opt->{pass_thru} ? '$' : '${$}') . "{$name}";
				}
			} elsif ($spec =~ /\G\$\{([^}]+)\}/gc) {
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$([\w\$])/gc) {
				# includes "$$"
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$/gc) {
				# Anything else is not a variable we recognize
				if ($opt->{strict}) {
					die _diag(__("norm_deps: trailing \$ in %q"), $_) . "\n"
						if $spec =~ /\G\z/gc;
					die _diag(__("norm_deps: unterminated or empty \${ in %q"), $_) . "\n"
						if $spec =~ /\G\{/gc;
					die _diag(__("norm_deps: stray \$ in %q"), $_) . "\n";
				}
				$out .= $opt->{pass_thru} ? '$' : '${$}';
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
	my ($spec, %opt) = @_;
	scalar norm_deps($spec, \%opt);
}

=item B<subs_dep> \%D, I<spec>, [ strict => 0, on_missing => 'vanish' ]

=item B<subs_deps> \%D, I<spec>... { strict => 0, on_missing => 'vanish' }

Substitute dependency specifications with
the given definitions.  C<norm_deps> is
called to normalize the specification (and
is given the options, if any).  The map is
optional since 0.0100, so this could be an
inverse operation of C<escape_deps>.
C<strict> is passed to B<norm_deps>.
The C<on_missing> option may be one of:

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
is planted like B<enroot> does: it keeps one
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

Added in 0.0002.

=cut

sub _bad_subs
{
	# HEY!  "bad" means undefined in the substitution
	# map here -- think `set -u' in your Bourne shell.
	# It is technically also double entendre, since
	# the map-less version of subs_deps is used as a
	# pure decode operation... in which case a named
	# substitution that is not an escape at all as "bad"
	# as in, "wait.... that's illegal."
	die _diag(__("subs_deps: bad substitution: %s"), "\${$_[0]}") . "\n";
}

sub subs_deps
{
	my $D = shift;
	my $opt = ref($_[-1]) eq 'HASH' ? pop : {};
	# pass_thru is not for us :)  Unpaired $s
	# will round-trip when we substitute them.
	if ($opt->{pass_thru}) {
		$opt = {%$opt};
		delete $opt->{pass_thru};
	}
	my $fb;
	if (defined $opt->{on_missing}) {
		my $missing = delete $opt->{on_missing};
		if (ref($missing) eq 'CODE') {
			$fb = $missing;
		} elsif ($missing eq 'croak') {
			$fb = \&_bad_subs;
		} else {
			# $missing could be "vanish"
			# but i don't really care.
		}
	}
	my @ret;
	foreach my $spec (norm_deps(@_, $opt)) {
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
nothing else: C<subs_deps> (without definitions, or with any)
gives it back, C<split_dep> finds no root in it, and
B<read_deps> reads it as one name, whatever is in it.  The
escaped dependency specifications are returned as a copy (in
scalar context, the first).

What is safe is left as it is: letters and digits (in ASCII), and
C</ . _ - + @>.  A C<$> is C<${$}>, and anything else is
C<${U+>I<HEX>C<}>, its code point (as in C<${U+0020}> for a space,
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
	my $spec = norm_deps(@_);
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

=item B<walk_deps> \%D, I<spec>... { graph => \%G, follow => \&ok }

Enumerate all dependencies of a path specification.
C<\%D> is a required map of variable definitions.
C<\%G> is an optional map for normalized path
specifications associated with their header values.
Every specification is normalized (see B<norm_deps>)
on its way in, so the list returned and the keys of
C<\%G> are normalized too, and C<$a/x> and C<${a}/x>
are the same entry.

Return the dependencies of NEEDs and WANTs of the
given path specifications pooled, recursively with
the dependents of all relative non-build dependents,
and update C<\%G> as a side-effect.  This list is
deduplicated symbolically, and files that are either
not regular files, are build dependents, or lack
headers are returned without their dependents.

Note that build dependents are solely identified
symbolically by the C<${B}> prefix.

Every specification the walk comes to is a key of C<\%G>,
so the graph is a negative cache too.  Its value is:

=over

=item *

the header (what B<read_deps> returns, as a hash
reference), for a regular file that was read;

=item *

an empty hash, for what has no header to read: a file
without one, or one that is not a regular file, or is
not there at all (so a WANT that is missing is still in
the list, and is not looked for again);

=item *

C<undef>, for what C<follow> denied: it is listed, but
was never read (see B<follow_ok>).

=back

So C<exists> says only that the walk came to it; whether
it was read is whether the value is defined.  A graph
passed to another walk is taken as it is, and what it
holds is not read or followed again.

Added in 0.0002.

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
	my $D = shift;
	my %opt = ref($_[-1]) eq 'HASH' ? %{ pop() } : ();
	my $G = $opt{graph} || +{};
	my $ok = $opt{follow} || \&follow_ok;

	# Everything is kept in normalized form, so that $a/x and ${a}/x
	# are one and the same node, whichever way a header spells it
	my (@pool, %pool);
	my @todo = reverse norm_deps(@_);

	while (@todo) {
		my $spec = pop @todo;
		next if $pool{$spec}++;
		push @pool, $spec;
		my $Imap = do {
			if (exists $G->{$spec}) {
				$G->{$spec};
			} elsif ($ok->($D, $spec)) {
				# Only a regular file has a header to read: a directory
				# opens fine but cannot be read, and a FIFO would hang
				my $file = subs_deps($D, $spec);
				$G->{$spec} = -f to_fs($file, 'walk_deps')
					? { read_deps($file, { forgive_missing => 1 }) }
					: {};
			} else {
				$G->{$spec} = undef;
			}
		};
		if (defined $Imap) {
			push @todo, reverse norm_deps(@{ $Imap->{WANT} || [] });
			push @todo, reverse norm_deps(@{ $Imap->{NEED} || [] });
		}
	}

	@pool;
}

=item B<read_manifest> I<file>

The goals in I<file> (a name, or a reference to the text), as an
L<RdKw::WwW::GenGenLib::Manifest>, which says what that looks like.
The names in it are unescaped, as B<subs_dep> does without definitions:
C<${U+0020}> is a space, and C<${$}> a C<$>.

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
