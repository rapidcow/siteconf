package RdKw::WwW::SiteConf;

use 5.008;
use strict;
use warnings;

use version;
our $VERSION = '0.03_00';
$VERSION = version->parse( $VERSION );

=encoding utf8

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

    $sc->generate('make');      # MY/MANIFEST and the Makefile

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
modifiers C<:Q> to shell-quote (C<${A:Q}>; only last, and only in a
recipe, where a C<$> in what it makes is for the shell, and is written
C<$$>, while one from C<$$> or a variable is make's), C<:E>, C<:H>, C<:R>, C<:T>
and C<:S/old/new/> to take names apart (C<${@:R}>); see
L<RdKw::WwW::SiteConf::Modifiers>.  Targets are named
relative to C<${b}>, or to C<${c}> if they say so (below).  Prerequisites are
paths from the project root, like those in a header (C<${A}> is C<.> there).
A prerequisite of a rule (a tool, such as the
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

A prerequisite may also be C<JUST:x> (the same as C<JUST-NEED:x>) or
C<JUST-WANT:x>: it is needed, or wanted, as C<NEED:> and C<WANT:> say, but
its header is not read, and what it declares is not followed.  That
is for what is not text, or is not to be looked at.  A tool with
C<JUST:> need not have a header, and does not have one that counts.

    pack.bin: JUST:${A}/tool.pickle
            ${A:Q}/pack ${B:Q}/${b:Q}/${@:Q}

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

A space within a file name is written C<${U+20}> or C<${U+0020}>,
in targets, prerequisites, F<MANIFEST>, and source headers alike.
Choose C<-G gmake> or C<-G ninja>; the POSIX make backend rejects
such names.  Quote the names in recipes with C<:Q>:

    my${U+20}page.html: ${a}/my${U+0020}source.txt ${A}/some${U+20}dependency
            cp ${A:Q}/${a:Q}/${<:Q} ${B:Q}/${b:Q}/${@:Q}

    # MANIFEST
    MAKE all
        NEED my${U+0020}page.html

A name may also hold C<*>, C<?>, C<[> and C<]>, as in C<feed/[year]/index.html>.
C<-G gmake> writes each of the first three in brackets, which GNU make
reads as that character (C<a[*]b>); C<-G make> and bmake would take them as
a pattern, so C<-G make> rejects such a name.  The shell takes them as a pattern
too, so quote the name in a recipe with C<:Q>.

C<:Q> quotes bytes.  A name or a value is spelled as the file system spells it
first, and C<:Q> (as the last modifier) quotes that.  So a character that the
encoding spells with an ASCII byte (Shift_JIS spells 表 as C<95 5C>, and a
C<\> is that byte for a shell) is safe in C<:Q>, as in
C<${U+8868:Q}>.  In a name it is an error, as no escape could tell make or
the shell what it is; a letter, a digit and C<_.+,@-> pass.  The text of a
recipe, and a variable that is not quoted, are as you write them.

Words are told apart where they are written, never by what a variable
holds: every word of a target or prerequisite list is one name, however
many blanks its variables expand to, so C<-Dx='my dir'> makes C<${x}/a>
one file, F<my dir/a>.  (A name that expands to nothing is an error.)
Recipes are different, since they are for the shell: a variable there is
text, and C<-DPY='python3 -m foo'> may be a command; C<:Q> quotes a
value as a whole.  The word modifiers (C<:E>, C<:H>, C<:R>, C<:T>, C<:S>)
take a value as one name, too: see L<RdKw::WwW::SiteConf::Modifiers>.

Target and dependency lists may span multiple lines: end each
continued line with a backslash.  The backslash and newline, along
with indentation on the next line, are replaced by a space.  Lines
that are only a comment (a C<#> after any indentation, then whitespace
or the end of the line: C<#foo> is a word) in between are skipped,
and do not end the list -- unlike in L<make(1)>, where one would
take the rest of the list with it:

    ${b}/index.html \
    ${b}/about.html \
        : \
    # why this is spelled out
        ${a}/site/${.TARGET}

=item String literals

Where a character may be said as C<${U+>I<hex>C<}> (in a name, in a
recipe, in a header, in F<MANIFEST>, in F<MY/config.mk>), a string may
be as well: C<${"...">C<}> is each of its characters.  Inside a string,
a backslash begins one of C<\a \b \t \n \v \f \r \e> (the controls of C),
C<\s> (a space), C<\\>, C<\">, or C<\x{>I<hex>C<}> (a code point, in
braces, to make clear it is one); anything else is an error.  Nothing
else is special, so C<$> and C<}> are as they are.  Modifiers go after
it, in Makefile.in: C<${"表":Q}>.

A string says what is said; it is I<not> quoted.  That is for C<:Q>,
and what is quoted by bytes, last, is for the backend to say or not: a
C<${"\n":Q}> is an error to make and to ninja, as a line break ends a
command to both, and C<${"Icon\r":Q}> is not.

=item F<Makefile.in> variables

A line that begins with a name, C<=>, and a value is a variable.  The
name is C<\w+> (letters of any script, digits and C<_>), and no other
character; C<U+...> and the names that begin with a dot are for us.

    dir = feed            # a comment, after a blank
    from = ${a}/${dir}    # a variable that is there already
    表 = 表
    text = h u h
        a${"\s"}
         b
        # not a comment${"\s"}
    # a comment
        c
        ${""}

    ${dir}/index.html: ${from}/index.md
            echo ${text:Q} ${表:Q}

Only the first C<=> counts.  The value is what follows it, up to a
C<#> that follows a blank, without the blanks around it.  The lines
that follow, each beginning with a tab, are more of it: they are joined
by a line break (one tab is removed from each, and the blanks at its end,
so a space that is to stay is C<${"\s"}>), and a C<#> in one is just a
C<#>.  Comment lines and blank lines between them are skipped; a tab and
nothing else is an empty line, and so is C<${""}> (the example's text
ends with a line break).  If the first line says nothing, the value
begins with the next.

The value is expanded where it is: a variable in it is what it is now,
and it is no more than text after that.  C<:Q> is an error in it (it
is for a recipe).  It is an error to define what is defined
already, in F<config.mk> or above.  A variable is known to what follows
it (a recipe, as much as a prerequisite or a target; for a target, only
a variable that is defined here) and to nothing else: a header does not
see it.  The value of a variable that is not quoted is text in a
recipe, as it is.

=item F<Makefile.in> C<INCLUDE> and C<AUGMENT>

C<INCLUDE> reads one or more UTF-8 files of rules where it stands.
C<AUGMENT> reads one or more files of C<target: prerequisites> lines:
each target must have a rule (which may come later), and the
prerequisites are added to it, with its source left as it is.  A path
of either is expanded as a prerequisite is, and is relative to
C<${A}>, so C<${B}/deps> and C<${data}/deps> can be used.  Every file
named must exist, and none may include itself.

=item F<MANIFEST> (C<F>)

The goals of the build, each a L<make(1)> target:

    MAKE all
        NEED index.html           # hard: no rule or source, no build
        WANT extra/index.html     # soft: dropped, with a warning

    MAKE small
        NEED index.html about.html

Indentation is only for the eyes.  A C<#> preceded by whitespace
(or at the start of the line) begins a comment.  File names are
relative to C<${a}> (and made in C<${b}>).  Each keyword may have a
colon after it (C<MAKE: all>, C<NEED: index.html>).  C<NEED> and
C<WANT> take any number of names, split at white space as everywhere
else.

C<INCLUDE> reads one or more manifests where it stands, and the last
C<MAKE> goes on in them and after them.  Its paths are relative to
C<${A}>, and are unescaped as a file name is (below), with what is in
F<config.mk> substituted (C<${A}> is C<.>; no modifiers).

A file name is unescaped as a header's is (see
L<RdKw::WwW::GenGenLib::Manifest>): C<${$}> is a C<$> and
C<${U+>I<hex>C<}> a character, as in C<r${U+00E9}sum${U+00E9}.html>, and
C<${"...">C<}> is the characters of a string (see below); there are no
variables.  What it comes to must still be a permitted target name:
spaces are allowed with GNU make or Ninja, but C<$>, C<#>, C<:> and the
like are not; nothing absolute, and no C<..>.

A goal name is not unescaped.  It may be anything but white space (of
any script: a no-break space too), a control or format character, and
C<:>, C<#>, C<%>, C<$> and C<\>, and it may not begin with C<->.  So it
may have slashes, and letters of any script.  The backend then decides
whether it can say it.

C<JUST-NEED> and C<JUST-WANT> are those two, for a name whose header is
not read (the header of the source that makes it, for a target, which is
what a goal names).  They are spelled in full, and the same way in a
header.  The resolved manifest keeps them: a C<JUST-WANT> that was had
is a C<JUST-NEED>, and one that was not is commented out.

    MAKE christmas
        WANT      not-a-lot
        JUST-NEED one-thing

A header is read if any place says C<NEED> or C<WANT> of its file, and
left alone if every place says C<JUST->.  A C<JUST-NEED> only asks
that its file's header need not be read for it.

A name that is also the name of a goal stands for what that goal
needs, as if its names were written where it is: a C<NEED> of it has
its C<NEED>s and C<WANT>s as they are, a C<WANT> of it wants them all.

    MAKE default
        NEED: food

    MAKE food
        NEED: ${"some\sbread"} jam

A goal that needs itself, directly or through others, is an error.
No file may have the name of a rule, which is a goal that is made, or a
cleaning rule.  That is checked for the characters of both, and for the
bytes that the file system and the arguments make of them.  So C<MAKE
site/index.html> clashes with the file F<site/index.html>, unless that
goal was not asked for (C<-t>).  A directory is no file here: C<MAKE
site> is fine.

=item the files themselves

A source file declares its place in the graph in a header (see
L<RdKw::WwW::GenGenLib/read_deps>, which also says what comments they
may hide in):

    # HAVE: ${A}/${a}/index.html
    # NEED: skel/HTML
    # NEED: ${B}/${b}/style.css
    # WANT: ${A}/data/extra.scm
    # JUST-NEED: ${B}/${b}/pickle.bin

C<JUST-NEED> and C<JUST-WANT> are the same two, for what is only a name:
the file is a dependency, but its own header is not read.

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
F<MY/MANIFEST> in the very same format, a block for each goal (all
C<NEED>, with what was dropped left as comments).

File names, here and in what we are given, are character strings:
they are spelled as L<RdKw::I18N::CodeSets> says
(L<RdKw::I18N::CodeSets/filesys> of C<< RdKw::I18N::CodeSets->locale >>)
on their way out to the system, and a name it cannot spell is an error.
F<Makefile.in>, F<MANIFEST> and F<MY/MANIFEST> are UTF-8.  The build
file is bytes: L<make(1)> and L<ninja(1)> read it so, and every name in
it is spelled as the file system spells it.  The backends say how.

=head1 METHODS

=over

=cut

use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname basename );
use File::Spec ();

# Import locale and set up gettext.
use RdKw::I18N::CodeSets::Functions qw( diag to_fs un_fs to_argv tagmsg qq_ascii );
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';

use RdKw::WwW::GenGenLib 0.0100 qw(
	read_make read_deps update_file escape_dep
	norm_dep uproot );
use RdKw::WwW::SiteConf::Modifiers;

sub _status { $! = 0; $? = shift; @_; }

# A name as the file system spells it, and back;
# or an error prefixed `E:'.
sub _to_fs { to_fs($_[0], { prog => 'E' }); }
sub _un_fs { un_fs($_[0], { prog => 'E' }); }

# Where in a file: `file' line 3
# (Since our standard names (MANIFEST and Makefile.in)
# are usually well-behaved, the quotes are only used
# when the user overrides them with exotic file names.)
sub _blame
{
	my ($file, $line) = @_;
	# HEY!  %#q is the file name of the faulty
	# file and %d is its lineno.
	diag(__("%#q line %d"), $file, $line);
}

# Goals of the manifest cannot take these names; `Makefile' because
# we write it, and `MY' is a directory.  (`clean', or whatever -Sclean
# makes of it, is reserved too if there is such a rule: see _clean_pattern.)
my %reserved_goal = map { $_ => 1 } qw( Makefile MY );

# POSIX white space.
my $SP = '\t\n\cK\f\r ';

# NEED:, WANT: and the others: whether it is in `deps' or `want', and JUST
my %PREFIX = (
	NEED => [ deps => 0 ], WANT => [ want => 0 ],
	JUST => [ deps => 1 ], 'JUST-NEED' => [ deps => 1 ], 'JUST-WANT' => [ want => 1 ],
);

# A word of Makefile.in as it is written: a ${...} may hold spaces
# (in :S/ /_/), and it is all one word.
my $STR = qr/"(?:[^"\\]|\\.)*"/s;
my $BRACED = qr/\$\{(?:$STR)?(?:[^{}\\]|\\.|\{[^{}]*\})*\}/s;
my $WORD = qr/(?:[^$SP\$]|\$(?!\{)|$BRACED)+/;

# The prerequisites of a rule: up to a `;', which begins its recipe,
# as in `a: b ; cp b a' -- but not one in a ${...} (:S/;/,/), nor $;
my $PREREQ = qr/(?:[^;\$]|$BRACED|\$[^{]|\$\z)*/;
# The targets of a rule: up to its first `:', but not one in a ${...}
# (${"File::Spec"}, ${x:Q})
my $TARGETS = qr/(?:[^:\$]|$BRACED|\$[^{]|\$\z)*/;

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

=item B<new> B =E<gt> I<dir>[, D =E<gt> { ... }, S =E<gt> { ... }, quiet =E<gt> 1, strict =E<gt> 1 ]

I<dir> is the build directory, as seen from the current directory.
C<MY/config.mk> there must exist.  Warnings are not printed when
I<quiet> is true.  When I<strict> is true, a C<WANT> that cannot be
had is an error (said even if I<quiet>), as it is for a C<NEED>,
except that the build is still planned and written without it, and
L</failed> says so afterwards.  I<D> overrides C<MY/config.mk> parameters.
(C<F> and C<R>, whether from here or from there, are paths from the
current directory, not from the project root.)  I<S> sets the options of
the generator (C<-S> of C<siteconf -g>): a name, and a value that may be
undef.  They are not kept anywhere.

C<goals =E<gt> [ ... ]> selects manifest goals, in the order given,
as C<goal>, C<NEED:goal> (both keep NEED and WANT as declared), or
C<WANT:goal> (all files are wanted).  A repeated goal keeps its first
position and its last mode.  Each may be a comma-separated list.  An
empty list, or none, selects the first goal of the manifest.

=cut

sub new
{
	my ($class, %arg) = @_;
	my $self = bless {
		B => defined $arg{B} && length $arg{B} ? $arg{B} : '.',
		quiet => $arg{quiet},
		strict => $arg{strict},
		goals => [ @{ $arg{goals} || [] } ],
		prog => defined $arg{prog} ? $arg{prog} : 'siteconf',
		# the options of the backend (-S), each a name and a value that may
		# be undef: they are not in config.mk, and are not kept
		S => { %{ $arg{S} || {} } },
	}, $class;

	my $conf = "$self->{B}/MY/config.mk";
	-f _to_fs($conf) or die _status 0, tagmsg(E => diag(__(
		# HEY!  Keep a winky face in the translation ;)
		# (as GenGenLib's load_state does: newbies see it)
		"You have not configured!  (no %q)\n"
		. "You should ./configure first. ;)"), $conf));
	my %D = read_make($conf, prog => $self->{prog});
	# F and R (the manifest and the rules) are external to the project:
	# paths from where we are, not from the project root.  The header does
	# not say them: a fork of either is the same build file.
	if ($arg{D}) {
		my $Doverrides = $arg{D};
		foreach (keys %$Doverrides) {
			$D{$_} = $Doverrides->{$_};
		}
	}
	for my $k (qw( A B a b c R F e )) {
		defined $D{$k} && length $D{$k}
			or die _status 0, tagmsg(E => diag(__(
				"%q: %q is missing.  Try reconfiguring."), $conf, $k));
	}
	File::Spec->file_name_is_absolute($D{b})
		and die _status 0, tagmsg(E => diag(__(
			# HEY!  %q is a variable of config.mk: `b' or `c', which are where
			# what we make goes (the target tree, and the cache)
			"%q prefix must be a relative path."), 'b'));
	# c, the cache (what we make but do not ship), is written by
	# configure even when it is b; we do not guess it.
	File::Spec->file_name_is_absolute($D{c})
		and die _status 0, tagmsg(E => diag(__(
			"%q prefix must be a relative path."), 'c'));
	grep { $_ eq '..' } split m!/!, $D{c}
		and die _status 0, tagmsg(E => diag(__(
			"%q prefix may not climb out of the build directory."), 'c'));
	$D{e} =~ m!/!
		and die _status 0, tagmsg(E => diag(__(
			"%q (directory marker) may not contain a slash."), 'e'));
	$self->{D} = \%D;
	# The build directory and the project root, as they really are
	# (and as characters, like every other name).  Each is said as
	# soon as it is not found, while $! still says why.
	$self->{Babs} = abs_path(_to_fs($self->{B}));
	defined $self->{Babs}
		or die tagmsg(E => diag(__("cannot find the build directory %q: %m"), $self->{B}));
	$self->{Rabs} = abs_path(_to_fs($self->_fs($D{A})));
	defined $self->{Rabs}
		or die tagmsg(E => diag(__("cannot find the source tree %q: %m"), $D{A}));
	$_ = _un_fs($_) for @$self{qw( Babs Rabs )};
	$self;
}

sub _warn
{
	my ($self, @mesg) = @_;
	$self->{quiet} or print STDERR @mesg;
}

# A WANT that cannot be had.  This is a wrapper
# for _warn that prints loudly and increments
# that sets failure status if -A (all; strict
# mode) is on.
sub _soft
{
	my ($self, @mesg) = @_;
	if ($self->{strict}) {
		$self->{failed} = 1;
		print STDERR @mesg;
	} else {
		$self->_warn(@mesg);
	}
}

# _soft, of the file `node': while a plan may yet start over, it is
# said once, at the end, in the order the files were done (see plan).
# `rank' 0 is what the file itself goes without, and 1 a goal that goes
# without the file (which comes after).
sub _held
{
	my ($self, $node, $rank, @mesg) = @_;
	$self->{hold} or return $self->_soft(@mesg);
	push @{ $self->{hold} }, [ $node, $rank, scalar @{ $self->{hold} }, \@mesg ];
}

=item B<failed>

True if the C<strict> build left out a C<WANT> (see L</new>), so that
whoever runs us should exit with a failure status; always false
otherwise.

=cut

sub failed { $_[0]{failed} ? 1 : 0; }

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

# The characters of a string literal, `"..."'.  (With no prog, what
# scan_string says has no prefix, and ends in a newline.)
sub _string
{
	my ($self, $lit, $where) = @_;
	my ($s) = eval { RdKw::WwW::GenGenLib::scan_string($lit, prog => undef) };
	defined $s or do {
		# Prefix what scan_string says with a blame line.
		(my $why = $@) =~ s/^/$where: /gm;
		die _status 0, tagmsg(E => $why);
	};
	$s;
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
		and die _status 0, tagmsg(E => diag(__(
			# HEY!  The first %s is where (a file, or `file' line 3), and
			# the second is b or c (a variable of config.mk, as in ${b}).
			# Leave the ${...}s alone: they are what is written in a header.
			'%1$s: %2$q: ${%3$s} is relative to ${B}; '
			. 'use ${B}/${%3$s}.'),
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
		} elsif ($spec =~ /\G\$\{($STR)\}/gc) {
			$out .= $self->_string($1, $where);
		} elsif ($spec =~ /\G\$\{([Uu]\+[^}]*)\}/gc) {
			my $u = $1;
			$u =~ /\A[Uu]\+([0-9A-Fa-f]{1,8})\z/ and hex($1) <= 0x10FFFF
				or die _status 0, tagmsg(E => diag(__(
					# HEY!  the last %s is what is in a header, as ${U+...}
					"%s: %q: %s is no code point"),
					$where, $spec, "\${$u}"));
			$out .= chr hex $1;
		} elsif ($spec =~ /\G\$(?:\{(\w+)\}|(\w))/gc) {
			my $x = defined $1 ? $1 : $2;
			defined $var{$x} or die _status 0, tagmsg(E => diag(__(
				# HEY!  the last %s is the variable, as ${name}
				"%s: %q: no such variable %s"),
				$where, $spec, "\${$x}"));
			$out .= $var{$x};
		} elsif ($spec =~ /\G\$/gc) {
			die _status 0, tagmsg(E => diag(__('%s: stray $ in %q'), $where, $spec));
		} else {
			last;
		}
	}
	length $out or die _status 0, tagmsg(E => diag(__("%s: empty path"), $where));
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
	$tree eq 'c' && defined $self->{D}{c}
		&& File::Spec->canonpath($self->{D}{c})
			ne File::Spec->canonpath($self->{D}{b})
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
			: index($path, "$dir/") == 0
			? substr($path, length($dir) + 1) : next;
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
	# Nothing to mangle for the shell?  Then leave it be.
	return $s if $s =~ m!\A[A-Za-z0-9_./:@%+=,-]+\z!;
	# Otherwise: single quotes, and ' itself as '\''
	$s =~ s!'!'\\''!g;
	"'$s'";
}

=item B<arg_max> I<opt> [, I<cap> ]

Not a method.  How many bytes of file names a backend puts on one
command line (an C<rm> of a cleaning rule), as C<-Sarg_max> in I<opt>
(the options of the generator) says:

=over

=item no C<-Sarg_max>, or C<-Sarg_max> with no value

16384: an eighth of 128 KiB, the least ARG_MAX we know of (Linux).

=item C<-Sarg_max=>I<bytes>

That many.  C<-Sarg_max=0> and C<-Sarg_max=> give 0: no limit, and so
one command for all of the files.

=item C<-Sarg_max=auto>

An eighth of C<sysconf(_SC_ARG_MAX)> on the machine that runs
C<siteconf -g>, and no more than I<cap> if that is given; 16384 if
C<sysconf> does not say.

=back

Any other value is an error.

=cut

my $ARG_MAX = 16384;

sub arg_max
{
	my ($opt, $cap) = @_;
	my $v = $opt ? $opt->{arg_max} : undef;
	defined $v or return $ARG_MAX;
	length $v or return 0;
	$v =~ /\A[0-9]+\z/ and return 0 + $v;
	$v eq 'auto'
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  %s is the option, as -Sarg_max=lots
			"%s: expected a number of bytes, or auto"), "-Sarg_max=$v"));
	require POSIX;
	my $n = eval { POSIX::sysconf(POSIX::_SC_ARG_MAX()) };
	$n = defined $n && $n > 0 ? int($n / 8) : $ARG_MAX;
	defined $cap && $n > $cap ? $cap : $n;
}

=item B<header_comment> I<plan>

Not a method.  The lines of a build file's header that say what made
it: C<prog> of the I<plan>, and then its C<args>, as comment lines.
They are ASCII, whatever the locale: an argument of printable ASCII is
as the shell would read it, and any other is quoted as Perl would
quote it (see L<RdKw::I18N::CodeSets/qq_ascii>), C<\n> and all.

=cut

sub header_comment
{
	my ($plan) = @_;
	my $say = sub { $_[0] =~ /\A[\x20-\x7e]*\z/ ? shell_quote($_[0]) : qq_ascii($_[0]) };
	my $args = join ' ', map { $say->($_) } @{ $plan->{args} || [] };
	my $prog = join ' ', map { $say->($_) } split / /, $plan->{prog};
	my $text = "# (generated by `$prog' :D)\n";
	$text .= "#\n# options: $args\n" if length $args;
	# (bytes, as the rest of the build file is)
	utf8::downgrade($text);
	$text;
}

=item B<fs_text> I<string> [, I<where> ]

Not a method.  I<string> as the file system spells it (bytes), or an
error.  It is an error, too, if a character that is not ASCII is
spelled with a byte that is: the file system encoding may spell
a character as a C<\> or a C<`> (Shift_JIS, GBK and Big5 do), and
a program that reads ASCII would take that byte for itself.  Only
letters, digits and C<_.+,@-> pass.  A byte of such a character cannot
be escaped, so nothing here tries.

=cut

# (what has been found safe, for each of the spellings: `filesys', `argv')
my %SAFE;
sub fs_text { _spell_text('filesys', @_) }

=item B<argv_text> I<string> [, I<where> ]

Like L</fs_text>, but as an argument is spelled (the encoding of
C<argv>, which is what a person types after C<make>): the names of
rules, which one asks of a build tool by name.

=cut

sub argv_text { _spell_text('argv', @_) }

sub _spell_text
{
	my ($cat, $s, $where) = @_;
	my $spell = sub { _to_fs_or_argv($cat, $_[0]) };
	my $bytes = $spell->($s);
	return $bytes unless $s =~ /[^\x00-\x7F]/;
	my %seen;
	for my $c (grep { !$seen{$_}++ } $s =~ /([^\x00-\x7F])/g) {
		next if $SAFE{$cat}{$c};
		my $b = $spell->($c);
		if ($b =~ /([\x00-\x2A\x2F\x3A-\x3F\x5B-\x5E\x60\x7B-\x7F])/) {
			require RdKw::I18N::CodeSets;
			my $enc = RdKw::I18N::CodeSets->locale->$cat;
			my $msg = diag(__(
				# HEY!  The first %s is where (as in the messages above), %s
				# the character (U+0041) and %s its spelling in bytes (0x5C).
				"%s: %s is encoded as %s in file system encoding%s,"
				. " which contains ASCII metacharacters"),
				defined $where ? $where : 'name', sprintf('U+%04X', ord $c),
				join(' ', map { sprintf '0x%02X', ord } split //, $b),
				defined $enc ? diag(' (%#q)', $enc) : "");
			die _status 0, tagmsg(E => $msg);
		}
		$SAFE{$cat}{$c} = 1;
	}
	$bytes;
}

sub _to_fs_or_argv
{
	my ($cat, $s) = @_;
	$cat eq 'argv' ? to_argv($s, { prog => 'E' }) : to_fs($s, { prog => 'E' });
}

=item B<recipe_bytes> I<runs>

Not a method.  The recipe I<runs> (see C<_subst>) as bytes, in make's
words: what the file system spells, with a C<word> quoted for the
shell last of all, so that no byte of it is read as anything but a
byte, and with a C<$> of what the shell reads doubled.  The text and an
unquoted variable are the author's: they say C<echo "表"> if they mean it.
(A name in them was checked, as the name of a file, when it was read.)

=cut

sub recipe_bytes
{
	my ($runs, %opt) = @_;
	my $out = '';
	for (@$runs) {
		my ($kind, $s, $where) = @$_;
		# A line break in a value is the end of the command to make (and
		# ninja), whatever quotes the shell would see around it: whether
		# that can be said at all is for the backend (`line_break').
		$kind ne 'text' && $s =~ /\n/ && $opt{line_break} and
			die _status 0, tagmsg(E => diag($opt{line_break}, $where, $s));
		if ($kind eq 'word') {
			$out .= _dollars(shell_quote(_to_fs($s)));
		} else {
			$out .= _to_fs($s);
		}
	}
	$out;
}

# `$' for make is $$; for what the shell reads, which make must not
sub _dollars { (my $s = $_[0]) =~ s/\$/\$\$/g; $s }

=item B<recipe_commands> I<bytes>

Not a method.  A recipe in make's words (what L</recipe_bytes>
returns) as the commands that make would run, for a backend that is
not make: a list of C<[ >I<ignore>C<, >I<command>C< ]>, one for each
line of the recipe that is not blank.  A backslash at the end of a
line joins the next line to it (the backslash and the newline go, as
the shell would take them, and so does the tab that begins the next
line, as make takes it).  The C<@>, C<-> and C<+> in front are gone;
I<ignore> is true if a C<-> said to ignore a failure.  A C<$$> is
as it is: it is the shell's C<$>.

=cut

sub recipe_commands
{
	my ($recipe) = @_;
	my @logical;
	my $joining;
	for my $line (split /\n/, $recipe) {
		# (make drops the tab of a continuation line too)
		$line =~ s/^\t//;
		if ($joining) { $logical[-1] .= $line } else { push @logical, $line }
		$joining = $logical[-1] =~ s/\\\z//;
	}

	my @cmd;
	for my $line (@logical) {
		next if $line =~ /\A[$SP]*\z/;
		my $ignore = 0;
		# @ is for make to not echo, - is to not mind
		while ($line =~ s/\A[$SP]*([-@+])[$SP]*//) {
			$ignore = 1 if $1 eq '-';
		}
		$line =~ s/[$SP]+\z//;
		push @cmd, [ $ignore, $line ];
	}
	@cmd;
}

# Names that cannot escape from the source or the output tree.  Only an
# empty name and a NUL are refused for every backend: the selected
# backend must escape or reject any other character.  A name is also
# refused if the file system spells a character of it with an ASCII
# byte that is special (fs_text).
sub _check_file
{
	my ($file, $where) = @_;
	length $file && $file !~ /\0/
		or die _status 0, tagmsg(E => diag(__(
			# HEY!  The first %s is always where (a file, or `file' line 3),
			# in this message and in those that follow it
			"%s: bad file name %q"), $where, $file));
	fs_text($file, $where);
	$file =~ m!\A/!
		and die _status 0, tagmsg(E => diag(__(
			"%s: file name %q must be relative"), $where, $file));
	grep { $_ eq '..' } split m!/!, $file
		and die _status 0, tagmsg(E => diag(__(
			"%s: file name %q is out of tree"), $where, $file));
	1;
}

=item B<read_manifest> I<file>

Returns the goals in I<file>, a list of C<{ name, need, want }>
hash references, where the latter two are lists of C<{ file, line }>.
You can also give a scalar reference instead of a file name.  It is
read by L<RdKw::WwW::GenGenLib/read_manifest> (so names are unescaped),
and then what we cannot have is an error: a reserved goal name, and a
file name we do not permit as a target (an absolute one, one with
C<..>, or an empty one, or one with a NUL).  The backend escapes any
other special character or rejects it; POSIX make rejects most of them.

=cut

# What a goal may be called (as in GenGenLib::Manifest), and so a rule
my $RULE_NAME = qr/\A(?!-)[^\s\p{Cc}\p{Cf}:#%\$\\]+\z/;

# What -Sclean (or -Spurge: `key') says the cleaning rules are called:
# a comma-separated list of names, in each of which `&' is the name of a
# goal (and then there is a rule for each), and `key' itself if it says no
# name.  Empty if there is no such option, and so no rule; a lone `&' (a
# rule that would be named like the goal itself) is how to say there are
# none.  A name is one a goal may have.
sub _clean_pattern
{
	my ($self, $key) = @_;
	my $S = $self->{S};
	$S && exists $S->{$key} or return ();
	my $c = $S->{$key};
	$c = $key unless defined $c && length $c;
	my @pat;
	for my $name (split /,/, $c, -1) {
		length $name
			or die _status 0, tagmsg(E => diag(__(
				# HEY!  %s is the option, as -Sclean=a,,b
				"%s: a name of a rule may not be empty"), "-S$key=$c"));
		$name =~ $RULE_NAME
			or die _status 0, tagmsg(E => diag(__(
				# HEY!  the second %s is the name, as in -Sclean=a:b
				"%s: %q cannot be the name of a rule"), "-S$key=$c", $name));
		push @pat, $name unless $name eq '&';
	}
	@pat;
}

# Whether `name' is a cleaning rule that is not for a goal
sub _is_clean
{
	my ($self, $name) = @_;
	scalar grep { !/&/ && $_ eq $name } map { $self->_clean_pattern($_) } qw( clean purge );
}

sub read_manifest
{
	my ($self, $file) = @_;
	# GenGenLib reads an INCLUDE from the current directory, as ${A};
	# so we go there for it, and come back.  (With no project, as when
	# a test makes us of nothing, there is nowhere to go.)
	my $root = $self->{Rabs};
	my %D = $self->{D} ? (%{ $self->{D} }, A => '.') : ();
	my $here;
	if (defined $root) {
		$here = _un_fs(getcwd());
		ref $file or File::Spec->file_name_is_absolute($file)
			or $file = File::Spec->abs2rel(File::Spec->rel2abs($file, $here), $root);
		chdir _to_fs($root)
			or die tagmsg(E => diag(__("cannot find the source tree %q: %m"), $root));
	}
	my $mf = eval { RdKw::WwW::GenGenLib::read_manifest(\%D, $file) };
	my $why = $@;
	defined $here and (chdir _to_fs($here)
		or die tagmsg(E => diag(__("cannot find the build directory %q: %m"), $here)));
	$mf or do {
		$why =~ s/\Aread_manifest: //;
		die "E: $why";
	};

	# (what it reads, it reads; what we cannot have, in the order it is said)
	my @goal = $mf->goals;
	my %goal;
	for my $goal (@goal) {
		my $name = $goal->{name};
		$reserved_goal{$name} || $self->_is_clean($name)
			and die _status 0, tagmsg(E => diag(__(
				"%s: %q is a reserved goal name"),
				_blame($goal->{input}, $goal->{line}), $name));
		$goal{$name} = $goal;
	}

	# A name that is the name of a goal is that goal: what it makes is
	# what the name stands for (a NEED has the NEEDs and WANTs of it as
	# they are, a WANT wants them all), and that is said wherever it
	# was, in the order it was said.  A goal that comes back to itself
	# is an error.
	my (%done, %busy);
	my $resolve; $resolve = sub {
		my ($goal, @path) = @_;
		return if $done{$goal->{name}};
		$busy{$goal->{name}} = 1;
		push @path, $goal->{name};
		my (@need, @want);
		for my $kind (qw( need want )) {
			for my $ent (@{ $goal->{$kind} }) {
				my $sub = $goal{$ent->{file}};
				unless ($sub) {
					push @{ $kind eq 'need' ? \@need : \@want }, $ent;
					next;
				}
				$busy{$sub->{name}} and die _status 0, tagmsg(E => diag(__(
					# HEY!  the second %s is a chain of
					# goals which ends in the beginning
					# node; e.g. `a -> b -> a'.
					"%s: cyclic goal: %s"),
					_blame($ent->{input}, $ent->{line}),
					join(' -> ', @path[ (grep { $path[$_] eq $sub->{name} } 0 .. $#path)[0] .. $#path ],
						$sub->{name})));
				$resolve->($sub, @path);
				# (what it stands for is JUST if the one that says it is.
				# `via' is the goal whose line it is, and `vmode' how
				# this goal takes that one: WANTed if any goal on the
				# way is a WANT)
				my $j = $ent->{just};
				my $copy = sub { +{ %$_, just => $_->{just} || $j ? 1 : 0,
					via => defined $_->{via} ? $_->{via} : $sub->{name},
					vmode => $kind eq 'want' ? 'WANT' : $_->{vmode} || 'NEED' } };
				my @sneed = map { $copy->() } @{ $sub->{need} };
				my @swant = map { $copy->() } @{ $sub->{want} };
				if ($kind eq 'need') {
					push @need, @sneed;
					push @want, @swant;
				} else {
					push @want, @sneed, @swant;
				}
			}
		}
		($goal->{need}, $goal->{want}) = (\@need, \@want);
		delete $busy{$goal->{name}};
		$done{$goal->{name}} = 1;
	};
	$resolve->($_) for @goal;

	for my $goal (@goal) {
		_check_file($_->{file}, _blame($_->{input}, $_->{line}))
			for sort { $a->{order} <=> $b->{order} }
				@{ $goal->{need} }, @{ $goal->{want} };
	}
	@goal;
}

# Makefile.in with the `${...}'s (and `$x's) in `line' replaced.  The
# modifiers (see RdKw::WwW::SiteConf::Modifiers) come after the name.
# `node' is the name of the target (relative to its tree), and `src'
# that of its source (relative to `a'); the latter is only known
# once all prerequisites have been read, so those may not say it.
# What a :Q made is for the shell.  If `runs' is given (a recipe), we
# push to it, and return nothing, what is said in runs of
#   [ text => $text, $where ]    in make's words
#   [ word => $value, $where ]   a value for the shell, to be quoted
#                                after it is spelled in bytes
# A :Q is only a mark: it must be the last modifier, in a recipe, and
# the backend quotes the word (see recipe_bytes).  Elsewhere it is an
# error, which says where (`noquote' is that, as in `a prerequisite').
# Without `runs' we return the line.
sub _subst
{
	my ($self, $line, $node, $where, $src, $runs) = @_;
	my $D = $self->{D};
	my $out = '';
	my $put = sub {
		my ($kind, $s) = @_;
		# (a word that is empty is still one: it is quoted to '')
		return unless length $s or $kind eq 'word';
		if (!$runs) { $out .= $s }
		elsif ($kind eq 'text' && @$runs && $runs->[-1][0] eq 'text'
			&& $runs->[-1][2] eq $where) { $runs->[-1][1] .= $s }
		else { push @$runs, [ $kind, $s, $where ] }
	};
	my $pos = 0;
	while ((my $i = index($line, '$', $pos)) >= 0) {
		$put->('text', substr($line, $pos, $i - $pos));
		my $end = eval { RdKw::WwW::SiteConf::Modifiers::_expr_end($line, $i) };
		defined $end or do {
			# a `$' at the very end, or before a newline, is a `$'
			if ($@) {   # (as Modifiers says it)
				(my $why = $@) =~ s/^/$where: /gm;
				die _status 0, tagmsg(E => $why);
			}
			$put->('text', '$');
			$pos = $i + 1;
			next;
		};
		if (substr($line, $i + 1, 1) eq "\n") {
			$put->('text', '$');
			$pos = $i + 1;
			next;
		}
		my $body = substr($line, $i + 1, $end - $i - 1);
		my ($x, $mods, $lit) = ($body, undef, undef);
		if ($body =~ s!\A\{(.*)\}\z!$1!s) {
			if ($body =~ /\A"/) {
				# a string literal, and maybe modifiers after it
				my $rest;
				($lit, $rest) = eval { RdKw::WwW::GenGenLib::scan_string($body, prog => undef) };
				defined $lit or do {
					(my $why = $@) =~ s/^/$where: /gm;
					die _status 0, tagmsg(E => $why);
				};
				$rest =~ /\A(?::(.*))?\z/s or die _status 0, tagmsg(E => diag(__(
					# HEY!  the second %s is a string literal, as ${"..."}
					"%s: junk after the string in %s"), $where, "\${$body}"));
				$mods = $1;
				$x = '';
			} else {
				($x, $mods) = ($body =~ /\A([^:]*)(?::(.*))?\z/s);
			}
		}
		# `${A}/x' with an A of `.' would leave `./x' behind, so
		# it takes its slash with it.
		my $slash = substr($line, $end, 1) eq '/' ? '/' : '';
		$pos = $end + length $slash;
		my $val;
		if (defined $lit) {
			$val = $lit;
		} elsif ($x eq '$') {
			$val = '$';
		} elsif ($x =~ /\A[Uu]\+/) {
			# a character, as in a header (see _expand)
			$x =~ /\A[Uu]\+([0-9A-Fa-f]{1,8})\z/
				and hex($1) <= 0x10FFFF
				or die _status 0, tagmsg(E => diag(__(
					# HEY!  the second %s is what is in Makefile.in, as ${U+...}
					"%s: %s is not a valid Unicode code point"),
					$where, "\${$x}"));
			$val = chr hex $1;
		} elsif ($x eq '@' or $x eq '.TARGET') {
			defined $node or die _status 0, tagmsg(E => diag(__(
				# HEY!  the second %s is a variable, as ${@} (or ${.TARGET}),
				# in this message and in those that follow it
				"%s: %s outside of a recipe"),
				$where, "\${$x}"));
			$val = $node;
		} elsif ($x eq '<' or $x eq '.IMPSRC') {
			defined $src or die _status 0, tagmsg(E => diag(__(
				"%s: misplaced %s (not in a recipe)"),
				$where, "\${$x}"));
			length $src or die _status 0, tagmsg(E => diag(__(
				"%s: undefined %s"
				. ' (explicitly suppressed by ${a})'),
				$where, "\${$x}"));
			$val = $src;
		} elsif ($x eq '^X' or $x eq "\030") {
			$val = _un_fs($^X);
		} else {
			defined $D->{$x} or die _status 0, tagmsg(E => diag(__("%s: undefined variable: %s"),
				$where, "\${$x}"));
			$val = $D->{$x};
		}
		my $word;
		if (defined $mods) {
			$val = eval {
				RdKw::WwW::SiteConf::Modifiers::_apply($val, $mods,
					quote => sub {
						my ($v, $last) = @_;
						$runs or die diag(__(
							# HEY!  the second %s is where, as `a prerequisite'
							":Q (shell quote) is not valid in %s"),
							defined $self->{noquote} ? $self->{noquote} : __("a name")) . "\n";
						$last or die __(":Q (shell quote) must be the last modifier") . "\n";
						# the backend's, by bytes
						return $word = $v;
					},
					expand => sub {
						local $self->{noquote} = __("a nested expansion");
						$self->_subst($_[0], $node, $where, $src);
					}
				);
			};
			defined $val or die _status 0, ($@ =~ /\AE: /) ? $@ : "E: $where: $@";
		}
		if ($val eq '.' && length $slash) {
			# `./' is no use to anyone
			($val, $slash) = ('', '');
			undef $word;
		}
		$put->(defined $word ? 'word' : 'text', $val);
		$put->('text', $slash);
	}
	$put->('text', substr($line, $pos));
	$out;
}

# A prerequisite (or a source), as it is written in Makefile.in, expanded.
# It is one name: words are told apart where they are written (see
# _raw_words), never by what a variable holds, so `evil path' in ${x} is
# one file, and a name that is empty is not a file at all.
sub _subst_name
{
	my ($self, $word, $node, $where) = @_;
	local $self->{noquote} = __("a prerequisite");
	my $name = $self->_subst($word, $node, $where);
	length $name or die _status 0, tagmsg(E => diag(__(
		# HEY!  The first %s is where, the second what is in Makefile.in
		"%s: %q expands to nothing"), $where, $word));
	$name;
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
	# Characters, as ${U+...}, ${"..."}, ${$} and $$ (in one pass, so
	# that what they say is not read again), and what Makefile.in
	# assigned (not what is configured: ${a} is not for a name in ${b}).
	# Any other ${...} or $ is a tree we do not know.
	my $assigned = $self->{assigned} || {};
	my $unknown;
	$rest =~ s/(\$\{(?:[Uu]\+[^}]*|$STR)\})|(\$\{\$\}|\$\$)|\$\{(\w+)\}|\$/
		defined $1 ? $self->_subst($1, undef, $where)
		: defined $2 ? '$'
		: defined $3 && $assigned->{$3} ? $self->{D}{$3}
		: do { $unknown = 1; $& }
	/ge;
	$unknown and die _status 0, tagmsg(E => diag(__(
		'%s: %q: target is not preceded by'
		. ' a legal prefix (${b} or ${c})'),
		$where, $rest));
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

# `name = value' in Makefile.in: its lines after the first, which begin
# with a tab (and are the rest of the value, one line each), and a
# comment line or a blank one in between, are read here.  The value is
# what the first line says after a `#' (that follows a blank) and the
# blanks around it are cut off, then the lines, each as it is but for
# the tab in front and the blanks behind it, joined by a line break.
# It is expanded now, so a variable of it is what it is now.  It cannot
# be quoted (that is for the shell of a recipe), and what is defined
# already cannot be again.  The lines are `get'; `pending' (and its
# number) is where one read too far is put back, `lineno' the number
# of the one last read.
sub _assign
{
	my ($self, $name, $first, $get, $pending, $pending_no, $lineno, $where) = @_;
	exists $self->{D}{$name} and die _status 0, tagmsg(E => diag(__(
		# HEY!  the second %s is a variable, as ${name}
		"%s: %s is already defined"), $where, "\${$name}"));
	$first =~ s/\r?\n\z//;
	$first =~ s/(?:\A|[$SP])#.*//s;
	$first =~ s/\A[$SP]+|[$SP]+\z//g;
	my @part = length $first ? ($first) : ();
	while (defined(my $next = $get->())) {
		if ($next =~ /\A\t(.*)\z/s) {
			(my $t = $1) =~ s/[$SP]+\z//;
			push @part, $t;
			next;
		}
		next if $next =~ /\A[$SP]*#(?:[$SP]|\z)/o or $next =~ /\A[$SP]*\z/o;
		# (the line we are on, that we got last, is its number)
		($$pending, $$pending_no) = ($next, $$lineno);
		last;
	}
	local $self->{noquote} = __("a variable assignment");
	my $val = $self->_subst(join("\n", @part), undef, $where);
	$self->{D} = { %{ $self->{D} }, $name => $val };
	$self->{assigned}{$name} = 1;
}

# The paths of an INCLUDE or AUGMENT line: from the project root, as
# in a header, so that we can open them from here.
sub _include_paths
{
	my ($self, $args, $where) = @_;
	local $self->{D} = { %{ $self->{D} }, A => '.' };
	local $self->{noquote} = __("an include path");
	map {
		my $path = $self->_subst($_, undef, $where);
		length $path && $path !~ /\0/ or die _status 0, tagmsg(E => diag(__(
			"%s: bad include path %q"), $where, $_));
		File::Spec->rel2abs($path, $self->{Rabs});
	} _raw_words($args);
}

# Makefile.in => { target => { recipe, deps, src, line, at } }
#
# The first prerequisite of a rule, if it is in ${a} (see _source_of),
# is its source, and then (as `src', named from ${a}) it takes the
# place of the one we would otherwise suppose: ${a}/${@}.
sub _read_rules
{
	my ($self) = @_;
	# (an assignment adds to what we see, here and nowhere else)
	local $self->{D} = $self->{D};
	local $self->{assigned} = {};
	# What every file read so far says: the rules, the files that are
	# open (for an INCLUDE that comes back to one), the targets of the
	# rule above (`node', which a recipe line is for), the stanza that
	# is theirs (each rule line begins one), and what AUGMENT added to.
	local $self->{reading} = { rule => {}, open => {}, node => [],
		stanza => 0, stanzas => 0, augmented => [] };
	my $st = $self->{reading};
	$self->_read_rule_file(File::Spec->canonpath($self->{D}{R}));
	for my $entry (@{ $st->{augmented} }) {
		my ($rule, $where) = @$entry;
		$rule->{at} or die _status 0, tagmsg(E => diag(__(
			"%s: AUGMENT target %q has no rule"), $where, $rule->{name}));
	}
	my $rules = $st->{rule};
	for my $rule (values %$rules) {
		my $src = defined $rule->{src} ? $rule->{src} : $rule->{name};
		# The recipe is runs (see _subst) in make's words: a `$' from $$
		# or a variable is make's, but one in what a :Q made is the shell's
		# (the backend writes it $$).  Quoting is by bytes, so it is theirs.
		for (@{ $rule->{raw} }) {
			# (as the variables were when the line was read)
			local $self->{D} = $_->[2];
			$self->_subst($_->[0], $rule->{name}, $_->[1], $src, $rule->{recipe});
		}
		delete $rule->{raw};
	}
	$rules;
}

sub _augment_error
{
	die _status 0, tagmsg(E => diag(__(
		"%s: AUGMENT may only amend dependencies"), $_[0]));
}

# One file of rules, `file'; `at' is where the INCLUDE (or AUGMENT)
# that names it is, and `augment' is true for an AUGMENT.
sub _read_rule_file
{
	my ($self, $file, $at, $augment) = @_;
	my $st = $self->{reading};
	local $_;
	my $path = _to_fs($file);
	open my $fh, '<:encoding(UTF-8)', $path or die tagmsg(E => defined $at
		? diag(__("%s: cannot open file %q: %m"), $at, $file)
		: diag(__("cannot open file %q: %m"), $file));
	# (a file is the same file whatever path names it)
	my $key = abs_path($path);
	defined $key or $key = $path;
	$st->{open}{$key} and die _status 0, tagmsg(E => diag(__(
		"%s: include cycle through %q"), $at, $file));
	local $st->{open}{$key} = 1;

	# A line of the file; one that was read too far is given back
	my ($lineno, $pending, $pending_no) = (0);
	my $get = sub {
		if (defined $pending) {
			$lineno = $pending_no;
			my $l = $pending;
			undef $pending;
			return $l;
		}
		my $l = <$fh>;
		$lineno++ if defined $l;
		$l;
	};

	while (defined($_ = $get->())) {
		next if /\A[$SP]*#(?:[$SP]|\z)/o or /\A[$SP]*\z/o;
		my $line = $lineno;
		my $where = _blame($file, $line);
		# Fold rule headers before deciding whether an indented line
		# is a recipe.  Recipe backslashes belong to make/the shell.
		unless (/^\t/) {
			while (/(?<!\\)(?:\\\\)*\\\r?\n\z/) {
				s/[ \t]*\\\r?\n\z/ /;
				my $next = $get->();
				# a comment line does not end the header (nor is it in it)
				$next = $get->() while defined $next and
					$next =~ /\A[$SP]*#(?:[$SP]|\z)/o;
				defined $next or die _status 0, tagmsg(E => diag(__(
					"%s: unfinished line continuation"), $where));
				$next =~ s/^[ \t]+//;
				$_ .= $next;
			}
		}
		if (/^\t/) {
			$augment and _augment_error($where);
			@{ $st->{node} } or die _status 0, tagmsg(E => diag(__(
				# HEY!  a recipe line (one that begins with a tab)
				# with no rule above it to be the recipe of
				"%s: unexpected tabulation"), $where));
			$self->_recipe_line($_, $where);
			next;
		}
		if (/\A(\w+)[ \t]*=(.*)\z/s) {
			$augment and _augment_error($where);
			$st->{node} = [];
			$self->_assign($1, $2, $get, \$pending, \$pending_no, \$lineno, $where);
			next;
		}
		if (/\A[ ]*(INCLUDE|AUGMENT)(?:[$SP]+|\z)(.*)\z/so) {
			my ($directive, $args) = ($1, $2);
			$augment and _augment_error($where);
			$args =~ s/(?:\A|[$SP])#.*//so;
			my @paths = $self->_include_paths($args, $where);
			@paths or die _status 0, tagmsg(E => diag(__(
				# HEY!  the second %s is the keyword: INCLUDE or AUGMENT
				"%s: %s takes at least one file"), $where, $directive));
			$self->_read_rule_file($_, $where, $directive eq 'AUGMENT') for @paths;
			# (a recipe line here is not for the last rule of that file)
			$st->{node} = [];
			next;
		}
		if (/\A$TARGETS:/o) {
			$self->_rule_line($_, $where, $line, $augment);
			next;
		}
		$augment and _augment_error($where);
		(my $text = $_) =~ s/\r?\n\z//;
		die _status 0, tagmsg(E => diag(__("%s: invalid line: %q"), $where, $text));
	}
	close $fh or die tagmsg(E => diag(__("cannot read file %q: %m"), $file));
}

# A line of the recipe of the rule above (or of the rule on this line)
sub _recipe_line
{
	my ($self, $text, $where) = @_;
	my $st = $self->{reading};
	for my $node (@{ $st->{node} }) {
		my $rule = $st->{rule}{$node->[0]};
		if (defined $rule->{stanza} && $rule->{stanza} != $st->{stanza}) {
			die _status 0, tagmsg(E => diag(__(
				"%s: more than one recipe for %q"),
				$where, $node->[0]));
		}
		$rule->{stanza} = $st->{stanza};
		# (not yet: ${<} may be said further down)
		push @{ $rule->{raw} }, [ $text, $where, $self->{D} ];
	}
}

# `targets: prerequisites', maybe with `; recipe' after it.  In a file
# that AUGMENT reads, only the prerequisites are added (no recipe, nor
# source), and the line begins no stanza.
sub _rule_line
{
	my ($self, $text, $where, $line, $augment) = @_;
	my $st = $self->{reading};
	my ($src, $dep) = ($text =~ /\A($TARGETS):(.*)\z/so);
	# After a `;' is the first line of the recipe, and a tab
	# line after this one is the next
	my $cmd;
	$dep =~ /\A($PREREQ);[ \t]*(.*)\z/so
		and ($dep, $cmd) = ($1, "\t$2");
	$augment && defined $cmd and _augment_error($where);
	my @targets = map { [ $self->_read_target($_, $where) ] } _words($src)
		or die _status 0, tagmsg(E => diag(__("%s: null target list"), $where));
	unless ($augment) {
		$st->{node} = \@targets;
		$st->{stanza} = ++$st->{stanzas};
	}
	for my $node (@targets) {
		my ($key, $name) = @$node;
		my $rule = ($st->{rule}{$key} ||= { recipe => [], raw => [], deps => [],
			want => [], name => $name });
		if ($augment) {
			push @{ $st->{augmented} }, [ $rule, $where ];
		} else {
			$rule->{at} ||= $where;
			$rule->{line} ||= $line;
		}
		my $dep = $dep;
		if (!$augment && !$rule->{decided} && $dep =~ /[^$SP]/o) {
			$rule->{decided} = 1;
			# the first word (a ${...} may hold spaces, in :S/ /_/)
			my ($first) = ($dep =~ /\A[$SP]*($WORD)/o);
			if (defined $first and defined(my $from = _source_of($first))) {
				# ${a} alone says there is none (and ${<} is not known)
				my $name_of = length $from
					? $self->_subst_name($from, $name, $where) : '';
				length $from and _check_file($name_of, $where);
				$rule->{src} = $name_of;
				$rule->{source_at} = $where;
				$dep =~ s/\A[$SP]*\Q$first\E//;
			}
		}
		# NEED:x (or just x) is a prerequisite, and WANT:x
		# one that can be done without: said as it is written,
		# before anything is expanded, and of each word it
		# expands to.  Nothing else may come before a colon.
		for my $word (_raw_words($dep)) {
			my ($kind, $just) = ('deps', 0);
			if ($word =~ s/\A([^$SP\$\/:]*)://o) {
				my $pre = $1;
				my $how = $PREFIX{$pre}
					or die _status 0, tagmsg(E => diag(__(
						"%s: %q: a prerequisite must start with NEED:, WANT:,"
						. " JUST: (or JUST-NEED:) or JUST-WANT:, not %q"),
						$where, "$pre:$word", "$pre:"));
				($kind, $just) = @$how;
				# HEY!  %q is `NEED:' or `WANT:', literally.
				length $word or die _status 0, tagmsg(E => diag(__("%s: %q something?"),
					$where, "$pre:"));
			}
			# A prerequisite is a path from the project root, as in a
			# header, where ${A} is `.'.  The graph keeps it as the
			# build dir sees it.
			my $dep = do {
				local $self->{D} = { %{ $self->{D} }, A => '.' };
				$self->_subst_name($word, $name, $where);
			};
			my $built = $self->_to_build($dep);
			push @{ $rule->{$kind} }, $built;
			$rule->{dependency_at}{$kind}{$built} ||= $where;
			# (JUST only if every word that says it is)
			$rule->{ $just ? 'j' : 'nj' }{$built} = 1;
		}
	}
	$self->_recipe_line($cmd, $where) if defined $cmd;
}

# A node of the graph: what it takes to make one file in `b' from one
# in `a'.  `ok' says whether that can be done at all, and `why' not
# if it cannot.  A dependency on something in `b' is an edge to
# the node for that, which is how we know to make it (and to make it
# first); `kids' are those.
sub _node
{
	my ($self, $file, $just) = @_;
	$just = $just && !$self->{full}{$file} ? 1 : 0;
	my $D = $self->{D};
	if (my $node = $self->{node}{$file}) {
		if ($node->{visiting}) {
			my @stack = @{ $self->{stack} };
			shift @stack while @stack && $stack[0] ne $file;
			# HEY!  %s is the files, as `a' -> `b' -> `a'
			die _status 0, tagmsg(E => diag(__("dependency cycle: %s"),
				join(' -> ', map { diag('%q', $_) } @stack, $file)));
		}
		# A node made without its source's header cannot take what the
		# header says after the fact (what depends on it was checked
		# against it, and is ordered by it).  So a plain mention of a
		# file that was met as a JUST starts the plan over, with the
		# file read in full from the start.  The other way round is
		# nothing: a node that was read in full is JUST enough.
		if ($node->{just} && !$just) {
			$self->{full}{$file} = 1;
			die bless { file => $file }, 'RdKw::WwW::SiteConf::ABORT';
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
		and die _status 0, tagmsg(E => diag(__(
			"%q: %q is reserved for directory markers. "
			. "(Set -De to change it.)"),
			$file, $D->{e}));

	my $node = $self->{node}{$file} = {
		file => $file,
		apath => $apath,
		nosrc => $nosrc,
		bpath => $bpath,
		deps => [],
		kids => [],
		recipe => [],
		ok => 1,
		why => [],
		just => $just,
		visiting => 1,
	};
	push @{ $self->{stack} }, $file;
	my $fail = sub { $node->{ok} = 0; push @{ $node->{why} }, @_; };
	my $done = sub { $node->{seq} = ++$self->{seq}; delete $node->{visiting}; pop @{ $self->{stack} }; $node };

	unless ($rule) {
		$fail->(diag(__("no rule to make it\n (%q)."), $D->{R}));
		return $done->();
	}
	unless ($nosrc or -f _to_fs($self->_fs($apath))) {
		$fail->($rule->{at}
			# HEY!  the %s is where the rule is (e.g. `file' line 3)
			? diag(__("source %q is missing\n (rule at %s)."), $apath, $rule->{source_at} || $rule->{at})
			: diag(__("source %q is missing."), $apath));
		return $done->();
	}
	$node->{recipe} = $rule->{recipe};

	my %L;
	my %I = $nosrc || $just ? () : read_deps($self->_fs($apath), lines => \%L);
	if (defined $I{HAVE}) {
		# The source's own name, as a header spells it, is the one
		# the rule says it is: ${A}/${a}/FILE.
		my $where = diag('%#q: HAVE', $apath);
		my $have = $self->_expand($I{HAVE}, $where);
		my $want = File::Spec->canonpath("$D->{a}/$src");
		$have eq $want or die _status 0, tagmsg(E => $have ne $I{HAVE}
			# HEY!  Keep the question mark: we are as puzzled as
			# anyone.  The (aka %q) is what the HAVE says, expanded
			? diag(__("%#q: You HAVE %q (aka %q),\nbut I need %q?"),
				$apath, $I{HAVE}, $have, $want)
			: diag(__("%#q: You HAVE %q,\nbut I need %q?"), $apath, $I{HAVE}, $want));
	}

	# What the headers say they need, and what the rules do
	# (with no source, there is no header: %I is empty)
	my @hneed = $self->_entries(\%I, \%L, 'NEED', $apath);
	my @hwant = $self->_entries(\%I, \%L, 'WANT', $apath);
	my $just_dep = sub { $rule->{j}{$_[0]} && !$rule->{nj}{$_[0]} ? 1 : 0 };
	my $at = $rule->{dependency_at};
	my @rdep = map { [ $_, $_, diag(__("prerequisite in %s"), $at->{deps}{$_}), $just_dep->($_) ] }
		@{ $rule->{deps} };
	my @rwant = map { [ $_, $_, diag(__("WANT: in %s"), $at->{want}{$_}), $just_dep->($_) ] }
		@{ $rule->{want} };
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
				# (a JUST- is a name: its header is nothing to us, and it
				# does not count as having been followed)
				$d->[3] and next;
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
		# (it is a JUST- only if every way it is said is)
		my (%said, %plain);
		$_->[3] or $plain{$_->[1]} = 1 for @hneed, @hwant;
		@hneed = grep { !$said{$_->[1]}++ } @hneed;
		@hwant = grep { !$said{$_->[1]}++ } @hwant;
		$_->[3] = $plain{$_->[1]} ? 0 : 1 for @hneed, @hwant;
	}
	# What the rule's own prerequisites (the tools) say they need, if
	# they say anything at all
	for my $dep (@{ $rule->{deps} }) {
		$just_dep->($dep) and next;
		my ($need, $want) = $self->_tool($dep, $file, $at->{deps}{$dep});
		push @hneed, @$need;
		push @hwant, @$want;
	}
	# (and what a tool we can do without needs, we can do without too)
	for my $dep (@{ $rule->{want} || [] }) {
		$just_dep->($dep) and next;
		my ($need, $want) = $self->_tool($dep, $file, $at->{want}{$dep});
		push @hwant, @$need, @$want;
	}

	my @deps = $nosrc ? () : ($apath);
	my %tree = map { File::Spec->canonpath($D->{$_}) => 1 } qw( b c );
	my $check = sub {
		my ($said, $dep, $from, $just, $soft) = @_;
		return 1 if $tree{$dep};
		if (defined(my $made = $self->_target($dep))) {
			my $kid = $self->_node($made, $just);
			unless ($kid->{ok}) {
				return 0 if $soft;
				# (a cause per line, each cause deeper than what it breaks)
				# HEY!  %s is where it was needed (in header of `file').
				# The same goes for the next two marked strings.
				$fail->(diag(__("NEEDs %q\n (%s),\n  but cannot be made:"), $dep, $from),
					map { (my $l = $_) =~ s/^/  /mg; $l } @{ $kid->{why} });
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
				? diag(__("NEEDs %q\n (%s),\n  which we don't seem to have (is it %q?)"),
					$dep, $from, "\${B}/$said")
				: diag(__("NEEDs %q\n (%s),\n  which we don't seem to have."), $dep, $from));
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
			# HEY!  The %s, in parentheses, is where it
			# was wanted (in header of `file').  The face
			# is yours to keep; i added it because "W"
			# felt like a weak indication of a soft dep
			# failing....
			$self->_held($node, 0, tagmsg(W => diag(__("target %q WANTs %q\n"
				. " (%s),\n"
				. "  but it is missing; going on without it. :("),
				$file, $d->[1], $d->[2])));
		}
	}

	my %iHaz;
	$node->{deps} = [ grep { !$iHaz{$_}++ } @deps ];
	$done->();
}

# What the header of `file' (read_deps' `I', and the `lines' of it,
# `L') says of a kind, `NEED' or `WANT', as [ said, dep, from, just ]:
# the names of it and of its JUST- (said last).  `from' is where, with
# the line it is on.
sub _entries
{
	my ($self, $I, $L, $kind, $file) = @_;
	map {
		my ($key, $just) = @$_;
		my @name = @{ $I->{$key} || [] };
		my @line = @{ $L->{$key} || [] };
		map {
			my $at = _blame($file, $line[$_]);
			[ $name[$_], $self->_dep($name[$_], $at),
				# HEY!  This is where a NEED (or a WANT) was said, and is
				# said in parentheses after what is needed: %q is the file,
				# and %d the line in it
				diag(__("in header of %q line %d"), $file, $line[$_]), $just ];
		} 0 .. $#name;
	} [ $kind, 0 ], [ "JUST-$kind", 1 ];
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
		my %L;
		my %I = !defined $self->_target($dep) && -f _to_fs($fs) && -T _
			? read_deps($fs, lines => \%L) : ();
		[
			[ $self->_entries(\%I, \%L, 'NEED', $dep) ],
			[ $self->_entries(\%I, \%L, 'WANT', $dep) ],
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
	my ($self, $dep, $file, $at) = @_;
	my $tool = $self->{tool}{$dep} ||= do {
		my $fs = $self->_fs($dep);
		my %L;
		my %I = !defined $self->_target($dep) && -f _to_fs($fs) && -T _
			? read_deps($fs, lines => \%L) : ();
		if (defined $I{HAVE}) {
			my $have = $self->_dep($I{HAVE}, diag('%#q: HAVE', $dep));
			$self->_same($have, $dep)
				or die _status 0, tagmsg(E => $have ne $I{HAVE}
					# HEY!  As above, for a tool of the rule; the last %s
					# is where the rule is (`file' line 3)
					? diag(__("%#q: You HAVE %q (aka %q),\n"
						. "but I need %q for the rule for %q (%s)?"),
						$dep, $I{HAVE}, $have, $dep, $file, $at)
					: diag(__("%#q: You HAVE %q,\n"
						. "but I need %q for the rule for %q (%s)?"),
						$dep, $I{HAVE}, $dep, $file, $at));
		}
		{
			need => [ $self->_entries(\%I, \%L, 'NEED', $dep) ],
			want => [ $self->_entries(\%I, \%L, 'WANT', $dep) ],
		};
	};
	($tool->{need}, $tool->{want});
}

=item B<plan>

Reads everything, resolves what is C<WANT>ed, and returns the build
as a hash reference.  Dies, listing every one of them, if anything
that is C<NEED>ed cannot be had.

  goals   [ { name, default, select, files => [ FILE ... ], dropped => [ [FILE, WHY] ] } ]
            (how -t says it: default, if it is the default goal, as `,goal',
            `,' or `WANT:'; select, if it is a goal of its own, as `goal'
            or `WANT:goal'.  The default goal, if any, is the first.)
  node    { FILE => { file, apath, nosrc, bpath, deps,
                      recipe => [ [ KIND, TEXT, WHERE ] ... ] } }
  order   [ FILE ... ]    all files, in order of appearance
  dirs    [ { dir, marker, deps => [ MARKER ] } ]   parents first
  clean   [ { name, files => [ BPATH ] } ]   (if S says clean, else [])
  opt     the options of the generator (S), as far as it knows them (generate)
  D       the definitions, as in MY/config.mk

=cut

sub plan
{
	my ($self) = @_;
	my $D = $self->{D};
	$self->{rules} = $self->_read_rules;

	my @spec = $self->read_manifest(File::Spec->canonpath($D->{F}));
	@spec = $self->_select_goals(@spec);

	# The graph is made once, unless it finds out that a file it took
	# for a JUST is a NEED or WANT elsewhere: then once more, with that
	# file read in full (see _node).  Each time round has one more.
	my ($goal, $err, $order);
	$self->{full} = {};
	local $self->{hold};
	while (1) {
		$self->{node} = {};
		$self->{stack} = [];
		$self->{tool} = {};
		$self->{hold} = [];
		$self->{seq} = 0;
		($goal, $err, $order) = eval { $self->_goals(@spec) };
		if (my $abort = $@) {
			ref $abort && $abort->isa('RdKw::WwW::SiteConf::ABORT') or die $abort;
			next;
		}
		last;
	}
	# (the warnings of the last time round, now that it is the last; in
	# the order of the files they are of, as the errors are)
	my $held = delete $self->{hold};
	$self->_soft(@{ $_->[3] }) for sort {
		$a->[0]{seq} <=> $b->[0]{seq} || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2]
	} @$held;
	return $self->_finish($goal, $err, $order);
}

# The goals, as plan says: [ goals ], [ errors ], [ files in order ]
sub _goals
{
	my ($self, @spec) = @_;
	my $D = $self->{D};
	my (@goal, @err, @order, %known);
	# A file comes after what it takes to make it
	my $add; $add = sub {
		my ($file) = @_;
		return if $known{$file}++;
		$add->($_) for @{ $self->{node}{$file}{kids} };
		push @order, $file;
	};
	for my $spec (@spec) {
		my (@files, %iHaz, @dropped, %just);
		for my $kind (qw( need want )) {
			for my $ent (@{ $spec->{$kind} }) {
				my $file = $ent->{file};
				my $node = $self->_node($file, $ent->{just});
				# (the first that says it is the one: the NEEDs come first)
				next if $iHaz{$file}++;
				if ($node->{ok}) {
					$just{$file} = 1 if $ent->{just};
					push @files, $file;
					$add->($file);
					next;
				}
				# (one line for the manifest, which has one; else a line each)
				my $why = join ' ', map { (my $l = $_) =~ s/\A\s+//; $l } map { split /\n/ } @{ $node->{why} };
				my $causes = sub { my $p = shift; join '', map { (my $l = $_) =~ s/^/  /mg; tagmsg($p => $l) } @{ $node->{why} } };
				my $at = _blame($ent->{input}, $ent->{line});
				# HEY!  These three are where a goal says what it NEEDs (or
				# WANTs), in parentheses after it: %s is `file' line 3, and
				# %q the goal that has that line (which this goal includes)
				my $where = !defined $ent->{via} ? diag(__("in %s"), $at)
					: $ent->{vmode} eq 'WANT' ? diag(__("in %s, via WANTed goal %q"), $at, $ent->{via})
					: diag(__("in %s, via NEEDed goal %q"), $at, $ent->{via});
				if ($kind eq 'need') {
					push @err, [ $node->{seq}, scalar @err, tagmsg(E => diag(__(
						# HEY!  the %s is where (as above); what
						# follows the colon is why, a line each
						"goal %q NEEDs %q\n (%s),\n  but cannot be made:"),
						$spec->{name}, $file, $where)) . $causes->('E') ];
				} else {
					push @dropped, [ $file, $why, $ent->{just} ? 1 : 0 ];
					$self->_held($node, 1, tagmsg(W => diag(__(
						"goal %q WANTs %q\n (%s),\n  but cannot be made:"),
						$spec->{name}, $file, $where)), $causes->('W'));
				}
			}
		}
		push @goal, { name => $spec->{name}, select => $spec->{select}, default => $spec->{default},
			files => \@files, dropped => \@dropped, just => \%just };
	}
	# (what cannot be had comes before what it breaks: a file is done
	# after what it takes to make it, so in the order they were done)
	@err = map { $_->[2] } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @err;
	(\@goal, \@err, \@order);
}

# What is left of a plan once its graph is made
sub _finish
{
	my ($self, $goal, $err, $order) = @_;
	my $D = $self->{D};
	my @goal = @$goal;
	my @err = @$err;
	my @order = @$order;
	if (@err) {
		my $count = @err;
		# Weirdly enough, the same message is used even
		# if the user selected the ninja generator....
		# but eh, I guess we will roll with it. :v
		die _status 0, @err, tagmsg(E => diag(__n(
			# HEY!  "no soup for you!" (Seinfeld) but with Makefile
			# (not my bit, Claude came up with this... but cool
			# nonetheless o_o)
			"%d problem; no Makefile for you.",
			"%d problems; no Makefile for you.",
			$count), $count)
		);
	}

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

	# A rule (of a goal that we make, or to clean) is not a file.  (A
	# directory is not one of those: nothing in the Makefile is made
	# by that name, only by the name of its marker, and a rule called
	# `site' is the usual name of the goal for the directory `site'.)
	{
		my %rule = map { $_->{name} => 1 } @goal, @clean;
		my %rule_arg;
		for (keys %rule) {
			my $b = eval { to_argv($_, { prog => 'E' }) };
			$rule_arg{$b} = $_ if defined $b;
		}
		for my $file (map({ $_->{bpath} } @{ $self->{node} }{@order}),
				map { $_->{marker} } @dir) {
			my $b = eval { _to_fs($file) };
			my $clash = $rule{$file} ? $file : defined $b ? $rule_arg{$b} : undef;
			defined $clash and die _status 0, tagmsg(E => diag(__(
				# HEY!  the first %s is a name that is of a goal (or a
				# cleaning rule), and the second the file (it may be spelled
				# in other bytes: the file system and the arguments can differ)
				"%q is the name of a rule, and a file (%q) is as well"),
				$clash, $file));
		}
	}

	+{
		goals => \@goal,
		node => { map { $_ => $self->{node}{$_} } @order },
		order => \@order,
		dirs => \@dir,
		clean => \@clean,
		D => $D,
	};
}

# Select goals before resolving any files.  WANT changes only the roots:
# a file still needs all of its prerequisites, or is dropped as a whole.
sub _select_goals
{
	my ($self, @spec) = @_;
	# Each -t is fields, split by commas; a field of white space alone (or
	# of nothing) opts into the default goal, and the first that does is
	# it: what the next field names, if that is a name and no more (-t
	# ,goal), or else the first of the manifest (-t , and -t ', x').  Any
	# other field is names, split by white space, each a goal of its own.
	# A -t of nothing (or white space alone) is no fields at all, and so
	# no goal.  If no -t selects one, it is as -t , (with no -t said).
	my ($default, @own);
	for my $arg (@{ $self->{goals} || [] }) {
		next if $arg =~ /\A[$SP]*\z/;
		my @field = split /,/, $arg, -1;
		for (my $i = 0; $i < @field; $i++) {
			if ($field[$i] =~ /\A[$SP]*\z/) {
				next if $default;
				my $next = $field[$i + 1];
				$default = defined $next && $next =~ /\A[^$SP]+\z/
					? { arg => $field[++$i], named => 1 } : { arg => q() };
				next;
			}
			for my $sel (grep { length } split /[$SP]+/, $field[$i]) {
				my ($mode, $name) = _selector($sel);
				# (WANT: and NEED: alone are the first of the manifest)
				if (!length $name) {
					$default ||= { arg => $sel, mode => $mode };
					next;
				}
				push @own, $sel;
			}
		}
	}

	my $implied = !$default && !@own;
	$default = { arg => q() } if $implied;
	my %goal = map { $_->{name} => $_ } @spec;
	my $first = sub {
		@spec ? $spec[0]{name} : die _status 0, tagmsg(E => diag(__(
			"%q: expected a goal name"), "-t $_[0]"));
	};
	my (%mode, %how, @order);
	my $add = sub {
		my ($sel, $mode, $name, $how, $as) = @_;
		exists $goal{$name} or die _status 0, tagmsg(E => diag(__("%#q: missing goal %q"), $self->{D}{F}, $name));
		push @order, $name unless exists $mode{$name};
		$mode{$name} = $mode;
		$how{$name}{$how} = $as;
	};
	# (each says how it was selected, as -t would say it: the default as
	# `,goal' if named, `,' or `WANT:' if the first of the manifest; and
	# another as `goal' or `WANT:goal', NEED being no prefix)
	if ($default) {
		my ($mode, $name) = $default->{named} ? _selector($default->{arg})
			: ($default->{mode} || q(NEED), q());
		my $as = $default->{named} ? q(,) . ($mode eq q(WANT) ? "WANT:$name" : $name)
			: $mode eq q(WANT) ? q(WANT:) : q(,);
		$add->($default->{arg}, $mode, length $name ? $name : $first->($default->{arg}), default => $as);
	}
	for my $sel (@own) {
		my ($mode, $name) = _selector($sel);
		$add->($sel, $mode, $name, own => $mode eq q(WANT) ? "WANT:$name" : $name);
	}
	# What the header says: nothing, without -t; else the default first
	$self->{select_args} = $implied ? []
		: [ map { (q(-t), $_) } grep { defined }
			(map { $how{$_}{default} } @order), (map { $how{$_}{own} } @order) ];
	map {
		my $goal = $goal{$_};
		my %how = (default => $how{$_}{default}, select => $how{$_}{own});
		$mode{$_} eq q(WANT)
			? { %$goal, %how, need => [], want => [ sort { $a->{order} <=> $b->{order} }
				@{ $goal->{need} }, @{ $goal->{want} } ] }
			: { %$goal, %how };
	} @order;
}

# A selector of -t: its mode (NEED, unless it says WANT:) and its name
sub _selector
{
	my ($sel) = @_;
	my ($mode, $name) = index($sel, ':') < 0 ? (q(NEED), $sel) : split(/:/, $sel, 2);
	$mode eq 'NEED' || $mode eq 'WANT'
		or die _status 0, tagmsg(E => diag(__("%q: expected NEED or WANT, not %q"),
			"-t $sel", $mode));
	($mode, $name);
}

# The cleaning rules, as { name, files => [ BPATH ] } (see
# _clean_pattern): the opposite of making a goal.  The rule that is not
# for a goal is that of the first (what a bare `make' makes); one that is
# takes what its goal names, in the manifest and the goals it includes.
# Those of -Sclean do not take what is made on the way; those of
# -Spurge do.  Directory markers are kept either way.
sub _clean_rules
{
	my ($self, $goal, $order, $dir) = @_;
	my $node = $self->{node};
	my %pos; @pos{@$order} = 0 .. $#$order;
	my @rule;
	for my $key (qw( clean purge )) {
		my $deep = $key eq 'purge';
		my $files = sub {
			my %have;
			my $walk; $walk = sub {
				$have{$_[0]}++ and return;
				$deep and $walk->($_) for @{ $node->{$_[0]}{kids} };
			};
			$walk->($_) for map { @{ $_->{files} } } @_;
			[ map { $node->{$_}{bpath} } sort { $pos{$a} <=> $pos{$b} } keys %have ];
		};
		for my $pat ($self->_clean_pattern($key)) {
			if ($pat =~ /&/) {
				for my $g (@$goal) {
					(my $name = $pat) =~ s/&/$g->{name}/g;
					push @rule, { name => $name, files => $files->($g), opt => $key };
				}
			} else {
				push @rule, { name => $pat, files => $files->(@$goal ? $goal->[0] : ()), opt => $key };
			}
		}
	}
	my %taken = (%reserved_goal, map { $_->{name} => 1 } @$goal);
	for my $rule (@rule) {
		my $name = $rule->{name};
		my $key = delete $rule->{opt};
		# HEY!  %s is the option, as in -Sclean=clean-& (or -Sclean)
		$taken{$name}++ and die _status 0, tagmsg(E => diag(__("%s: %q is"
			. " also the name of a goal or another rule"),
			defined $self->{S}{$key} ? "-S$key=$self->{S}{$key}" : "-S$key", $name));
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
	my $text = "";
	$text .= "MAKE $goal->{name}\n";
	# (a JUST-WANT that was had is a JUST-NEED, and one that was not is
	# in a comment; the keywords begin at the same column)
	for my $file (@{ $goal->{files} }) {
		$text .= ($goal->{just}{$file} ? "\tJUST-NEED " : "\tNEED ")
			. escape_dep($file, unicode => 1) . "\n";
	}
	for my $drop (@{ $goal->{dropped} }) {
		$text .= ($drop->[2] ? "#\tJUST-WANT " : "#\tWANT ") . "$drop->[0]\t# $drop->[1]\n";
	}
	$text;
}

=item B<generate> [ I<generator>, [ I<file> ] ]

Writes F<MY/MANIFEST> (the goals, resolved), and the build files of
I<generator> in the build directory.  I<generator> is C<make> (the
default), C<bmake> or C<gmake>, which come with siteconf. C<ninja>,
C<doit> and C<redo> are distributions of their own (WwW-SiteConf-Ninja,
WwW-SiteConf-Doit and WwW-SiteConf-Redo) and may not be installed.  I<file>, if given,
is the name of the build file (else F<Makefile>, F<build.ninja> or F<dodo.py>);
to C<redo>, which writes a file for each target and goal, it is the
name of the default goal's (else F<all.do>).  I<file> F</dev/null> is
no file: it is not written.  The files that would not change are left
alone, mtime and all.

The options of the generator are those C<S> of L</new> says.  Each
generator knows some (see its own page); one that it does not know is
said to be unused, if it has a value.

A generator I<name> is lowercase ASCII letters and digits, in parts
joined by C<->, each beginning with a letter.  It is the module
C<RdKw::WwW::SiteConf::Backend::>I<Name>: each part capitalized, and
the C<-> dropped.  So C<gmake> is C<Gmake>, and C<g-make> would be
C<GMake>.  The module has these class methods.  They are for the
generators that come with siteconf or are released with it, and change
with it: they are not a stable interface.

=over

=item C<options>

The names of the options (C<-S>) that it knows.

=item C<default_output>

The name of the file that I<file> names, by default, or C<undef> if
there is none (and so there is no I<file>).

=item C<emit> I<plan>, I<file>

The files to write: a list of C<[ NAME, BYTES ]> or
C<[ NAME, BYTES, EXEC ]>, each I<NAME> relative to the build directory.
A true I<EXEC> makes the file executable (as C<chmod +x> would, under
the umask), for a build tool that runs it as a program.  I<plan> is
what L</plan> returns, with C<opt>, C<prog> and C<args>; I<file> is
the name of the file that L</default_output> names, or C<undef> for F</dev/null>.  A file
whose I<NAME> is C<undef> is not written.

=item C<build_command> I<generator>, I<builddir>, I<file>, I<goal>, I<plan>

The words of what to type to build I<goal> (or the default, if
C<undef>), quoted for the shell.  I<file> is C<undef> unless it was
named.  I<plan> is that of C<emit>, with C<output>: the I<file> that
C<emit> was given.

=back

=item B<generators>

Not a method.  The generators that are installed (that have a module
in C<@INC>), sorted by name: a list of C<[ NAME, FILE ]>, where
I<FILE> is the module that C<require> would load.  It reads every
directory of C<@INC>, so only C<siteconf -VV> asks for it; C<-G>
loads the one module it names.

=cut

# A generator is the module Backend::Name: each part of its name
# capitalized, without the `-' between them
my $BACKEND_NAME = qr/\A[a-z][a-z0-9]*(?:-[a-z][a-z0-9]*)*\z/;

sub _backend_module
{
	my ($name) = @_;
	q(RdKw::WwW::SiteConf::Backend::) . join q(), map { ucfirst } split /-/, $name;
}

sub generators
{
	my %found;
	for my $dir (grep { !ref } @INC) {
		my $sub = "$dir/RdKw/WwW/SiteConf/Backend";
		opendir my $dh, $sub or next;
		for my $file (sort readdir $dh) {
			my ($leaf) = $file =~ /\A((?:[A-Z][a-z0-9]*)+)\.pm\z/ or next;
			# (a capital begins a part: Gmake is gmake, GMake g-make;
			# and the first in @INC is the one that is loaded)
			$found{ join q(-), map { lc } $leaf =~ /([A-Z][a-z0-9]*)/g } ||= "$sub/$file";
		}
	}
	map { [ $_, $found{$_} ] } sort keys %found;
}

sub generate
{
	my ($self, $G, $out) = @_;
	$G = 'make' unless defined $G and length $G;
	$G =~ $BACKEND_NAME or die _status 0, tagmsg(E => diag(__(
		"invalid generator name: %q"), $G));
	my $module = _backend_module($G);
	(my $pm = "$module.pm") =~ s!::!/!g;
	unless (eval { require $pm; 1 }) {
		# (a backend that is there but broken says why)
		$@ =~ /\ACan't locate \Q$pm\E in \@INC/ or die $@;
		die _status 0, tagmsg(E => diag(__(
			# HEY!  %q is the generator (ninja), and
			# %s is the module that implements it
			"unknown generator: %q (%s is not installed)"),
			$G, $module));
	}
	my $outfile = $module->default_output;
	my $named = defined $out && length $out;
	# (-o /dev/null: no such file, as with -i)
	my $discard = $named && $out eq q(/dev/null);
	if ($named) {
		defined $outfile
			or die _status 0, tagmsg(E => diag(__(
				# HEY!  the first %s is the generator, and the
				# second the name it was asked to write (with -o)
				"generator %s writes a file for each target, and cannot"
				. " name them %q"), $G, $out));
	}
	if ($discard) {
		$outfile = undef;
		$named = 0;
	} elsif ($named) {
		$out =~ m!\A[^/\0]+\z! and $out !~ /\A\.\.?\z/
			or die _status 0, tagmsg(E => diag(__("bad output name %q: "
				. "stay in the build directory please"),
				$out));
		$outfile = $out;
	}

	# What the backend has no use for is said (if it has a value; a name
	# alone is for whichever backend knows it), and not planned for
	my %known = map { $_ => 1 } $module->options;
	my $S_all = $self->{S};
	my %S = %$S_all;
	for my $k (sort keys %S) {
		$known{$k} and next;
		delete $S{$k};
		defined $self->{S}{$k} or next;
		# HEY!  the first %s is an option, as -Sclean=x, and the second
		# the generator (make, gmake, ninja)
		$self->_warn(tagmsg(W => diag(__("%s: unused by generator %s"),
			"-S$k=$self->{S}{$k}", $G)));
	}
	local $self->{S} = \%S;
	my $plan = $self->plan;
	$plan->{opt} = \%S;
	my $My = "$self->{B}/MY";
	# (one file, so that no goal is a file name; -l -F says which)
	$self->_report('MY/MANIFEST', update_file("$My/MANIFEST",
		join("\n", map { $self->manifest_text($_) } @{ $plan->{goals} })));

	# What made it, for the header (see header_comment): the program with
	# its generator, then the options.  Not -o: the file may be moved, and
	# is the same file by any name.
	$plan->{prog} = "$self->{prog} -g -G $G";
	$plan->{args} = [
		($self->{strict} ? '-A' : ()),
		# (the goals as selected: the default first, as -t ,goal or -t ,;
		# then each other once, NEED: as no prefix; none if none was)
		@{ $self->{select_args} || [] },
		( map { defined $S_all->{$_} ? "-S$_=$S_all->{$_}" : "-S$_" } sort keys %$S_all ),
	];
	# Bytes.  The backends spell the names as the file system does.
	# (and what has no name is not written: -o /dev/null)
	$plan->{output} = $outfile;
	my @file = grep { defined $_->[0] } $module->emit($plan, $outfile);
	for my $file (@file) {
		my ($name, $text, $exec) = @$file;
		my $path = "$self->{B}/$name";
		_make_dir(dirname($path));
		$self->_report($name, update_file($path, $text, raw => 1));
		# (each time: update_file leaves a file alone that says the same)
		$exec and (chmod 0777 & ~umask, _to_fs($path)
			or die tagmsg(E => diag(__("cannot chmod %q: %m"), $path)));
	}

	# What to type next (the backend says, from the first goal of the
	# manifest)
	my @cmd = $module->build_command($G, $self->{B}, $named ? $outfile : undef,
		@{ $plan->{goals} } ? $plan->{goals}[0]{name} : undef, $plan);
	unless ($self->failed()) {
		$self->_warn(__("Done!") . "\n");
		# HEY!  %s is a command line, as the shell would read it
		$self->_warn(diag(__("To build, run: %s"), "@cmd") . "\n") if @file;
	}
	$plan;
}

# A directory, and those above it, unless it is there
sub _make_dir
{
	my ($dir) = @_;
	my $fs = _to_fs($dir);
	return if -d $fs;
	require File::Path;
	File::Path::make_path($fs, { error => \my $err });
	for (@$err) {
		my (undef, $why) = %$_;
		die _status 0, tagmsg(E => diag(__(
			# HEY!  the %s is why, as the system says it
			"cannot create directory %q: %s"), $dir, $why));
	}
}

sub _report
{
	my ($self, $name, $what) = @_;
	return unless $what;
	$self->_warn(diag($what > 1
		# HEY!  ``Writing'' creates the file, and
		# ``Updating'' overwrites it.   (The phrasing
		# is different from what we call it over at
		# `siteconf -i', primarily because MY/MANIFEST
		# is considered to be our files, so it is
		# assumed that the state prior to updating is
		# consistent with the state now.)
		? __("Writing %#q")
		: __("Updating %#q"), $name) . "\n");
}

=back

=cut

1;
