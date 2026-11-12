package RdKw::WwW::GenGenLib::Template::Provider;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

use Template::Provider;
our @ISA = qw( Template::Provider );

=head1 NAME

WwW::GenGenLib::Template::Provider - Template Toolkit provider for declared dependencies

=head1 SYNOPSIS

    use Template;
    use RdKw::WwW::GenGenLib::Template::Provider;

    my $provider = RdKw::WwW::GenGenLib::Template::Provider->new({
        SOURCE => $apath,               # what is to be processed
        DEFINITION => $D,               # MY/config.mk
        INCLUDE_PATH => [ '.', $D->{a} ],
        ENCODING => 'UTF-8',            # (Template's does not get here)
        CHECK_DEPS => 1,                # load only what is declared
    }) or die RdKw::WwW::GenGenLib::Template::Provider->error, "\n";
    my $tt = Template->new({ LOAD_TEMPLATES => [ $provider ] });
    $tt->process($apath, \%vars, ...) or die $tt->error, "\n";

=head1 DESCRIPTION

A L<Template::Provider> that names files as the file system spells
them, as L<RdKw::I18N::CodeSets> says (B<filesys> of
C<< RdKw::I18N::CodeSets->locale >>): template names are character
strings, and one that cannot be spelled there is an error, not a guess.

And it knows what the source declares.  The header of I<SOURCE> (see
L<RdKw::WwW::GenGenLib/read_deps>) names what it C<NEED>s and C<WANT>s,
and those name theirs, and so on (see L<RdKw::WwW::GenGenLib/walk_deps>):
those are its I<declared dependencies>, as the build file has them.
(Which is which does not matter: a C<NEED> is a declaration, and it is
not for us to check that it is there.)  A declared dependency may be
loaded however it is named (C<ALLOW_DEPS>), and what is not declared
need not be loaded at all (C<CHECK_DEPS>).

What C<INCLUDE>, C<PROCESS>, C<WRAPPER> and C<INSERT> are given is
taken as it is, and naively: a name that is absolute, or begins with
C<./> or C<../>, is that file, and any other is the first file of that
name in I<INCLUDE_PATH> (an undeclared file earlier in the path is not
skipped to find a declared one after it).  That file, as
L<File::Spec/canonpath> spells it, is compared with the declared
dependencies, spelled the same way after their variables are
substituted.  Local C<BLOCK>s are not files.

=head1 OPTIONS

Besides those of L<Template::Provider>, whose C<ABSOLUTE> and
C<RELATIVE> are for what is not declared (or, without C<ALLOW_DEPS>,
for everything):

=over

=item C<SOURCE>

The name of the template that is processed, as it is given to
C<process>.  Required.  It may always be loaded.

=item C<DEFINITION>

The definitions (F<MY/config.mk>), for the variables in the headers.
C<${A}> is the project root, C<.>, as it is to siteconf.  A variable
that is not defined is an error.

=item C<PREFIXES>

The symbolic prefixes that a file may be called by in what we say
(as a header would name it, and as it is also known): by default
C<${a}>, C<${B}/${b}> and C<${B}/${c}>; a list given is the whole
list, and a trailing slash or not makes no difference.  A file is
called by the prefix whose expansion it is under, the longest (so
C<${tem}/x> rather than C<${a}/t/x>, if C<${tem}> is C<site/t>); of
those that are as long, by the first in the list (list C<${B}/${c}>
before C<${B}/${b}> to call a file by that where the two are the
same).  A prefix that expands to C<.> has every relative name under
it, but is the shortest of all; one with a variable not in
I<DEFINITION> is none at all.

=item C<ALLOW_PREFIXES>

The symbolic roots (see L<RdKw::WwW::GenGenLib/split_dep>) that a
declaration may have, such as C<${a}> or C<${B}/${b}>; by default,
any.  A list given is the whole list, and a root is in it only as a
whole (C<${a}> is not C<${a}/${x}>); the empty string is no root at
all, for C<x>, C<../x> and C</x>.  A declaration with another root
is not declared, nor are its own declarations followed.

=item C<ALLOW_DEPS>

True (the default) to load a declared dependency even if C<ABSOLUTE>
or C<RELATIVE> would refuse its name: this is how a build that is
out of the tree may load what it has made, by the name it has.

=item C<CHECK_DEPS>

True to load only what is declared.  False (the default) to load what
is not declared, too, as L<Template::Provider> would.

=item C<RELATIVE_DEPS>, C<ABSOLUTE_DEPS>

Whether a declaration may leave the project root (or the directory
its variables make), and so be declared: with a C<..> in it
(C<../x>, C<${A}/../x>, C<${a}/../../x>), or as an absolute path
(C</x>, C<${A}//x>).  False by default.  What follows a variable is
never absolute: C<${a}//x> is C<${a}/x>, whatever C<${a}> is.  The
root, the variables that are whole segments at the start (C<${B}/${b}>,
see L<RdKw::WwW::GenGenLib/split_dep>), is as it is configured, and is
not checked; what follows is, once its variables are substituted.  This
is about the header only; what a template is given is taken as it is.

=item C<CHECK_HAVE>

True to have the header of I<SOURCE> say C<HAVE>, and name I<SOURCE>
(by any spelling).  False (the default) to leave that to siteconf,
which checks it when it writes the build file.

=item C<GRAPH>, C<FOLLOW>

For L<RdKw::WwW::GenGenLib/walk_deps>: the graph to cache headers in,
and which dependencies to follow (by default C<follow_ok>, which does
not follow what is built, nor what leaves the project root).

=back

No header is read unless C<ALLOW_DEPS>, C<CHECK_DEPS> or C<CHECK_HAVE>
asks for it.  C<COMPILE_DIR> and C<COMPILE_EXT> are not supported:
those write files by names this provider does not spell.

=cut

use Cwd ();
use File::Spec ();
use Template::Constants qw( STATUS_ERROR STATUS_DECLINED );
use RdKw::I18N::CodeSets ();
use RdKw::WwW::GenGenLib 0.0100 qw(
	read_deps walk_deps follow_ok
	norm_dep subs_dep split_dep
	escape_dep uproot );

# (what is said is said, and names spelled, as RdKw::WwW::GenGenLib does)
BEGIN {
	*__ = \&RdKw::WwW::GenGenLib::__;
	*_diag = \&RdKw::WwW::GenGenLib::_diag;
}

# A name as the file system spells it, and back (see RdKw::I18N::CodeSets)
sub _to_fs { RdKw::I18N::CodeSets->locale->to_fs($_[0], { prog => __PACKAGE__ }) }
sub _un_fs { RdKw::I18N::CodeSets->locale->un_fs($_[0], { prog => __PACKAGE__ }) }

my %default = (
	ALLOW_DEPS => 1,
	CHECK_DEPS => 0,
	CHECK_HAVE => 0,
	RELATIVE_DEPS => 0,
	ABSOLUTE_DEPS => 0,
);

=head1 METHODS

=over

=item B<new> \%options

See L</OPTIONS>.  Dies if I<SOURCE> cannot be found, or its header
(or what it declares, and so on) names a variable not in I<DEFINITION>, or
(with C<CHECK_HAVE>) its C<HAVE> is not I<SOURCE>.

=cut

sub new
{
	my ($class, $args) = @_;
	$args = { %{ $args || {} } };
	for my $k (qw( COMPILE_DIR COMPILE_EXT )) {
		# HEY!  the first %s is the class name (in every message
		# that starts so), and the second is an option name
		defined $args->{$k} and die _diag(__("%s: %s is not supported"), $class, $k) . "\n";
	}
	defined $args->{SOURCE}
		or die _diag(__("%s: SOURCE (the template to process) is required"), $class) . "\n";
	# We give Template::Provider whole paths, once we have said yes;
	# its own ABSOLUTE and RELATIVE are ours to say.
	my $self = $class->SUPER::new({ %$args, ABSOLUTE => 1, RELATIVE => 1 }) or return;
	$self->{TT_ABSOLUTE} = $args->{ABSOLUTE};
	$self->{TT_RELATIVE} = $args->{RELATIVE};
	$self->{SOURCE} = $args->{SOURCE};
	$self->{DEFINITION} = { %{ $args->{DEFINITION} || {} }, A => '.' };
	$self->{PREFIXES} = [ @{ $args->{PREFIXES} || [ '${a}', '${B}/${b}', '${B}/${c}' ] } ];
	if ($args->{ALLOW_PREFIXES}) {
		$self->{ALLOW_PREFIXES} = {};
		for (@{ $args->{ALLOW_PREFIXES} }) {
			my ($root, $rest) = split_dep($_);
			$rest =~ m{\A/*\z}
				or die _diag(__("%s: ALLOW_PREFIXES: %q is not a symbolic root"), $class, $_) . "\n";
			$self->{ALLOW_PREFIXES}{$root} = 1;
		}
	}
	$self->{$_} = exists $args->{$_} ? $args->{$_} : $default{$_} for keys %default;
	$self->{DECLARED} = {};
	$self->{REFUSED} = {};
	$self->{ALLOW_DEPS} || $self->{CHECK_DEPS} || $self->{CHECK_HAVE}
		or return $self;

	my $source = $self->_entry;
	defined $source or die _diag(__("%s: source %q not found"), $class, $args->{SOURCE}) . "\n";
	my %I = read_deps($source);
	if ($self->{CHECK_HAVE}) {
		defined $I{HAVE} or die _diag(__("%s: %q: no HAVE"), $class, $source) . "\n";
		$self->_norm($I{HAVE}) eq File::Spec->canonpath($source)
			or die _diag(__("%s: %q: You HAVE %q, but it is actually %s"),
				$class, $source, $I{HAVE}, $self->_named($source)) . "\n";
	}
	$self->{ALLOW_DEPS} || $self->{CHECK_DEPS} or return $self;

	# Everything it declares, and what those declare, and so on; but no
	# variable that we do not have, which would lead somewhere else.
	my $follow = $args->{FOLLOW} || \&follow_ok;
	my @all = walk_deps($self->{DEFINITION},
		map { $self->_vars($_); $_ } @{ $I{NEED} || [] }, @{ $I{WANT} || [] },
		{
			graph => $args->{GRAPH} || {},
			follow => sub {
				$self->_vars($_[1]);
				$self->_allowed_root($_[1]) && $follow->(@_);
			},
		});
	$self->{DECLARED}{ File::Spec->canonpath($source) } = 1;
	for my $spec (@all) {
		my $path = $self->_norm($spec);
		if (defined(my $why = $self->_unreasonable($spec))) {
			$self->{REFUSED}{$path} = $why;
		} else {
			$self->{DECLARED}{$path} = 1;
		}
	}
	$self;
}

# Dies if `spec' names a variable we do not have (a ${$} or a
# ${U+...} is a character, not a variable).
sub _vars
{
	my ($self, $spec) = @_;
	for my $x (norm_dep($spec) =~ /\$\{([^}]+)\}/g) {
		$x eq '$' || $x =~ /\AU\+/ || defined $self->{DEFINITION}{$x}
			# HEY!  the last %s is the variable, as ${name}
			or die _diag(__("%s: %q: no such variable %s"), __PACKAGE__, $spec, "\${$x}") . "\n";
	}
	1;
}

# A declaration, as the path that it names
sub _norm
{
	my ($self, $spec) = @_;
	$self->_vars($spec);
	File::Spec->canonpath(subs_dep($self->{DEFINITION}, $spec));
}

# Whether `spec' has a symbolic root that ALLOW_PREFIXES allows
sub _allowed_root
{
	my ($self, $spec) = @_;
	my $allow = $self->{ALLOW_PREFIXES} or return 1;
	my ($root) = split_dep($spec);
	$allow->{$root};
}

# The option that would let `spec' be declared, if it may not be: its
# symbolic root must be allowed, and the part after it (which is ours,
# as configured) may not climb out of it, nor be absolute where there
# is no root
sub _unreasonable
{
	my ($self, $spec) = @_;
	$self->_allowed_root($spec) or return 'ALLOW_PREFIXES';
	my ($root, $rest) = split_dep($spec);
	my $name = subs_dep($self->{DEFINITION}, $rest);
	if (length $root) {
		$name =~ s!\A/+!!;
	} elsif (File::Spec->file_name_is_absolute($name) && !$self->{ABSOLUTE_DEPS}) {
		return 'ABSOLUTE_DEPS';
	}
	$name =~ m{(?:\A|/)\.\.(?:/|\z)} && !$self->{RELATIVE_DEPS}
		and return 'RELATIVE_DEPS';
	return;
}

# `path', as we say it: and as a header would, if one of the PREFIXES
# leads to it
sub _named
{
	my ($self, $path) = @_;
	$path = File::Spec->canonpath($path);
	my $alias = $self->_alias($path);
	# HEY!  a path, and how a header would name it (${a}/x)
	defined $alias ? _diag(__("%q (aka %q)"), $path, $alias) : _diag('%q', $path);
}

# The longest of the PREFIXES that `path' is under (as they expand),
# with the rest of it; ties go to the first
sub _alias
{
	my ($self, $path) = @_;
	my ($best, $len, $rest);
	for (@{ $self->{PREFIXES} }) {
		(my $prefix = $_) =~ s{/+\z}{};
		my $dir = eval { $self->_norm($prefix) };
		defined $dir or next;
		my ($l, $r);
		if ($dir eq '.') {
			File::Spec->file_name_is_absolute($path) || $path =~ m{\A\.\.(?:/|\z)}
				and next;
			($l, $r) = (0, $path);
		} else {
			defined($r = uproot($dir, $path)) or next;
			$l = length $dir;
		}
		next if defined $best and $l <= $len;
		($best, $len, $rest) = ($prefix, $l, $r);
	}
	defined $best or return;
	length $rest ? "$best/" . escape_dep($rest, unicode => 1) : $best;
}

# The first file named so in INCLUDE_PATH, which is the one we would load
sub _resolve
{
	my ($self, $name) = @_;
	my $paths = $self->paths or return;
	for my $dir (@$paths) {
		my $path = "$dir/$name";
		return $path if -f _to_fs($path);
	}
	return;
}

# Absolute, or relative (`./x', `../x'), as Template::Provider says
sub _kind
{
	my ($name) = @_;
	File::Spec->file_name_is_absolute($name) ? 'ABSOLUTE'
		: $name =~ m{\A\.+/} ? 'RELATIVE' : '';
}

# The file `name' is, if there is one
sub _find
{
	my ($self, $name) = @_;
	_kind($name) or return $self->_resolve($name);
	-f _to_fs($name) ? $name : undef;
}

sub _entry
{
	my ($self) = @_;
	$self->_find($self->{SOURCE});
}

=item B<access> I<name>

The file that B<fetch> and B<load> would load for I<name> (by the
rules in L</DESCRIPTION>: absolute, C<./> or C<../> as it is, and any
other the first in I<INCLUDE_PATH>), and whether they may: in list
context, the path (absolute, as L<Cwd/abs_path> spells it) and
C<undef>, or C<undef> and what is wrong.  Both are C<undef> if there
is no such file.

    my ($path, $error) = $provider->access("./$file");
    defined $error and die "$file: $error\n";
    defined $path or die "$file: not found\n";

=cut

sub access
{
	my ($self, $name) = @_;
	my $path;
	if ($name eq $self->{SOURCE}) {
		$path = $self->_entry;
		defined $path or return;
	} else {
		my $kind = _kind($name);
		$path = $kind ? $name : $self->_resolve($name);
		defined $path or return;
		my $dep = File::Spec->canonpath($path);
		my $declared = $self->{DECLARED}{$dep};
		if ($self->{CHECK_DEPS} && !$declared) {
			my $why = $self->{REFUSED}{$dep};
			# HEY!  the first (or only) %s is a name, as "%q (aka %q)"
			# says it, and a second is an option name, as it is
			return (undef, !defined $why
				? _diag(__("undeclared dependency: %s"), $self->_named($dep))
				: $why eq 'ALLOW_PREFIXES'
				? _diag(__("%s is declared, but forbidden because %s does not permit its root"),
					$self->_named($dep), $why)
				: _diag(__("%s is declared, but forbidden because %s is unset"),
					$self->_named($dep), $why));
		}
		if ($kind && !($self->{ALLOW_DEPS} && $declared) && !$self->{"TT_$kind"}) {
			return (undef, $kind eq 'ABSOLUTE'
				? __("absolute paths are not allowed (ABSOLUTE is unset)")
				: __("relative paths are not allowed (RELATIVE is unset)"));
		}
		-f _to_fs($path) or return;
	}
	my $abs = Cwd::abs_path(_to_fs($path));
	defined $abs or return (undef, _diag('%q: %m', $path));
	(_un_fs($abs), undef);
}

=item B<fetch> I<name>

=item B<load> I<name>

As in L<Template::Provider>, as the options say (C<INSERT> goes
through B<load>, the rest through B<fetch>).  A name we do not find
is declined, for the next provider.

=cut

sub fetch
{
	my ($self, $name, @rest) = @_;
	ref $name and return $self->SUPER::fetch($name, @rest);
	my ($path, $error) = $self->access($name);
	defined $error and return (_diag('%q: %s', $name, $error), STATUS_ERROR);
	defined $path or return (undef, STATUS_DECLINED);
	$self->SUPER::fetch($path, @rest);
}

sub load
{
	my ($self, $name, @rest) = @_;
	ref $name and return $self->SUPER::load($name, @rest);
	my ($path, $error) = $self->access($name);
	defined $error and return (_diag('%q: %s', $name, $error), STATUS_ERROR);
	defined $path or return (undef, STATUS_DECLINED);
	$self->SUPER::load($path, @rest);
}

=back

=cut

# What Template::Provider does to files, by names the file system knows
sub _template_modified
{
	my ($self, $path) = @_;
	defined $path && length $path or return;
	(stat(_to_fs($path)))[9];
}

sub _template_content
{
	my ($self, $path) = @_;
	defined $path && length $path
		or return (undef, "No path specified to fetch content from ");
	my $fs = _to_fs($path);
	my ($data, $error, $mod_date);
	if (-d $fs) {
		$error = _diag(__("%q: not a file"), $path);
	} elsif (open my $fh, '<', $fs) {
		local $/;
		binmode $fh;
		$data = <$fh>;
		$mod_date = (stat $fh)[9];
		close $fh;
	} else {
		$error = _diag('%q: %m', $path);
	}
	wantarray ? ($data, $error, $mod_date) : $data;
}

1;
