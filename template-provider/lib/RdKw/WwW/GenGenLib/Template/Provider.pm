package RdKw::WwW::GenGenLib::Template::Provider;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

=head1 NAME

WwW::GenGenLib::Template::Provider - Template Toolkit provider for declared dependencies

=head1 SYNOPSIS

    use Template;
    use RdKw::WwW::GenGenLib::Template::Provider;

    my $provider = RdKw::WwW::GenGenLib::Template::Provider->new({
        SOURCE => $apath,               # what is to be processed
        D => $D,                        # MY/config.mk
        INCLUDE_PATH => [ '.', $D->{a} ],
        ENCODING => 'UTF-8',            # (Template's does not get here)
        CHECK_DEPS => 1,                # load only what is declared
    }) or die RdKw::WwW::GenGenLib::Template::Provider->error, "\n";
    my $tt = Template->new({ LOAD_TEMPLATES => [ $provider ] });
    $tt->process($apath, \%vars, ...) or die $tt->error, "\n";

=head1 DESCRIPTION

A L<Template::Provider> that names files as the file system's locale
does (see L<RdKw::WwW::GenGenLib/to_fs>): template names are character
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

=item C<D>

The definitions (F<MY/config.mk>), for the variables in the headers.
C<${A}> is the project root, C<.>, as it is to siteconf.  A variable
that is not defined is an error.

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

use base 'Template::Provider';
use Cwd ();
use File::Spec ();
use Template::Constants qw( STATUS_ERROR STATUS_DECLINED );
use RdKw::WwW::GenGenLib 0.0100 qw(
	read_deps walk_deps follow_ok
	norm_dep subs_dep split_dep to_fs un_fs );

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
(or what it declares, and so on) names a variable not in I<D>, or
(with C<CHECK_HAVE>) its C<HAVE> is not I<SOURCE>.

=cut

sub new
{
	my ($class, $args) = @_;
	$args = { %{ $args || {} } };
	for my $k (qw( COMPILE_DIR COMPILE_EXT )) {
		defined $args->{$k} and die "$class: $k is not supported\n";
	}
	defined $args->{SOURCE}
		or die "$class: SOURCE (the template to process) is required\n";
	# We give Template::Provider whole paths, once we have said yes;
	# its own ABSOLUTE and RELATIVE are ours to say.
	my $self = $class->SUPER::new({ %$args, ABSOLUTE => 1, RELATIVE => 1 }) or return;
	$self->{TT_ABSOLUTE} = $args->{ABSOLUTE};
	$self->{TT_RELATIVE} = $args->{RELATIVE};
	$self->{SOURCE} = $args->{SOURCE};
	$self->{D} = { %{ $args->{D} || {} }, A => '.' };
	$self->{$_} = exists $args->{$_} ? $args->{$_} : $default{$_} for keys %default;
	$self->{DECLARED} = {};
	$self->{REFUSED} = {};
	$self->{ALLOW_DEPS} || $self->{CHECK_DEPS} || $self->{CHECK_HAVE}
		or return $self;

	my $source = $self->_entry;
	defined $source or die "$class: source `$args->{SOURCE}' not found\n";
	$self->{ENTRY} = File::Spec->canonpath($source);
	my %I = read_deps($source);
	if ($self->{CHECK_HAVE}) {
		defined $I{HAVE} or die "$class: $source: no HAVE\n";
		$self->_norm($I{HAVE}) eq File::Spec->canonpath($source)
			or die "$class: $source: HAVE `$I{HAVE}', but it is `$source'\n";
	}
	$self->{ALLOW_DEPS} || $self->{CHECK_DEPS} or return $self;

	# Everything it declares, and what those declare, and so on; but no
	# variable that we do not have, which would lead somewhere else.
	my $follow = $args->{FOLLOW} || \&follow_ok;
	my @all = walk_deps($self->{D},
		map { $self->_vars($_); $_ } @{ $I{NEED} || [] }, @{ $I{WANT} || [] },
		{
			graph => $args->{GRAPH} || {},
			follow => sub { $self->_vars($_[1]); $follow->(@_) },
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
		$x eq '$' || $x =~ /\AU\+/ || defined $self->{D}{$x}
			or die __PACKAGE__ . ": `$spec': no such variable \${$x}\n";
	}
	1;
}

# A declaration, as the path that it names
sub _norm
{
	my ($self, $spec) = @_;
	$self->_vars($spec);
	File::Spec->canonpath(subs_dep($self->{D}, $spec));
}

# The option that would let `spec' be declared, if it may not be: the
# part after its symbolic root (which is ours, as configured) may not
# climb out of it, nor be absolute where there is no root
sub _unreasonable
{
	my ($self, $spec) = @_;
	my ($root, $rest) = split_dep($spec);
	my $name = subs_dep($self->{D}, $rest);
	if (length $root) {
		$name =~ s!\A/+!!;
	} elsif (File::Spec->file_name_is_absolute($name) && !$self->{ABSOLUTE_DEPS}) {
		return 'ABSOLUTE_DEPS';
	}
	$name =~ m{(?:\A|/)\.\.(?:/|\z)} && !$self->{RELATIVE_DEPS}
		and return 'RELATIVE_DEPS';
	return;
}

# The first file named so in INCLUDE_PATH, which is the one we would load
sub _resolve
{
	my ($self, $name) = @_;
	my $paths = $self->paths or return;
	for my $dir (@$paths) {
		my $path = "$dir/$name";
		return $path if -f to_fs($path, __PACKAGE__);
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
	-f to_fs($name, __PACKAGE__) ? $name : undef;
}

sub _entry
{
	my ($self) = @_;
	$self->_find($self->{SOURCE});
}

# The path to load `name' from, or an error; nothing if there is none
sub _authorized
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
			return (undef, defined $why
				? "`$dep' is declared, but forbidden because $why is unset"
				: "undeclared dependency `$dep'; add NEED: $dep to $self->{ENTRY}");
		}
		if ($kind && !($self->{ALLOW_DEPS} && $declared) && !$self->{"TT_$kind"}) {
			return (undef, lc($kind) . " paths are not allowed (set $kind option)");
		}
		-f to_fs($path, __PACKAGE__) or return;
	}
	my $abs = Cwd::abs_path(to_fs($path, __PACKAGE__));
	defined $abs or return (undef, "$path: $!");
	(un_fs($abs, __PACKAGE__), undef);
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
	my ($path, $error) = $self->_authorized($name);
	defined $error and return ("$name: $error", STATUS_ERROR);
	defined $path or return (undef, STATUS_DECLINED);
	$self->SUPER::fetch($path, @rest);
}

sub load
{
	my ($self, $name, @rest) = @_;
	ref $name and return $self->SUPER::load($name, @rest);
	my ($path, $error) = $self->_authorized($name);
	defined $error and return ("$name: $error", STATUS_ERROR);
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
	(stat(to_fs($path, __PACKAGE__)))[9];
}

sub _template_content
{
	my ($self, $path) = @_;
	defined $path && length $path
		or return (undef, "No path specified to fetch content from ");
	my $fs = to_fs($path, __PACKAGE__);
	my ($data, $error, $mod_date);
	if (-d $fs) {
		$error = "$path: not a file";
	} elsif (open my $fh, '<', $fs) {
		local $/;
		binmode $fh;
		$data = <$fh>;
		$mod_date = (stat $fh)[9];
		close $fh;
	} else {
		$error = "$path: $!";
	}
	wantarray ? ($data, $error, $mod_date) : $data;
}

1;
