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
    }) or die RdKw::WwW::GenGenLib::Template::Provider->error, "\n";
    my $tt = Template->new({ LOAD_TEMPLATES => [ $provider ] });
    $tt->process($apath, \%vars, ...) or die $tt->error, "\n";

=head1 DESCRIPTION

A L<Template::Provider> that does two things.

It names files as the file system's locale does (see
L<RdKw::WwW::GenGenLib/to_fs>): template names are character strings,
and one that cannot be spelled there is an error, not a guess.

And it reads only what the source said it would.  The header of
I<SOURCE> (see L<RdKw::WwW::GenGenLib/read_deps>) names what it
C<NEED>s and C<WANT>s, and those name theirs, and so on (see
L<RdKw::WwW::GenGenLib/walk_deps>): what C<INCLUDE>, C<PROCESS>,
C<WRAPPER> and C<INSERT> load, by any name, must be one of them, so
that what is read is what the build file says the target is made
from.  Local C<BLOCK>s are not files, and need no declaration.

A name is looked up in I<INCLUDE_PATH> in order, and the first file
found is the one that must be declared: an undeclared file earlier in
the path is not skipped to find a declared one after it.  Names are
relative, with no C<.> or C<..> in them, except I<SOURCE> itself.

=head1 OPTIONS

Besides those of L<Template::Provider>:

=over

=item C<SOURCE>

The name of the template that is processed, as it is given to
C<process>.  Required.

=item C<D>

The definitions (F<MY/config.mk>), for the variables in the headers.
C<${A}> is the project root, C<.>, as it is to siteconf.  A variable
that is not defined is an error.

=item C<CHECK_DEPS>

True (the default) to load only what is declared.  False to stay
shallow: anything may be loaded, and nothing is read from any header
(the name of the source in its C<HAVE> is the caller's business).

=item C<GRAPH>, C<FOLLOW>

For L<RdKw::WwW::GenGenLib/walk_deps>: the graph to cache headers in,
and which dependencies to follow (by default C<follow_ok>, which does
not follow what is built, nor what leaves the project root).

=back

C<COMPILE_DIR> and C<COMPILE_EXT> are not supported: those write files
by names this provider does not spell.

=cut

use base 'Template::Provider';
use Cwd ();
use File::Spec ();
use Template::Constants qw( STATUS_ERROR STATUS_DECLINED );
use RdKw::WwW::GenGenLib 0.0100 qw(
	read_deps walk_deps follow_ok
	norm_dep subs_dep to_fs un_fs );

sub new
{
	my ($class, $args) = @_;
	$args = { %{ $args || {} } };
	for my $k (qw( COMPILE_DIR COMPILE_EXT )) {
		defined $args->{$k} and die "$class: $k is not supported\n";
	}
	defined $args->{SOURCE}
		or die "$class: SOURCE (the template to process) is required\n";
	my $self = $class->SUPER::new({ %$args, ABSOLUTE => 1 }) or return;
	$self->{SOURCE} = $args->{SOURCE};
	$self->{D} = { %{ $args->{D} || {} }, A => '.' };
	$self->{CHECK_DEPS} = exists $args->{CHECK_DEPS} ? $args->{CHECK_DEPS} : 1;
	$self->{CHECK_DEPS} or return $self;

	my $source = $self->_entry;
	defined $source or die "$class: source `$args->{SOURCE}' not found\n";
	my %I = read_deps($source);
	defined $I{HAVE} && $self->_norm($I{HAVE}) ne File::Spec->canonpath($source)
		and die "$class: $source: HAVE `$I{HAVE}', but it is `$source'\n";
	# Everything it declares, and what those declare, and so on; but no
	# variable that we do not have, which would lead somewhere else.
	my $follow = $args->{FOLLOW} || \&follow_ok;
	my @all = walk_deps($self->{D},
		map { $self->_vars($_); $_ } @{ $I{NEED} || [] }, @{ $I{WANT} || [] },
		{
			graph => $args->{GRAPH} || {},
			follow => sub { $self->_vars($_[1]); $follow->(@_) },
		});
	my %allowed = ( File::Spec->canonpath($source) => 1 );
	$allowed{ $self->_norm($_) } = 1 for @all;
	$self->{ENTRY} = $source;
	$self->{ALLOWED} = \%allowed;
	$self;
}

# Dies if `spec' names a variable we do not have.
sub _vars
{
	my ($self, $spec) = @_;
	for my $x (norm_dep($spec) =~ /\$\{([^}]+)\}/g) {
		$x eq '$' || defined $self->{D}{$x}
			or die __PACKAGE__ . ": `$spec': no such variable \${$x}\n";
	}
	1;
}

# A declaration, as the path from the root that it names
sub _norm
{
	my ($self, $spec) = @_;
	$self->_vars($spec);
	File::Spec->canonpath(subs_dep($self->{D}, $spec));
}

# Template names are plain relative paths.
sub _safe_name
{
	my ($name) = @_;
	defined $name && !ref $name
		&& length $name
		&& !File::Spec->file_name_is_absolute($name)
		&& $name !~ m{(?:\A|/)\.{1,2}(?:/|\z)};
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

# The source itself, wherever it is: as it is named, if it is absolute
sub _entry
{
	my ($self) = @_;
	my $name = $self->{SOURCE};
	File::Spec->file_name_is_absolute($name)
		? (-f to_fs($name, __PACKAGE__) ? $name : undef)
		: $self->_resolve($name);
}

# The path to load `name' from, or an error; nothing if there is none
sub _authorized
{
	my ($self, $name) = @_;
	my $path;
	if ($name eq $self->{SOURCE}) {
		$path = $self->_entry;
	} else {
		_safe_name($name) or return (undef, "invalid template name");
		$path = $self->_resolve($name);
	}
	defined $path or return;
	if ($self->{CHECK_DEPS}) {
		my $dep = File::Spec->canonpath($path);
		$self->{ALLOWED}{$dep}
			or return (undef, "undeclared dependency `$dep';"
				. " add NEED: $dep to $self->{ENTRY}");
	}
	my $abs = Cwd::abs_path(to_fs($path, __PACKAGE__));
	defined $abs or return (undef, "$path: $!");
	(un_fs($abs, __PACKAGE__), undef);
}

=head1 METHODS

=over

=item B<new> \%options

See L</OPTIONS>.  Dies if I<SOURCE> cannot be found, or its header
(or what it declares, and so on) names a variable not in I<D>, or a
C<HAVE> that is not I<SOURCE>.

=item B<fetch> I<name>

=item B<load> I<name>

As in L<Template::Provider>, but for what is declared (C<INSERT> goes
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
