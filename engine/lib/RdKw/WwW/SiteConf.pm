package RdKw::WwW::SiteConf;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.03_00';
$VERSION = eval $VERSION;

=head1 NAME

RdKw::WwW::SiteConf - read the build graph of a configured source tree

=head1 SYNOPSIS

    use RdKw::WwW::SiteConf;

    my $sc = RdKw::WwW::SiteConf->new(B => 'build');   # reads MY/config.mk
    my $plan = $sc->plan;       # resolves MANIFEST against Makefile.in

    for my $goal (@{ $plan->{goals} }) {
        print "$goal->{name}:\n";
        for my $file (@{ $goal->{files} }) {
            my $node = $plan->{node}{$file};
            print "  $node->{bpath} <- @{ $node->{deps} }\n";
        }
    }

    $sc->generate('make');      # MY/MANIFEST.* and the Makefile

=head1 DESCRIPTION

For the generated configure script, see L<RdKw::WwW::SiteConf::Configure>.

Three inputs make up a project, all found from F<MY/config.mk>:

=over

=item F<Makefile.in> (C<R>)

(Found from the current directory, as is F<MANIFEST>.)

Transformation rules from C<${a}/FILE> to C<${b}/FILE>.  Rules look
like those of L<make(1)>, with C<${A}>, C<${B}>, C<${a}>, C<${b}>
(and whatever else is in F<config.mk>) substituted, plus C<${@}> or
C<${.TARGET}> for the file being made (in prerequisites too, each
target of a rule having its own), C<${^X}> for our perl, C<${U+>I<hex>C<}>
for the character of that code point (as in a header), and the
modifiers C<:Q> to shell-quote (C<${A:Q}>; in a recipe, a C<$> in what
it makes is for the shell, and is written C<$$>, while one from C<$$>
or a variable is make's), C<:E>, C<:H>, C<:R>, C<:T>
and C<:S/old/new/> to take names apart (C<${@:R}>); see
L<RdKw::WwW::SiteConf::Modifiers>.  Targets are named
relative to C<${b}>, or to C<${c}> if they say so (below).  A prerequisite of a rule (a tool, such as the
renderer) may have a header too: if it does, its C<NEED>s and C<WANT>s
are the rule's as well, and its C<HAVE>, if any, must be its name as the
rule spells it.  It needs no header, though.  (This is how the renderer
of C<-P web> comes to depend on F<MY/option.mk>.)

Unless it says otherwise, a rule makes C<${B}/${b}/FILE> from
C<${A}/${a}/FILE>: that source is implied.  A rule may say otherwise
by naming the source first.  If the first prerequisite is in C<${a}>
(it starts with C<${A}/${a}/> or C<${a}/>, which is read as it is
written, before anything is expanded) it is the source, and the implied
one is not there:

    blog/a.md.html blog/b.md.html: ${a}/${@:R}
            cd ${A:Q} && pandoc -o ${B:Q}/${b:Q}/${@:Q} ${a:Q}/${<:Q}

    styles.css: ${a}/styles.scss

needs no F<html/a.md.html>.  Spelled out, C<${a}/${@}> brings the
implied source back.  In a recipe, C<${<}> (or C<${.IMPSRC}>) is the
source, relative to C<${a}> as C<${@}> is to the target tree.

A prerequisite may say how firmly it is needed: C<NEED:x> is the same
as plain C<x>, and C<WANT:x> is kept if it can be had (it exists, or it
can be made), and is dropped with a warning if not -- as a C<WANT> in a
header is.  What a C<WANT:> tool's header C<NEED>s is only wanted, too.
The prefix is read as it is written, before anything is expanded, and
is for each word the rest expands to.  It is in capitals and has
nothing between it and the name (C<NEED: x> is an error), and nothing
else may come before a colon in a prerequisite: C<need:x> and C<USE:x>
are errors, so a file named F<NEED:> is C<NEED:NEED:>.  A first
prerequisite with a prefix is never the source.

    a.html: NEED:${A}/render NEED:${B}/MY/option.mk WANT:${A}/extra.css
            cd -- ${A:Q} && ${^X} render -B ${B:Q} -- ${a}/${<} ${B:Q}/${b}/${@}

A C<;> ends the prerequisites, as it does to make, and what follows it
is the first line of the recipe; a tab line after it is the next.  (A
C<;> in a C<${...}>, as in C<${@:S/;/,/}>, is part of that.)

    robots.txt: ; printf 'User-agent: *\n' > ${B:Q}/${b:Q}/${@:Q}

A first prerequisite that is C<${a}> and nothing more (or C<${a}/>,
C<${A}/${a}//>, any number of slashes) says there is no source: the
target is made from the other prerequisites alone, and C<${<}> is an
error in its recipe.

    stamp: ${a}/ ${A}/tool
            ${A:Q}/tool > ${B:Q}/${b:Q}/${@:Q}

What is made but does not go into the site -- the intermediate files
-- may be put in the cache, C<${c}>, which is relative to C<${B}> like
C<${b}> is and is C<${b}> unless configured otherwise (C<-Dc>).  A
target is named after C<${c}/> then (or C<${b}/>, which is what none
says); C<${@}> is still the name after it, and nothing else under
C<${B}> may be a target:

    ${c}/blog/a.md.html: ${a}/${@:R}
            cd ${A:Q} && pandoc -o ${B:Q}/${c:Q}/${@:Q} ${a:Q}/${<:Q}

    blog/a.html: ${B}/${c}/blog/a.md.html

Directories are made as for C<${b}>.  We do not check that C<${a}>,
C<${b}> and C<${c}> are different directories (C<${c}> is C<${b}>
unless configured, and C<${a}> may be C<${b}> with explicit prefixes):
whoever cares about that should check, using the names in
F<MY/config.mk>.  The file must have a C<c>, as configure writes it.
Only files made in C<${b}> can
be goals of the manifest; those in the cache are made because
something needs them.

Words (targets, prerequisites, and what F<MANIFEST> says) are separated
by white space as L<make(1)> knows it -- space, tab, newline, vertical
tab, form feed and carriage return -- and by nothing else: a no-break
space is part of a name.

Target and dependency lists may span multiple lines: end each
continued line with a backslash.  The backslash and newline, along
with indentation on the next line, are replaced by a space.  Lines
that are only a comment (a C<#> after any indentation, then whitespace
or the end of the line: C<#foo> is a word) in between are skipped, and do not end the list -- unlike in L<make(1)>, where one
would take the rest of the list with it:

    ${b}/index.html \
    ${b}/about.html \
        : \
    # why this is spelled out
        ${a}/site/${.TARGET}

=item F<MANIFEST> (C<F>)

The goals of the build, each a L<make(1)> target:

    MAKE all
        NEED index.html           # hard: no rule or source, no build
        WANT extra/index.html     # soft: dropped, with a warning

    MAKE small
        NEED index.html

Indentation is only for the eyes.  A C<#> preceded by whitespace
(or at the start of the line) begins a comment.  File names are
relative to C<${a}> (and made in C<${b}>).

A file name is unescaped as a header's is (see
L<RdKw::WwW::GenGenLib::Manifest>): C<${$}> is a C<$> and
C<${U+>I<hex>C<}> a character, as in C<r${U+00E9}sum${U+00E9}.html>; and
there are no variables.  A goal name is not.  What it comes to must
still be a name that we would put into a Makefile, as it must in a
target: no blanks, C<$>, C<#>, C<:> and the like, nothing absolute,
and no C<..> (so far, the escape is good for C<siteconf -l>, and what
is not ASCII).

=item the files themselves

A source file declares its place in the graph in a header (see
L<RdKw::WwW::GenLib/read_deps>, which also says what comments they
may hide in):

    # HAVE: ${A}/${a}/index.html
    # NEED: skel/HTML
    # NEED: ${B}/${b}/style.css
    # WANT: ${A}/data/extra.scm

Every path here is from the project root, spelled in full, and
nothing is relative to anything else.  These are expanded first:

=over

=item C<${A}>

The root itself, which is always C<.>  (This is not C<A> of
F<config.mk>, which is the way from the build directory back.)

=item C<${a}>, C<${B}>

The source tree, and the build directory, as configured.

=item C<${b}>

The target tree, as configured -- which is relative to C<${B}>, so
it is only good after it: C<${B}/${b}/style.css>.  A bare C<${b}/...>
is an error.

=item whatever else is in F<config.mk>

For example, a custom-defined variable via C<-Dtem=template>
makes C<${tem}/head.html> expand to F<template/head.html>.

If the variable is still not found here then it is an error.

=back

A single letter may drop its braces (C<$a>), C<$$> or C<${$}> is a
C<$>, and C<${U+>I<hex>C<}> is the character of that code point, as in
C<${U+0020}> for a space (see L<RdKw::WwW::GenGenLib/escape_dep>).  A
name with none of these is relative to the root, so C<skel/HTML> and
C<${A}/skel/HTML> are the same.  Build state is under C<${B}/MY/>.

C<HAVE> is the source's own path, C<${A}/${a}/FILE>.  A dependency on
something in C<${B}/${b}> is an edge to that file in the graph, which
needs a rule and a source of its own, and is made first, whether or
not any goal asks for it.  (Cycles are an error.)  Other
dependencies must exist.

The dependencies in F<Makefile.in> are those of L<make(1)>, as
seen from the build directory, after the substitutions above.

=back

A C<WANT>ed file is resolved at configuration time: it is kept if
there is a rule for it, its source exists, and everything it
C<NEED>s exists.  The resolved goals are written to
F<MY/MANIFEST.I<goal>> in the very same format (all C<NEED>, with
what was dropped left as comments).

File names, here and in what we are given, are character strings:
they are spelled as L<RdKw::I18N::CodeSets> says (B<filesys> of
C<< RdKw::I18N::CodeSets->locale >>) on their way out to the system,
and a name it cannot spell is an error.  What is in the files is
UTF-8, the build file we write included; so a name that is not ASCII
is found by L<make(1)> or L<ninja(1)> only where the file system
spells it in UTF-8 too.

=head1 METHODS

=over

=cut

use File::Basename qw( dirname basename );
use Cwd qw( abs_path );
use File::Spec ();

use RdKw::I18N::CodeSets ();
use RdKw::WwW::GenGenLib 0.0100 qw(
	read_make read_deps update_file
	norm_dep uproot );

# What we say is said in the language of the locale, if
# RdKw::WwW::SiteConf::L10N says where the catalogs are (and
# Locale::Messages is there to read them); else, and for what no
# catalog has, as it is written (see RdKw::L10N::TextDomain).
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

use RdKw::WwW::SiteConf::Modifiers;

# A name as the file system spells it, and back (see RdKw::I18N::CodeSets)
sub _to_fs { RdKw::I18N::CodeSets->locale->to_fs($_[0], { prog => 'E' }) }
sub _un_fs { RdKw::I18N::CodeSets->locale->un_fs($_[0], { prog => 'E' }) }

# A message: %q is a name, %s as it is, %m is $! (see RdKw::I18N::CodeSets)
sub _diag
{
	RdKw::I18N::CodeSets->locale->diag(@_);
}

# An error or a warning: each line of the message after `prefix'
# (E: or W:), and a newline at the end
sub _say
{
	my ($prefix, $msg) = @_;
	$msg =~ s/^/$prefix: /mg;
	"$msg\n";
}

# Where in a file: `file' line 3
sub _line
{
	my ($file, $line) = @_;
	_diag(__("%q line %s"), $file, $line);
}

# Goals of the manifest cannot take these names; `Makefile' because
# we write it, and `MY' is a directory.  (`clean', or whatever -Dclean
# makes of it, is reserved too: see _clean_pattern.)
my %reserved_goal = map { $_ => 1 } qw( Makefile MY );

# White space, as make and the shell (and POSIX) know it: these six, and
# nothing else.  A no-break space, say, is part of a name.
my $SP = '\t\n\cK\f\r ';

# A word of Makefile.in as it is written: a ${...} may hold spaces
# (in :S/ /_/), and it is all one word.
my $WORD = qr/(?:[^$SP\$]|\$(?!\{)|\$\{(?:[^{}\\]|\\.|\{[^{}]*\})*\})+/;

# The prerequisites of a rule: up to a `;', which begins its recipe,
# as in `a: b ; cp b a' -- but not one in a ${...} (:S/;/,/), nor $;
my $PREREQ = qr/(?:[^;\$]|\$\{(?:[^{}\\]|\\.|\{[^{}]*\})*\}|\$[^{]|\$\z)*/;

# The words of `s' as written (see $WORD).  Whatever is not one (an
# unfinished ${, say) is the last, for _subst to say what is wrong.
sub _raw_words
{
	my ($s) = @_;
	my @word;
	push @word, $1 while $s =~ /\G[$SP]*($WORD)/gco;
	$s =~ /\G[$SP]*/gco;
	my $rest = substr($s, pos($s) || 0);
	push @word, $rest if length $rest;
	@word;
}

# The words of `s', split as split ' ' would, at $SP alone.  (Matched,
# not split: split /[$SP]+/ splits an upgraded string at a Unicode
# space, in perl 5.34 and 5.44 at least, though the class alone never
# matches one -- as if it were /\s+/.)
sub _words
{
	my ($s) = @_;
	$s =~ /([^$SP]+)/go;
}

=item B<new> B =E<gt> I<dir>[, D =E<gt> { ... }, quiet =E<gt> 1 ]

I<dir> is the build directory, as seen from the current directory.
C<MY/config.mk> there must exist.  Warnings are not printed when
I<quiet> is true.  I<D> overrides C<MY/config.mk> parameters.
(C<F> and C<R>, whether from here or from there, are paths from the
current directory, not from the project root.)

=cut

sub new
{
	my ($class, %arg) = @_;
	my $self = bless {
		B => defined $arg{B} && length $arg{B} ? $arg{B} : '.',
		quiet => $arg{quiet},
		prog => defined $arg{prog} ? $arg{prog} : 'siteconf',
	}, $class;

	my $conf = "$self->{B}/MY/config.mk";
	# HEY!  Keep a winky face in the translation ;)
	# (as GenGenLib's load_state does: newbies see it)
	-f _to_fs($conf) or die _say(E => _diag(__("You have not configured!  (no %q)\n"
		. "You should ./configure first. ;)"), $conf));
	my %D = read_make($conf);
	# F and R (the manifest and the rules) are external to the project:
	# paths from where we are, not from the project root.  The overrides
	# are noted so that we can credit them in the header.
	my %fromhere;
	if ($arg{D}) {
		my $Doverrides = $arg{D};
		foreach (keys %$Doverrides) {
			$D{$_} = $Doverrides->{$_};
			$fromhere{$_} = $Doverrides->{$_} if $_ eq 'F' or $_ eq 'R';
		}
	}
	for my $k (qw( A B a b c R F e )) {
		defined $D{$k} && length $D{$k}
			or die _say(E => _diag(__("%q: %q is missing.  Try reconfiguring."), $conf, $k));
	}
	File::Spec->file_name_is_absolute($D{b})
		# HEY!  %q is a variable of config.mk: `b' or `c', which are where
		# what we make goes (the target tree, and the cache)
		and die _say(E => _diag(__("%q prefix must be a relative path."), 'b'));
	# c, the cache (what we make but do not ship), is written by
	# configure even when it is b; we do not guess it.
	File::Spec->file_name_is_absolute($D{c})
		and die _say(E => _diag(__("%q prefix must be a relative path."), 'c'));
	grep { $_ eq '..' } split m!/!, $D{c}
		and die _say(E => _diag(__("%q prefix may not climb out of the build directory."), 'c'));
	$D{e} =~ m!/!
		and die _say(E => _diag(__("%q (directory marker) may not contain a slash."), 'e'));
	defined $D{clean} && length $D{clean} and $D{clean} !~ /\A[A-Za-z0-9&][-\w.+&]*\z/
		and die _say(E => _diag(__("%q may be made of letters, digits and -_.+& only: %q"),
			'clean', $D{clean}));
	$self->{D} = \%D;
	# The build directory and the project root, as they really are
	# (and as characters, like every other name).  Each is said as
	# soon as it is not found, while $! still says why.
	$self->{Babs} = abs_path(_to_fs($self->{B}));
	defined $self->{Babs}
		or die _say(E => _diag(__("cannot find the build directory %q: %m"), $self->{B}));
	$self->{Rabs} = abs_path(_to_fs($self->_fs($D{A})));
	defined $self->{Rabs}
		or die _say(E => _diag(__("cannot find the source tree %q: %m"), $D{A}));
	$_ = _un_fs($_) for @$self{qw( Babs Rabs )};
	$self->{fromhere} = \%fromhere;
	$self;
}

sub _warn
{
	my ($self, @mesg) = @_;
	$self->{quiet} or print STDERR @mesg;
}

# A path seen from the build directory, as a path we can open.
sub _fs
{
	my ($self, $path) = @_;
	File::Spec->file_name_is_absolute($path)
		? $path : File::Spec->catfile($self->{B}, $path);
}

# Paths come in two frames: the project root (what headers say, see
# _expand), and the build directory (what the Makefile says, and what
# we can open from here).  This is the way over.  Whatever is absolute
# stays that way, unless it is in the build directory (as ${B}/${b}/x
# is when B is absolute, whether spelled as configured or as it really
# is); then it is seen from there like the rest, or we would not know
# it for something we make.
sub _to_build
{
	my ($self, $path) = @_;
	if (File::Spec->file_name_is_absolute($path)) {
		$path = File::Spec->canonpath($path);
		my @root = ($self->{Babs});
		File::Spec->file_name_is_absolute($self->{D}{B})
			and unshift @root, File::Spec->canonpath($self->{D}{B});
		for my $root (@root) {
			$root eq File::Spec->rootdir and next;
			index($path, "$root/") == 0 and return substr($path, length($root) + 1);
		}
		return $path;
	}
	File::Spec->abs2rel(File::Spec->rel2abs($path, $self->{Rabs}), $self->{Babs});
}

# A path in a header, as one from the project root.  It is relative to
# the root unless it says otherwise, and may say so with these:
#
#   ${A}  the root itself, so `.' (not where A leads from the build dir)
#   ${a}  the source tree, relative to ${A}; so ${A}/${a}/x is html/x
#   ${B}  the build dir, relative to ${A}
#   ${b}  the target tree, but relative to ${B}!  It is only good after
#         one: ${B}/${b}/x.  On its own it names the wrong place.
#
# as well as anything else configured (${c}, ${inc}, ...),
# and a single letter spelled as $a is as good as ${a}.
sub _expand
{
	my ($self, $spec, $where) = @_;
	my $D = $self->{D};
	# anything configured (-Dinc=include, say), but A is not config.mk's
	my %var = ( %$D, A => '.' );
	$spec =~ /(?<!\$\{B\}\/)(?<!\$B\/)\$(?:\{([bc])\}|([bc]))/
		# HEY!  The first %s is where (a file, or `file' line 3), and
		# the second is b or c (a variable of config.mk, as in ${b}).
		# Leave the ${...}s alone: they are what is written in a header.
		and die _say(E => _diag(__('%1$s: %2$q: ${%3$s} is relative to ${B}; write ${B}/${%3$s}'),
			$where, $spec, defined $1 ? $1 : $2));
	# ${A} is `.', so ${A}/x is just x -- even when x is absolute
	# (as ${a} may be), which `./' in front of it would not be.
	$spec =~ s{\A\$(?:\{A\}|A)(?:/+|\z)}{} and !length $spec and $spec = '.';
	# $$ (or ${$}) is a $, and ${U+hex} the character of that code
	# point, as they are to GenGenLib (see escape_dep)
	my $out = '';
	for (;;) {
		if ($spec =~ /\G([^\$]+)/gc) {
			$out .= $1;
		} elsif ($spec =~ /\G\$(?:\{\$\}|\$)/gc) {
			$out .= '$';
		} elsif ($spec =~ /\G\$\{([Uu]\+[^}]*)\}/gc) {
			my $u = $1;
			$u =~ /\A[Uu]\+([0-9A-Fa-f]{1,8})\z/ and hex($1) <= 0x10FFFF
				# HEY!  the last %s is what is in a header, as ${U+...}
				or die _say(E => _diag(__("%s: %q: %s is no code point"),
					$where, $spec, "\${$u}"));
			$out .= chr hex $1;
		} elsif ($spec =~ /\G\$(?:\{(\w+)\}|(\w))/gc) {
			my $x = defined $1 ? $1 : $2;
			# HEY!  the last %s is the variable, as ${name}
			defined $var{$x} or die _say(E => _diag(__("%s: %q: no such variable %s"),
				$where, $spec, "\${$x}"));
			$out .= $var{$x};
		} elsif ($spec =~ /\G\$/gc) {
			die _say(E => _diag(__('%s: stray $ in %q'), $where, $spec));
		} else {
			last;
		}
	}
	length $out or die _say(E => _diag(__("%s: empty path"), $where));
	File::Spec->canonpath($out);
}

# `path' relative to `a', as seen from the build dir.
sub _apath
{
	my ($self, $path) = @_;
	$self->_to_build(File::Spec->canonpath("$self->{D}{a}/$path"));
}

# What a header calls a dependency, as seen from the build dir
sub _dep
{
	my ($self, $path, $where) = @_;
	$self->_to_build($self->_expand($path, $where));
}

# What a file we make is called in the graph (its key): its name, if
# it is made in `b', or `${c}/name' if in `c' (which is `b' unless
# said otherwise, and then it is all the same).  A `$' cannot be in a
# name, so the one is never mistaken for the other.
sub _key
{
	my ($self, $tree, $name) = @_;
	$tree eq 'c' && defined $self->{D}{c} && File::Spec->canonpath($self->{D}{c}) ne File::Spec->canonpath($self->{D}{b})
		? "\${c}/$name" : $name;
}

# A key as (tree, name)
sub _unkey
{
	my ($key) = @_;
	$key =~ m!\A\$\{c\}/(.*)\z!s ? ('c', $1) : ('b', $key);
}

# The key of what we make, if `path' (seen from the build dir) is
# something we make: that is, if a rule makes it.  (With b = `.' the
# build dir is also the source tree and where MY/ lives, so the place
# alone says nothing.)
sub _target
{
	my ($self, $path) = @_;
	for my $tree (qw( b c )) {
		defined $self->{D}{$tree} or next;
		my $dir = File::Spec->canonpath($self->{D}{$tree});
		my $name = $dir eq '.' ? $path
			: index($path, "$dir/") == 0 ? substr($path, length($dir) + 1) : next;
		my $key = $self->_key($tree, $name);
		return $key if $self->{rules} && $self->{rules}{$key};
	}
	undef;
}

# Where the file of this key is, seen from the build dir
sub _bpath
{
	my ($self, $key) = @_;
	my ($tree, $name) = _unkey($key);
	File::Spec->canonpath("$self->{D}{$tree}/$name");
}

=item B<shell_quote> I<string>

Not a method.  Quotes I<string> for the shell, unless that is
needless.

=cut

sub shell_quote
{
	my ($s) = @_;
	# Nothing in it for the shell to mangle?  Then leave it be.
	return $s if $s =~ m!\A[A-Za-z0-9_./:@%+=,-]+\z!;
	# otherwise: single quotes, and ' itself as '\''
	$s =~ s!'!'\\''!g;
	"'$s'";
}

# Names that we dare to put into a Makefile, and cannot escape from
# the source or the output tree.
sub _check_file
{
	my ($file, $where) = @_;
	$file =~ m!\A[^$SP:\$#%\\|;<>"'`*?\[\](){}&]+\z!o
		# HEY!  The first %s is always where (a file, or `file' line 3),
		# in this message and in those that follow it
		or die _say(E => _diag(__("%s: bad file name %q"), $where, $file));
	$file =~ m!\A/!
		and die _say(E => _diag(__("%s: file name %q must be relative"), $where, $file));
	grep { $_ eq '..' } split m!/!, $file
		and die _say(E => _diag(__("%s: file name %q climbs out of the tree"), $where, $file));
	1;
}

=item B<read_manifest> I<file>

Returns the goals in I<file>, a list of C<{ name, need, want }>
hash references, where the latter two are lists of C<{ file, line }>.
You can also give a scalar reference instead of a file name.  It is
read by L<RdKw::WwW::GenGenLib/read_manifest> (so names are unescaped),
and then what we cannot have is an error: a reserved goal name, and a
file name we would not put into a Makefile (one with blanks or what
make would make something of, an absolute one, one with C<..>).

=cut

# What -Dclean says the cleaning rules are called: a name, in which `&'
# is the name of a goal (and then there is a rule for each), and `clean'
# if it is not said.  A lone `&' (a rule that would be named like the
# goal itself) means there are none; then this is undef.
sub _clean_pattern
{
	my ($self) = @_;
	my $c = $self->{D} ? $self->{D}{clean} : undef;
	$c = 'clean' unless defined $c && length $c;
	$c eq '&' ? undef : $c;
}

# Whether `name' is the one cleaning rule that is not for a goal
sub _is_clean
{
	my ($self, $name) = @_;
	my $pat = $self->_clean_pattern;
	defined $pat && $pat !~ /&/ && $name eq $pat;
}

sub read_manifest
{
	my ($self, $file) = @_;
	my $mf = eval { RdKw::WwW::GenGenLib::read_manifest($file) } or do {
		(my $why = $@) =~ s/\Aread_manifest: //;
		die "E: $why";
	};
	$file = $mf->file;

	# (what it reads, it reads; what we cannot have, in the order it is said)
	my @goal = $mf->goals;
	for my $goal (@goal) {
		my $name = $goal->{name};
		$reserved_goal{$name} || $self->_is_clean($name)
			and die _say(E => _diag(__("%s: %q is a reserved goal name"),
				_line($file, $goal->{line}), $name));
		_check_file($_->{file}, _line($file, $_->{line}))
			for sort { $a->{line} <=> $b->{line} } @{ $goal->{need} }, @{ $goal->{want} };
	}
	@goal;
}

# Makefile.in with the `${...}'s (and `$x's) in `line' replaced.  The
# modifiers (see RdKw::WwW::SiteConf::Modifiers) come after the name.
# `node' is the name of the target (relative to its tree), and `src'
# that of its source (relative to `a'); the latter is only known
# once all prerequisites have been read, so those may not say it.
# What a :Q made is for the shell; if `quoted' is given, it is pushed
# where each one is in what we return, as [ offset, length ].
sub _subst
{
	my ($self, $line, $node, $where, $src, $quoted) = @_;
	my $D = $self->{D};
	my $out = '';
	my $pos = 0;
	while ((my $i = index($line, '$', $pos)) >= 0) {
		$out .= substr($line, $pos, $i - $pos);
		my $end = eval { RdKw::WwW::SiteConf::Modifiers::_expr_end($line, $i) };
		defined $end or do {
			# a `$' at the very end, or before a newline, is a `$'
			$@ and die "E: $where: $@";   # (as Modifiers says it)
			$out .= '$';
			$pos = $i + 1;
			next;
		};
		if (substr($line, $i + 1, 1) eq "\n") {
			$out .= '$';
			$pos = $i + 1;
			next;
		}
		my $body = substr($line, $i + 1, $end - $i - 1);
		my ($x, $mods) = ($body, undef);
		if ($body =~ s!\A\{(.*)\}\z!$1!s) {
			($x, $mods) = $body =~ /\A([^:]*)(?::(.*))?\z/s;
		}
		# `${A}/x' with an A of `.' would leave `./x' behind, so
		# it takes its slash with it.
		my $slash = substr($line, $end, 1) eq '/' ? '/' : '';
		$pos = $end + length $slash;
		my $val;
		if ($x eq '$') {
			$val = '$';
		} elsif ($x =~ /\A[Uu]\+/) {
			# a character, as in a header (see _expand)
			$x =~ /\A[Uu]\+([0-9A-Fa-f]{1,8})\z/ and hex($1) <= 0x10FFFF
				# HEY!  the second %s is what is in Makefile.in, as ${U+...}
				or die _say(E => _diag(__("%s: %s is no code point"), $where, "\${$x}"));
			$val = chr hex $1;
		} elsif ($x eq '@' or $x eq '.TARGET') {
			# HEY!  the second %s is a variable, as ${@} (or ${.TARGET}),
			# in this message and in those that follow it
			defined $node or die _say(E => _diag(__("%s: %s outside of a recipe"),
				$where, "\${$x}"));
			$val = $node;
		} elsif ($x eq '<' or $x eq '.IMPSRC') {
			defined $src or die _say(E => _diag(__("%s: %s is not known here"
				. " (the source is what the prerequisites say)"), $where, "\${$x}"));
			length $src or die _say(E => _diag(__("%s: %s: this rule has no source"
				. ' (its first prerequisite is ${a})'), $where, "\${$x}"));
			$val = $src;
		} elsif ($x eq '^X' or $x eq "\030") {
			$val = _un_fs($^X);
		} else {
			defined $D->{$x} or die _say(E => _diag(__("%s: undefined variable: %s"),
				$where, "\${$x}"));
			$val = $D->{$x};
		}
		my $q;
		if (defined $mods) {
			$val = eval {
				RdKw::WwW::SiteConf::Modifiers::_apply($val, $mods,
					quote => sub { $q = 1; shell_quote(@_) },
					expand => sub { $self->_subst($_[0], $node, $where, $src) });
			};
			defined $val or die $@ =~ /\AE: / ? $@ : "E: $where: $@";
		}
		if ($val eq '.' && length $slash) {
			# `./' is no use to anyone
			($val, $slash) = ('', '');
		}
		push @$quoted, [ length $out, length $val ] if $q && $quoted;
		$out .= $val . $slash;
	}
	$out . substr($line, $pos);
}

# A target as Makefile.in spells it: `name' (in b), `${b}/name' or
# `${c}/name', or those with ${B}/ in front.  Returns its key (see
# _key) and its name; the name is what ${@} is.
sub _read_target
{
	my ($self, $spec, $where) = @_;
	my $tree = 'b';
	my $norm = norm_dep($spec, pass_thru => 1);
	my $rest;
	TREE: for my $t (qw( b c )) {
		for my $base ("\${B}/\${$t}", "\${$t}") {
			defined($rest = uproot($base, $norm)) or next;
			$tree = $t;
			$rest =~ s!\A/+!!;
			last TREE;
		}
	}
	# (as it was written, unless it said a tree)
	defined $rest or $rest = $spec;
	$rest =~ /\$/ and die _say(E => _diag(__('%s: %q: a target is a name,'
		. ' optionally after ${b}/ or ${c}/; nowhere else under ${B}'), $where, $rest));
	_check_file($rest, $where);
	($self->_key($tree, $rest), $rest);
}

# Whether this (raw) prerequisite says where in ${a} the target comes
# from: it is ${a}, or begins with ${A}/${a}/ or ${a}/ (any number of
# slashes).  Returns what follows, which is empty if that is nowhere
# in particular; or undef if it is not in ${a}.  (A `$' that is no
# variable, as in `$@', is passed through; `$$' and `$x' may come back
# as `${$}' and `${x}', which are the same to _subst.)
sub _source_of
{
	my ($dep) = @_;
	defined(my $rest = uproot('${a}', norm_dep($dep, pass_thru => 1)))
		or return;
	$rest =~ s!\A/+!!;
	$rest;
}

# Makefile.in => { target => { recipe, deps, src, line } }
#
# The first prerequisite of a rule, if it is in ${a} (see _source_of),
# is its source, and then (as `src', named from ${a}) it takes the
# place of the one we would otherwise suppose: ${a}/${@}.
sub _read_rules
{
	my ($self) = @_;
	my $D = $self->{D};
	my $file = File::Spec->canonpath($D->{R});
	open my $fh, '<:encoding(UTF-8)', _to_fs($file)
		or die _say(E => _diag(__("cannot open file %q: %m"), $file));

	my (%rule, @node, $stanza);
	while (<$fh>) {
		next if /\A[$SP]*#(?:[$SP]|\z)/o or /\A[$SP]*\z/o;
		my $line = $.;
		my $where = _line($D->{R}, $line);
		# Fold rule headers before deciding whether an indented line
		# is a recipe.  Recipe backslashes belong to make/the shell.
		unless (/^\t/) {
			while (/(?<!\\)(?:\\\\)*\\\r?\n\z/) {
				s/[ \t]*\\\r?\n\z/ /;
				my $next = <$fh>;
				# a comment line does not end the header (nor is it in it)
				$next = <$fh> while defined $next and $next =~ /\A[$SP]*#(?:[$SP]|\z)/o;
				defined $next or die _say(E => _diag(__("%s: unfinished line continuation"), $where));
				$next =~ s/^[ \t]+//;
				$_ .= $next;
			}
		}
		# A line of the recipe of the rule above (or of this one)
		my $recipe = sub {
			my ($text) = @_;
			for my $node (@node) {
				my $rule = $rule{$node->[0]};
				if (defined $rule->{stanza} && $rule->{stanza} != $stanza) {
					die _say(E => _diag(__("%s: more than one recipe for %q"),
						$where, $node->[0]));
				}
				$rule->{stanza} = $stanza;
				# (not yet: ${<} may be said further down)
				push @{ $rule->{raw} }, [ $text, $where ];
			}
		};
		if (/^\t/) {
			# HEY!  a recipe line (one that begins with a tab)
			# with no rule above it to be the recipe of
			@node or die _say(E => _diag(__("%s: unexpected tabulation"), $where));
			$recipe->($_);
			next;
		}
		if (/:/) {
			my ($src, $dep) = split /:/, $_, 2;
			# After a `;' is the first line of the recipe, and a tab
			# line after this one is the next
			my $cmd;
			$dep =~ /\A($PREREQ);[ \t]*(.*)\z/so
				and ($dep, $cmd) = ($1, "\t$2");
			@node = map { [ $self->_read_target($_, $where) ] } _words($src)
				or die _say(E => _diag(__("%s: null target list"), $where));
			$stanza = $line;
			for my $node (@node) {
				my ($key, $name) = @$node;
				my $rule = ($rule{$key} ||= { recipe => '', raw => [], deps => [],
					want => [], name => $name, line => $line });
				my $dep = $dep;
				if (!$rule->{decided} && $dep =~ /[^$SP]/o) {
					$rule->{decided} = 1;
					# the first word (a ${...} may hold spaces, in :S/ /_/)
					my ($first) = $dep =~ /\A[$SP]*($WORD)/o;
					if (defined $first and defined(my $from = _source_of($first))) {
						# ${a} alone says there is none (and ${<} is not known)
						my $name_of = length $from ? $self->_subst($from, $name, $where) : '';
						length $from and do {
							$name_of =~ /[^$SP]/o and $name_of !~ /[$SP]/o
								or die _say(E => _diag(__('%s: %q must be one name in ${a}'),
									$where, $first));
							_check_file($name_of, $where);
						};
						$rule->{src} = $name_of;
						$dep =~ s/\A[$SP]*\Q$first\E//;
					}
				}
				# NEED:x (or just x) is a prerequisite, and WANT:x
				# one that can be done without: said as it is written,
				# before anything is expanded, and of each word it
				# expands to.  Nothing else may come before a colon.
				for my $word (_raw_words($dep)) {
					my $kind = 'deps';
					if ($word =~ s/\A([^$SP\$\/:]*)://o) {
						$1 eq 'NEED' or $1 eq 'WANT'
							or die _say(E => _diag(__("%s: %q: a prerequisite must"
								. " either NEED: or WANT: before a colon"), $where, "$1:$word"));
						$kind = $1 eq 'WANT' ? 'want' : 'deps';
						# HEY!  %q is NEED: or WANT:, with no name after it
						length $word or die _say(E => _diag(__("%s: %q of nothing"),
							$where, "$1:"));
					}
					push @{ $rule->{$kind} },
						_words($self->_subst($word, $name, $where));
				}
			}
			$recipe->($cmd) if defined $cmd;
			next;
		}
		(my $text = $_) =~ s/\r?\n\z//;
		die _say(E => _diag(__("%s: invalid line: %q"), $where, $text));
	}
	close $fh;
	for my $rule (values %rule) {
		my $src = defined $rule->{src} ? $rule->{src} : $rule->{name};
		# The recipe is in make's words: a `$' from $$ or a variable
		# is make's, but one in what a :Q made is the shell's, $$
		for (@{ $rule->{raw} }) {
			my @q;
			my $line = $self->_subst($_->[0], $rule->{name}, $_->[1], $src, \@q);
			substr($line, $_->[0], $_->[1]) =~ s/\$/\$\$/g for reverse @q;
			$rule->{recipe} .= $line;
		}
		delete $rule->{raw};
	}
	\%rule;
}

# A node of the graph: what it takes to make one file in `b' from one
# in `a'.  `ok' says whether that can be done at all, and `why' not
# if it cannot.  A dependency on something in `b' is an edge to
# the node for that, which is how we know to make it (and to make it
# first); `kids' are those.
sub _node
{
	my ($self, $file) = @_;
	my $D = $self->{D};
	if (my $node = $self->{node}{$file}) {
		if ($node->{visiting}) {
			my @stack = @{ $self->{stack} };
			shift @stack while @stack && $stack[0] ne $file;
			# HEY!  %s is the files, as `a' -> `b' -> `a'
			die _say(E => _diag(__("dependency cycle: %s"),
				join(' -> ', map { _diag('%q', $_) } @stack, $file)));
		}
		return $node;
	}

	my $rule = $self->{rules}{$file};
	# Its source: what the rule says, or ${a}/${@} if it says nothing
	my (undef, $name) = _unkey($file);
	my $src = $rule && defined $rule->{src} ? $rule->{src} : $name;
	# (an empty one is no source at all: the rule has said ${a})
	my $nosrc = !length $src;
	my $apath = $nosrc ? undef : $self->_apath($src);
	my $bpath = $self->_bpath($file);
	basename($bpath) eq $D->{e}
		and die _say(E => _diag(__("%q: %q is reserved for directory markers."), $file, $D->{e}));

	my $node = $self->{node}{$file} = {
		file => $file,
		apath => $apath,
		nosrc => $nosrc,
		bpath => $bpath,
		deps => [],
		kids => [],
		recipe => '',
		ok => 1,
		why => [],
		visiting => 1,
	};
	push @{ $self->{stack} }, $file;
	my $fail = sub { $node->{ok} = 0; push @{ $node->{why} }, @_; };
	my $done = sub { delete $node->{visiting}; pop @{ $self->{stack} }; $node };

	unless ($rule) {
		$fail->(_diag(__("no rule to make it (%q)"), $D->{R}));
		return $done->();
	}
	unless ($nosrc or -f _to_fs($self->_fs($apath))) {
		$fail->($rule->{line}
			# HEY!  the %s is where the rule is (`file' line 3)
			? _diag(__("source %q is missing (rule at %s)"), $apath, _line($D->{R}, $rule->{line}))
			: _diag(__("source %q is missing"), $apath));
		return $done->();
	}
	$node->{recipe} = $rule->{recipe};

	my %I = $nosrc ? () : read_deps($self->_fs($apath));
	if (defined $I{HAVE}) {
		# The source's own name, as a header spells it, is the one
		# the rule says it is: ${A}/${a}/FILE.
		my $where = _diag('%q: HAVE', $apath);
		my $have = $self->_expand($I{HAVE}, $where);
		my $want = File::Spec->canonpath("$D->{a}/$src");
		$have eq $want or die _say(E => $have ne $I{HAVE}
			# HEY!  Keep the question mark: we are as puzzled as
			# anyone.  The (aka %q) is what the HAVE says, expanded
			? _diag(__("%q: You HAVE %q (aka %q),\nbut I need %q?"),
				$apath, $I{HAVE}, $have, $want)
			: _diag(__("%q: You HAVE %q,\nbut I need %q?"), $apath, $I{HAVE}, $want));
	}

	# What the headers say they need, and what the rules do
	my $where = _diag('%q', $nosrc ? $file : $apath);
	# HEY!  This and the next three are where a NEED (or a WANT)
	# was said, and are said in parentheses after what is needed
	my $from = $nosrc ? __("in header") : _diag(__("in header of %q"), $apath);
	my @hneed = map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{NEED} || [] };
	my @hwant = map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{WANT} || [] };
	my $rule_at = _line($D->{R}, $rule->{line});
	my @rdep = map { [ $_, $_, _diag(__("prerequisite in %s"), $rule_at) ] } @{ $rule->{deps} };
	my @rwant = map { [ $_, $_, _diag(__("WANT: in %s"), $rule_at) ] } @{ $rule->{want} || [] };
	# What the source files we NEED (or WANT) say they need, and so on:
	# like gcc -MM, which lists the headers of headers.
	{
		# How firmly each file has been followed: 1 for soft, 2 for hard.
		# A file first met as a WANT is met again as a NEED (of something
		# else), and then what it NEEDs is NEEDed too, so only a visit at
		# least as firm as an earlier one is skipped.
		my %seen = $nosrc ? () : ($apath => 2);
		my (@more_need, @more_want);
		my $follow; $follow = sub {
			my ($list, $soft) = @_;
			my $firm = $soft ? 1 : 2;
			for my $d (@$list) {
				($seen{$d->[1]} || 0) >= $firm and next;
				$seen{$d->[1]} = $firm;
				my ($need, $want) = $self->_inherit($d->[1]);
				push @{ $soft ? \@more_want : \@more_need }, @$need;
				push @more_want, @$want;
				$follow->($need, $soft);
				$follow->($want, 1);
			}
		};
		$follow->(\@hneed, 0);
		$follow->(\@hwant, 1);
		push @hneed, @more_need;
		push @hwant, @more_want;
		# The same file may have turned up through several others, and
		# as both: say it once, and a NEED is not a WANT as well
		my %said;
		@hneed = grep { !$said{$_->[1]}++ } @hneed;
		@hwant = grep { !$said{$_->[1]}++ } @hwant;
	}
	# What the rule's own prerequisites (the tools) say they need, if
	# they say anything at all
	for my $dep (@{ $rule->{deps} }) {
		my ($need, $want) = $self->_tool($dep, $file, $rule);
		push @hneed, @$need;
		push @hwant, @$want;
	}
	# (and what a tool we can do without needs, we can do without too)
	for my $dep (@{ $rule->{want} || [] }) {
		my ($need, $want) = $self->_tool($dep, $file, $rule);
		push @hwant, @$need, @$want;
	}

	my @deps = $nosrc ? () : ($apath);
	my %tree = map { File::Spec->canonpath($D->{$_}) => 1 } qw( b c );
	my $check = sub {
		my ($said, $dep, $from, $soft) = @_;
		return 1 if $tree{$dep};
		if (defined(my $made = $self->_target($dep))) {
			my $kid = $self->_node($made);
			unless ($kid->{ok}) {
				return 0 if $soft;
				# (a cause per line, each cause deeper than what it breaks)
				# HEY!  %s is where it was needed (in header of `file'),
				# here and in the next two
				$fail->(_diag(__("NEEDs %q (%s), but cannot be made:"), $dep, $from),
					map { "  $_" } @{ $kid->{why} });
				return 0;
			}
			push @{ $node->{kids} }, $made unless grep { $_ eq $made } @{ $node->{kids} };
			return 1;
		}
		return 1 if -e _to_fs($self->_fs($dep));
		unless ($soft) {
			$fail->($said =~ m!\AMY/(?:config|option)\.mk\z!
				# HEY!  The last %q is the name it may have meant: a
				# header says MY/option.mk, when it is ${B}/MY/option.mk
				? _diag(__("NEEDs %q (%s), which we don't seem to have (is it %q?)"),
					$dep, $from, "\${B}/$said")
				: _diag(__("NEEDs %q (%s), which we don't seem to have"), $dep, $from));
		}
		0;
	};
	for my $d (@rdep, @hneed) {
		$check->(@$d, 0) and push @deps, $d->[1];
	}
	for my $d (@rwant, @hwant) {
		if ($check->(@$d, 1)) {
			push @deps, $d->[1];
		} else {
			# HEY!  Keep the sad face :(  The %s, in parentheses,
			# is where it was wanted (in header of `file')
			$self->_warn(_say(W => _diag(__("target %q WANTs %q\n"
				. "  (%s)\n"
				. "... but it is missing; going on without it :("), $file, $d->[1], $d->[2])));
		}
	}

	my %iHaz;
	$node->{deps} = [ grep { !$iHaz{$_}++ } @deps ];
	$done->();
}

# The NEEDs and WANTs in the header of `dep' (seen from the build dir),
# as in _tool, if `dep' is a source file: something we make is not
# followed (what it takes to make it is the rule's business, and the
# build tool's order).
sub _inherit
{
	my ($self, $dep) = @_;
	my $got = $self->{inherit}{$dep} ||= do {
		my $fs = $self->_fs($dep);
		my %I = !defined $self->_target($dep) && -f _to_fs($fs) && -T _
			? read_deps($fs) : ();
		my $where = _diag('%q', $dep);
		my $from = _diag(__("in header of %q"), $dep);
		[
			[ map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{NEED} || [] } ],
			[ map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{WANT} || [] } ],
		];
	};
	@$got;
}

# Whether two paths seen from the build dir are spelled alike, once
# the root in front of an absolute one is spelled as seen from the
# build dir too.  (The rules spell ${A}/x as config.mk spells A, which
# may be absolute.)  Only the root is ever resolved -- what is under
# it, symlinks and all, is taken as it is written.
sub _same
{
	my ($self, @path) = @_;
	my $root = File::Spec->abs2rel($self->{Rabs}, $self->{Babs});
	my %iHaz;
	my @abs = grep { File::Spec->file_name_is_absolute($_) && !$iHaz{$_}++ }
		map { File::Spec->canonpath($_) } $self->{D}{A}, $self->{Rabs};
	for my $p (@path) {
		$p = File::Spec->canonpath($p);
		for my $r (@abs) {
			if ($p eq $r) {
				$p = $root;
				last;
			}
			if (index($p, "$r/") == 0) {
				$p = File::Spec->canonpath(File::Spec->catfile($root,
					substr($p, length($r) + 1)));
				last;
			}
		}
	}
	$path[0] eq $path[1];
}

# The NEEDs and WANTs in the header of a rule's prerequisite `dep'
# (seen from the build dir), as [ said, dep ] pairs; `file' and `rule'
# are who asked, for telling the user.  A tool need not
# have a header (or be text, or be a plain file); then it has none.
# What we make has its own node, so it is not a tool.
sub _tool
{
	my ($self, $dep, $file, $rule) = @_;
	my $tool = $self->{tool}{$dep} ||= do {
		my $fs = $self->_fs($dep);
		my %I = !defined $self->_target($dep) && -f _to_fs($fs) && -T _
			? read_deps($fs) : ();
		if (defined $I{HAVE}) {
			my $have = $self->_dep($I{HAVE}, _diag('%q: HAVE', $dep));
			my $at = _line($self->{D}{R}, $rule->{line});
			$self->_same($have, $dep)
				or die _say(E => $have ne $I{HAVE}
					# HEY!  As above, for a tool of the rule; the last %s
					# is where the rule is (`file' line 3)
					? _diag(__("%q: You HAVE %q (aka %q),\nbut I need %q for the rule for %q (%s)?"),
						$dep, $I{HAVE}, $have, $dep, $file, $at)
					: _diag(__("%q: You HAVE %q,\nbut I need %q for the rule for %q (%s)?"),
						$dep, $I{HAVE}, $dep, $file, $at));
		}
		my $where = _diag('%q', $dep);
		my $from = _diag(__("in header of %q"), $dep);
		{
			need => [ map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{NEED} || [] } ],
			want => [ map { [ $_, $self->_dep($_, $where), $from ] } @{ $I{WANT} || [] } ],
		};
	};
	($tool->{need}, $tool->{want});
}

=item B<plan>

Reads everything, resolves what is C<WANT>ed, and returns the build
as a hash reference.  Dies, listing every one of them, if anything
that is C<NEED>ed cannot be had.

  goals   [ { name, files => [ FILE ... ], dropped => [ [FILE, WHY] ] } ]
  node    { FILE => { file, apath, nosrc, bpath, deps, recipe } }
  order   [ FILE ... ]    all files, in order of appearance
  dirs    [ { dir, marker, deps => [ MARKER ] } ]   parents first
  clean   [ { name, files => [ BPATH ] } ]
  D       the definitions, as in MY/config.mk

=cut

sub plan
{
	my ($self) = @_;
	my $D = $self->{D};
	$self->{node} = {};
	$self->{stack} = [];
	$self->{tool} = {};
	$self->{rules} = $self->_read_rules;

	my @spec = $self->read_manifest(File::Spec->canonpath($D->{F}));

	my (@goal, @err, @order, %known);
	# A file comes after what it takes to make it
	my $add; $add = sub {
		my ($file) = @_;
		return if $known{$file}++;
		$add->($_) for @{ $self->{node}{$file}{kids} };
		push @order, $file;
	};
	for my $spec (@spec) {
		my (@files, %iHaz, @dropped);
		for my $kind (qw( need want )) {
			for my $ent (@{ $spec->{$kind} }) {
				my $file = $ent->{file};
				my $node = $self->_node($file);
				if ($node->{ok}) {
					next if $iHaz{$file}++;
					push @files, $file;
					$add->($file);
					next;
				}
				# (one line for the manifest, which has one; else a line each)
				my $why = join ' ', map { (my $l = $_) =~ s/\A\s+//; $l } @{ $node->{why} };
				my $causes = sub { my $p = shift; join '', map { "$p   $_\n" } @{ $node->{why} } };
				if ($kind eq 'need') {
					# HEY!  the %s is where (`file' line 3); what
					# follows the colon is why, a line each
					push @err, _say(E => _diag(__("%s: goal %q NEEDs %q, but cannot be made:"),
						_line($D->{F}, $ent->{line}), $spec->{name}, $file))
						. $causes->('E:');
				} else {
					push @dropped, [ $file, $why ];
					$self->_warn(_say(W => _diag(__("goal %q WANTs %q, but cannot be made:"),
						$spec->{name}, $file)), $causes->('W:'));
				}
			}
		}
		push @goal, { name => $spec->{name}, files => \@files, dropped => \@dropped };
	}
	# HEY!  "no soup for you!" (Seinfeld), but a Makefile
	@err and die @err, _say(E => _diag(__n("%d problem; no Makefile for you.",
		"%d problems; no Makefile for you.", scalar @err), scalar @err));

	# Every file hangs off the marker of its parent directory (and
	# every marker off its own parent's), so that a parallel build
	# does not try to put anything where there is nowhere yet.
	my (@dir, %dir);
	for my $file (@order) {
		my $node = $self->{node}{$file};
		my @parent = _parents($node->{bpath});
		@parent or next;
		push @{ $node->{deps} }, "$parent[0]/$D->{e}";
		for my $i (reverse 0 .. $#parent) {
			my $dir = $parent[$i];
			next if $dir{$dir}++;
			push @dir, {
				dir => $dir,
				marker => "$dir/$D->{e}",
				deps => $i < $#parent ? [ "$parent[$i + 1]/$D->{e}" ] : [],
			};
		}
	}

	my @clean = $self->_clean_rules(\@goal, \@order, \@dir);

	+{
		goals => \@goal,
		node => { map { $_ => $self->{node}{$_} } @order },
		order => \@order,
		dirs => \@dir,
		clean => \@clean,
		D => $D,
	};
}

# The cleaning rules, as { name, files => [ BPATH ] } (see
# _clean_pattern).  The only rule that is not for a goal removes
# everything we made; one that is takes what the goal needs.  The
# directory markers are left in either case.
sub _clean_rules
{
	my ($self, $goal, $order, $dir) = @_;
	my $pat = $self->_clean_pattern;
	defined $pat or return;
	my $node = $self->{node};
	my @rule;
	if ($pat =~ /&/) {
		my %pos; @pos{@$order} = 0 .. $#$order;
		for my $g (@$goal) {
			(my $name = $pat) =~ s/&/$g->{name}/g;
			my %have;
			my $walk; $walk = sub {
				$have{$_[0]}++ and return;
				$walk->($_) for @{ $node->{$_[0]}{kids} };
			};
			$walk->($_) for @{ $g->{files} };
			push @rule, { name => $name,
				files => [ map { $node->{$_}{bpath} } sort { $pos{$a} <=> $pos{$b} } keys %have ] };
		}
	} else {
		push @rule, { name => $pat,
			files => [ map { $node->{$_}{bpath} } @$order ] };
	}
	my %taken = (%reserved_goal, map { $_->{name} => 1 } @$goal);
	for my $rule (@rule) {
		my $name = $rule->{name};
		# HEY!  %s is the option, as -Dclean=clean-&
		$taken{$name}++ and die _say(E => _diag(__("%s: %q is"
			. " also the name of a goal or another rule"), "-Dclean=$self->{D}{clean}", $name));
	}
	@rule;
}

# parents('a/b/c') => ('a/b', 'a')
sub _parents
{
	my ($path) = @_;
	my @parent;
	while ((my $up = dirname($path)) ne '.') {
		push @parent, $path = $up;
	}
	@parent;
}

=item B<manifest_text> I<goal>

The goal, resolved, in the format of the manifest.

=cut

sub manifest_text
{
	my ($self, $goal) = @_;
	my $text = "#\n# resolved by `$self->{prog} -g'\n#\n";
	$text .= "MAKE $goal->{name}\n";
	$text .= "\tNEED $_\n" for @{ $goal->{files} };
	for my $drop (@{ $goal->{dropped} }) {
		$text .= "#\tWANT $drop->[0]\t# $drop->[1]\n";
	}
	$text;
}

=item B<generate> [ I<generator>, [ I<file> ] ]

Writes F<MY/MANIFEST.I<goal>> for each goal, and the build file
for I<generator> (C<make>, the default, C<gmake> or C<ninja>), named
I<file> in the build directory if given (else F<Makefile> or
F<build.ninja>).
The files that would not change are left alone, mtime and all.

=cut

my %generator = (
	make => [ 'RdKw::WwW::SiteConf::Make', 'Makefile' ],
	gmake => [ 'RdKw::WwW::SiteConf::GMake', 'Makefile' ],
	ninja => [ 'RdKw::WwW::SiteConf::Ninja', 'build.ninja' ],
);

sub generate
{
	my ($self, $G, $out) = @_;
	$G = 'make' unless defined $G and length $G;
	# HEY!  %s is the generators (make, gmake, ninja)
	my $gen = $generator{$G} or die _say(E => _diag(__("unknown generator %q.  Choose one of: %s"),
		$G, join(', ', sort keys %generator)));
	my ($module, $outfile) = @$gen;
	my $named = defined $out && length $out;
	if ($named) {
		$out =~ m!\A[^/\0]+\z! and $out !~ /\A\.\.?\z/
			or die _say(E => _diag(__("bad output name %q: a file in the build directory, please"),
				$out));
		$outfile = $out;
	}
	(my $pm = "$module.pm") =~ s!::!/!g;
	require $pm;

	my $plan = $self->plan;
	my $My = "$self->{B}/MY";
	my %have;
	for my $goal (@{ $plan->{goals} }) {
		my $name = "MANIFEST.$goal->{name}";
		$have{$name}++;
		$self->_report($name, update_file("$My/$name", $self->manifest_text($goal)));
	}
	# Goals that are no more
	for my $old (glob(_to_fs("$My/MANIFEST.*"))) {
		my $name = basename(_un_fs($old));
		$name =~ /\AMANIFEST\.[A-Za-z0-9][-\w.+]*\z/ or next;
		$have{$name} or do {
			unlink $old;
			$self->_warn(_diag(__("Removing %q"), "MY/$name") . "\n");
		};
	}

	$plan->{prog} = "$self->{prog} -g -G $G" . join '', map {
		" -$_ " . shell_quote($self->{fromhere}{$_})
	} sort keys %{ $self->{fromhere} };
	$plan->{prog} .= " -o " . shell_quote($out) if $named;
	my $text = $module->_emit($plan);
	$self->_report($outfile, update_file("$self->{B}/$outfile", $text));

	# What to type next: the builder (named after the generator), with
	# -C if we are not in the build directory, -f if the file is not
	# the one it would look for, and the first goal of the manifest.
	my @cmd = ($G);
	push @cmd, '-C', shell_quote($self->{B}) unless $self->{B} eq '.';
	push @cmd, '-f', shell_quote($outfile) if $named;
	push @cmd, shell_quote($plan->{goals}[0]{name}) if @{ $plan->{goals} };
	$self->_warn(__("Done!") . "\n");
	# HEY!  %s is a command line, as the shell would read it
	$self->_warn(_diag(__("To build, run: %s"), "@cmd") . "\n");
	$plan;
}

sub _report
{
	my ($self, $name, $what) = @_;
	return unless $what;
	$name = "MY/$name" if $name =~ /^MANIFEST\./;
	# HEY!  Writing is what was not there, and Updating what was
	$self->_warn(_diag($what > 1 ? __("Writing %q") : __("Updating %q"), $name) . "\n");
}

=back

=cut

1;
