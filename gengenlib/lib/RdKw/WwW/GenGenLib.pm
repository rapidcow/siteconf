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

=cut

use Encode ();
use Encode::Locale ();
use IO::Handle ();
use File::Basename qw( basename dirname );
use File::Compare ();
use File::Spec;

our @ISA = qw( Exporter );
our @EXPORT_OK = qw(
	read_make write_make
	update_file load_state
	read_deps
	norm_deps norm_dep
	subs_deps subs_dep
	split_dep walk_deps follow_ok
	enroot uproot
	to_fs un_fs
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
		. "cannot name `$name' in this locale"
		. " ($Encode::Locale::ENCODING_LOCALE_FS)\n";
	$fs;
}

sub un_fs
{
	my ($fs, $who) = @_;
	my $name = eval { Encode::decode(locale_fs => $fs,
		Encode::FB_CROAK() | Encode::LEAVE_SRC()) };
	defined $name or die +(defined $who ? "$who: " : "")
		. "cannot read a file name in this locale"
		. " ($Encode::Locale::ENCODING_LOCALE_FS)\n";
	$name;
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
		or die "read_make: open <$file: $!\n";
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
		or die "update_file: open >$tmp: $!\n";
	print $fh $text or die "update_file: write >$tmp: $!\n";
	close $fh or die "update_file: write >$tmp: $!\n";

	my $exists = -e $file_fs;
	if ($exists && File::Compare::compare($tmp_fs, $file_fs) == 0) {
		unlink $tmp_fs;
		return 0;  # make it numeric so `>' isn't upset
	}
	rename $tmp_fs, $file_fs or die "update_file: mv $tmp $file: $!\n";
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
		-f to_fs($file, 'load_state') or die <<RUSH;
error: You have not configured! (no $file)
error: You should ./configure first. ;)
RUSH
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
(Since 0.0100; before, only C<HAVE>, C<NEED> and C<WANT> after
exactly one space were header lines, and names were split at any
white space.)

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
	\A .*?			# anything at all before the comment, as in
				# `x = 1  # NEED: ...' -- but the first
				# comment that works is the one
	(?:
		\#		# UNIX sh, scripting languages
	|	;		# BIND zone, DOS-INI, Lisp, ledger
	|	\*		# C89/ANSI/K&R /* ... */
	|	//		# C++, Java, C99 line-comment
	|	"		# vimscript
	|	'		# VBScript (aughhhhhh!!! >n<!)
	|	--		# lua, SQL
	|	%		# TeX, lilypond
	|	(?<![A-Za-z0-9_])
		\@?(?i:rem)	# BASIC, DOS batch; any case (but a word
				# of its own, unlike theorem)
	|	::		# DOS batch, the label that is not
	)
	[\t ]+			# Blanks are necessary both due to my
				# subjective aesthetics and preventing
				# false positives (e.g. a quoted string)
	([A-Za-z._-]+)		# The field: any name, in any case (ours
				# are HAVE, NEED, WANT, and only so)
	[\t ]* : [\t ]*		# and then what it says
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
		: die "read_deps: open $file: $!\n");

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
			# at blanks: anything else is part of a name.
			my @list = /\G[\t ]*([^\t ]+)/gc;
			$onit = 1;
			next unless @list;

			if ($type eq 'HAVE') {
				die "read_deps: $file line $.: You HAVE too many.\n"
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
		die "read_deps: read $file: $!\n";
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
C<$$> is a literal C<$>.  Any other C<$> is malformed: a
trailing one, an unterminated C<${>, an empty C<${}>, a C<$>
before a C<}> or a C<.>, and so on.  The optional C<strict>
option decides whether to die on malformed input, or to
replace unpaired dollar signs
with literal dollar signs.  Defaults to C<< strict => 0 >>.

With C<< pass_thru => 1 >>, unrecognized dollar signs are
left unchanged, for example C<$@>, rather than escaped.
Recognized variables and the project root are still normalized.
C<strict> takes precedence: malformed input still dies even
with C<pass_thru> enabled.  Defaults to C<< pass_thru => 0 >>.

Added in 0.0002.  C<pass_thru> added in 0.0003.

=cut

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
			} elsif ($spec =~ /\G\$\{([^}]+)\}/gc) {
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$([\w\$])/gc) {
				# includes "$$"
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$/gc) {
				# Anything else is not a variable we recognize
				if ($opt->{strict}) {
					die "norm_deps: trailing \$ in `$_'\n"
						if $spec =~ /\G\z/gc;
					die "norm_deps: unterminated or empty \${ in `$_'\n"
						if $spec =~ /\G\{/gc;
					die "norm_deps: stray \$ in `$_'\n";
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

=item B<subs_dep> \%D, I<spec>, [ strict => 0 ]

=item B<subs_deps> \%D, I<spec>... { strict => 0 }

Substitute dependency specifications with
the given definitions.  C<norm_deps> is
called to normalize the specification (and
is given the options, if any).

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

Added in 0.0002.

=cut

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
			my $value = $D->{$name};
			# Undefined = empty to us.
			defined $value or $value = '';
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
	while ($spec =~ /\G(\$\{[^}]+\})(\/|\z)/gc) {
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

=back

=cut

1;
