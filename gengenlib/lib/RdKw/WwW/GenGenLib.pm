package RdKw::WwW::GenGenLib;

use 5.006;
use strict;
use warnings;
use Exporter ();

our $VERSION = '0.00_02';
$VERSION = eval $VERSION;

=head1 NAME

RdKw::WwW::GenGenLib - general-purpose generation utilities

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

=cut

use Encode ();
use File::Basename qw( basename dirname );
use File::Compare ();
use File::Spec;

our @ISA = qw( Exporter );
our @EXPORT_OK = qw(
	read_make write_make
	update_file load_state
	read_deps norm_deps
	subs_deps split_dep
	walk_deps follow_ok
);

=head1 ROUTINES

=over

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
in genlib 0.00_00; use
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

	open my $fh, '>:encoding(UTF-8)', $tmp
		or die "update_file: open >$tmp: $!\n";
	print $fh $text or die "update_file: write >$tmp: $!\n";
	close $fh or die "update_file: write >$tmp: $!\n";

	my $exists = -e $file;
	if ($exists && File::Compare::compare($tmp, $file) == 0) {
		unlink $tmp;
		return 0;  # make it numeric so `>' isn't upset
	}
	rename $tmp, $file or die "update_file: mv $tmp $file: $!\n";
	$exists ? 1 : 2;
}

=item B<load_state> I<B>

Read C<${B}/MY/config.mk> and C<${B}/MY/option.mk> and return
an associative map of hashes, keyed by I<config> and I<option>.
Dies kindly if you have not configured.

This function not compatible with the original B<load_state>
in genlib 0.00_00.  Namely, you must obtain C<\%D> and C<\%O>
by name.

=cut

sub load_state
{
	my ($Bdir) = @_;
	$Bdir = '.' unless defined $Bdir and length $Bdir;
	my %S;
	for my $f (qw( config option )) {
		my $file = "$Bdir/MY/$f.mk";
		-f $file or die <<RUSH;
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

A file that is not UTF-8 (an image, say) has no header;
reading stops at the first line that is malformed, without
a word.

C<forgive_missing> is an optional boolean that decides whether
a file that cannot be opened to begin with can be forgiven.
Defaults to 0 (false; do not forgive).

=cut

sub read_deps
{
	local ($_, $.);
	my ($file, $opt) = @_;
	my $missing_ok = $opt && $opt->{forgive_missing};
	my $onit = 0;
	my %I = ();

	open (my $fh, '<', $file) or ($missing_ok
		? return ()
		: die "read_deps: open $file: $!\n");

	while (<$fh>) {
		# Not UTF-8 is not text, and so has no header: give up on the
		# spot, and quietly (the :encoding layer would warn per line).
		# A line break is never inside a character, so this is safe.
		eval { $_ = Encode::decode('UTF-8', $_, Encode::FB_CROAK()); 1 }
			or last;
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

=item B<norm_deps> I<spec>, ... { errors => "croak" }

Symbolically normalize dependency specification,
as read by B<read_deps>.  Variables are demarcated
with braces, and the C<'${A}/'> prefix is stripped.

In the case that I<spec> is literally C<'${A}'>,
return the empty string.

In list context; in scalar context, normalize just
the first argument.

A trailing C<$> and an unterminated C<${> are malformed.
The optional C<errors> option decides what to do about
them: C<"croak"> (the default) dies, and C<"replace">
treats the offending C<$> as a literal one (C<$$>).

=cut

sub norm_deps
{
	my $opt = ref($_[-1]) eq 'HASH' ? pop : {};
	my $errors = defined $opt->{errors} ? $opt->{errors} : 'croak';
	$errors eq 'croak' || $errors eq 'replace'
		or die "norm_deps: errors must be `croak' or `replace'\n";

	my (@ret);
	foreach (@_) {
		my $spec = $_;
		my $out = '';
		for (;;) {
			if ($spec =~ /\G([^\$]+)/gc) {
				$out .= $1;
			} elsif ($spec =~ /\G\$\{([^}]*)\}/gc) {
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$([^{])/gcs) {
				# includes "$$"
				$out .= "\${$1}";
			} elsif ($spec =~ /\G\$\z/gc) {
				die "norm_deps: trailing \$ in `$_'\n"
					if $errors eq 'croak';
				$out .= '${$}';
			} elsif ($spec =~ /\G\$\{/gc) {
				die "norm_deps: unterminated \${ in `$_'\n"
					if $errors eq 'croak';
				$out .= '${$}{';
			} else {
				last;
			}
		}
		$out =~ s{\A\$\{A\}(?:/|\z)}{};
		return $out unless wantarray;
		push @ret, $out;
	}
	@ret;
}

=item B<subs_deps> \%D, I<spec>, ... { errors => "croak" }

Substitute dependency specifications with
the given definitions.  C<norm_deps> is
called to normalize the specification (and
is given the options, if any), and path
segments that consist solely of a variable
expanding to C<"."> or nothing are collapsed
(so C<${a}/x> may become C<x>, but C<x-${a}/y>
is left alone).

=cut

sub subs_deps
{
	my $D = shift;
	my $opt = ref($_[-1]) eq 'HASH' ? pop : {};
	my @ret;
	foreach my $spec (norm_deps(@_, $opt)) {
		my $out = '';
	#	pos($spec) = 0;
SSS:		while ($spec =~ /\G([^\$]*)\$/gc) {
			$out .= $1;
			my ($name, $curly, $value);
			if ($curly = ($spec =~ /\G\{([^\}]+)\}/gc)) {
				$name = $1;
			} elsif (/\G(.)/gc) {
				$name = $1;
			}
			unless (defined $name) {
				# "$" at EOF
				$out = '$';
				next SSS;
			}
			if ($name eq '$') {
				# "$$" escapes "$"
				$out .= $name;
				next SSS;
			}
			unless (defined ($value = $D->{$name})) {
				# Undefined = empty to us.
				$value = '';
			}
			if (($out eq '' || $out =~ m{/\z})
				&& ($value eq '' || $value eq '.')
				&& $spec =~ m{\G(?:/|\z)}gc) {
				# Skip useless "./" segment (only if the variable
				# makes up the whole segment: good-${a}/x is not x)
				next SSS;
			}
			$out .= $value;
		}
		$out .= substr($spec, pos($spec) || 0);
		return $out unless wantarray;
		push @ret, $out;
	}
	@ret;
}

=item B<split_dep> I<spec>

Split a dependency specification into its symbolic
root and the remainder of the path.  The symbolic
root consists of C</>-separated segments entirely
derived from a variable.

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

=item B<walk_deps> \%D, I<spec>, ... { graph => \%G, follow => \&ok }

Enumerate all dependencies of a path specification.
C<\%D> is a required map of for variable definitions.
C<\%G> is an optional map for normalized path
specifications associated with their header values.

Return the dependencies of NEEDs and WANTs of the
given path specifications pooled, recursively with
the dependents of all relative non-build dependents,
and update C<\%G> as a side-effect.  This list is
deduplicated symbolically, and files that are either
not readable, are build dependents, or lack headers
are returned without their dependents.

Note that build dependents are solely identified
symbolically by the C<${B}> prefix.

=item B<follow_ok> \%D, I<spec>

Default implementation of the C<follow> option.
Entries denied this way are permanently cached
as C<undef> in the graph.

=cut

sub follow_ok
{
	my ($D, $spec) = @_;
	my ($root, $path) = split_dep($spec);
	# Build dependents are terminal
	return if $root =~ /\A\$\{B\}(?:\/|\z)/;
	# Nor does an absolute path outside any variable lead anywhere safe
	return if $root eq '' && $path =~ m{\A/};
	# Directory traversal is bad: this part we must
	# expand fully ahead of time, since it may be
	# concatenated from seemingly innocent components
	# (e.g. ${A}${A} when ${A} is (almost) always ".")
	my $name = subs_deps($D, $path);
	return if $name =~ /(?:\A|\/)\.\.(?:\/|\z)/;
	1;
}

sub walk_deps
{
	my $D = shift;
	my %opt = ref($_[-1]) eq 'HASH' ? %{ pop() } : ();
	my $G = $opt{graph} || +{};
	my $ok = $opt{follow} || \&follow_ok;

	my (@pool, %pool);
	my @todo = reverse @_;

	while (@todo) {
		my $spec = pop @todo;
		next if $pool{$spec}++;
		push @pool, $spec;
		my $Imap = do {
			if (exists $G->{$spec}) {
				$G->{$spec};
			} elsif ($ok->($D, $spec)) {
				$G->{$spec} = +{ read_deps(
					subs_deps($D, $spec),
					{ forgive_missing => 1 }) };
			} else {
				$G->{$spec} = undef;
			}
		};
		if (defined $Imap) {
			push @todo, reverse @{ $Imap->{WANT} || [] };
			push @todo, reverse @{ $Imap->{NEED} || [] };
		}
	}

	@pool;
}

=back

=cut

1;
