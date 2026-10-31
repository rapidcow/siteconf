package RdKw::WwW::SiteConf;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.00_00';  # NOT DONE
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

Three inputs make up a project, all found from F<MY/config.mk>:

=over

=item F<Makefile.in> (C<R>)

Transformation rules from C<${a}/FILE> to C<${b}/FILE>.  Rules look
like those of L<make(1)>, with C<${A}>, C<${B}>, C<${a}>, C<${b}>
(and whatever else is in F<config.mk>) substituted, plus C<${@}> or
C<${.TARGET}> for the file being made, C<${^X}> for our perl, and
the C<:Q> modifier to shell-quote (C<${A:Q}>).  Targets are named
relative to C<${b}>.  A rule that depends on a file named F<render>
also depends on F<MY/option.mk>.

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

=item the files themselves

A source file may declare (see L<RdKw::WwW::GenLib/read_deps>)
what it C<NEED>s and C<WANT>s, relative to C<${A}>, or to the
build directory for paths under F<MY/>.

=back

A C<WANT>ed file is resolved at configuration time: it is kept if
there is a rule for it, its source exists, and everything it
C<NEED>s exists.  The resolved goals are written to
F<MY/MANIFEST.I<goal>> in the very same format (all C<NEED>, with
what was dropped left as comments).

=head1 METHODS

=over

=cut

use Carp qw( croak );
use File::Basename qw( dirname basename );
use File::Spec ();

use RdKw::WwW::GenLib qw( read_make read_deps update_file );

# Goals of the manifest cannot take these names; `Makefile' because
# we write it, `clean' because it is ours, and `MY' is a directory.
my %reserved_goal = map { $_ => 1 } qw( clean Makefile MY );

=item B<new> B =E<gt> I<dir>, [ quiet =E<gt> 1 ]

I<dir> is the build directory, as seen from the current directory.
C<MY/config.mk> there must exist.  Warnings are not printed when
I<quiet> is true.

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
	-f $conf or die <<RUSH;
E: You have not configured!
E: (no $conf)  You should ./configure first. ;)
RUSH
	my %D = read_make($conf);
	for my $k (qw( A B a b R F e )) {
		defined $D{$k} && length $D{$k}
			or die "E: $conf: `$k' is missing.  Try reconfiguring.\n";
	}
	File::Spec->file_name_is_absolute($D{b})
		and die "E: `b' prefix must be a relative path.\n";
	$D{e} =~ m!/! and die "E: `e' (directory marker) may not contain a slash.\n";
	$self->{D} = \%D;
	$self;
}

sub D { $_[0]{D} }

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

# `path' relative to `a', as seen from the build dir.  A pure function
# of what is in %D; `a' itself is relative to the sources, unless it
# is absolute (out-of-tree sources).
sub apath
{
	my ($self, $path) = @_;
	my $D = $self->{D};
	File::Spec->canonpath(
		File::Spec->file_name_is_absolute($D->{a})
			? "$D->{a}/$path"
			: "$D->{A}/$D->{a}/$path");
}

# Things under A, as seen from the build dir; and MY/, which is
# build state and is where it says it is.
sub _dep
{
	my ($self, $path) = @_;
	$path =~ m!^MY/! ? $path
		: File::Spec->canonpath("$self->{D}{A}/$path");
}

sub bpath
{
	my ($self, $path) = @_;
	File::Spec->canonpath("$self->{D}{b}/$path");
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
	$file =~ m!\A[^\s:\$#%\\|;<>"'`*?\[\](){}&]+\z!
		or die "E: $where: bad file name `$file'\n";
	$file =~ m!\A/! and die "E: $where: file name `$file' must be relative\n";
	grep { $_ eq '..' } split m!/!, $file
		and die "E: $where: file name `$file' climbs out of the tree\n";
	1;
}

=item B<read_manifest> I<file>

Returns the goals in I<file>, a list of C<{ name, need, want }>
hash references, where the latter two are lists of C<{ file, line }>.
You can also give a scalar reference instead of a file name.

=cut

sub read_manifest
{
	my ($self, $file) = @_;
	my $fh;
	if (ref $file) {
		open $fh, '<:encoding(UTF-8)', $file or die "E: open <string: $!\n";
		$file = 'MANIFEST';
	} else {
		open $fh, '<:encoding(UTF-8)', $file or die "E: open <$file: $!\n";
	}

	my (@goal, %seen, $goal);
	while (<$fh>) {
		chomp;
		s/(?:^|\s)#.*//;
		next if /^\s*$/;
		my $where = "$file line $.";
		my ($kw, @arg) = split ' ';
		if ($kw eq 'MAKE') {
			@arg == 1 or die "E: $where: MAKE takes exactly one goal name\n";
			my $name = $arg[0];
			$name =~ /\A[A-Za-z0-9][-\w.+]*\z/
				or die "E: $where: bad goal name `$name'\n";
			$reserved_goal{$name}
				and die "E: $where: `$name' is a reserved goal name\n";
			$seen{$name}++ and die "E: $where: goal `$name' is already made\n";
			push @goal, $goal = { name => $name, need => [], want => [], line => $. };
			next;
		}
		if ($kw eq 'NEED' or $kw eq 'WANT') {
			$goal or die "E: $where: $kw before any MAKE\n";
			@arg == 1 or die "E: $where: $kw takes exactly one file"
				. " (use # for comments)\n";
			_check_file($arg[0], $where);
			push @{ $goal->{lc $kw} }, { file => $arg[0], line => $. };
			next;
		}
		die "E: $where: expected MAKE, NEED or WANT, not `$kw'\n";
	}
	close $fh;
	@goal or die "E: $file: no goals; what should I make?\n";
	@goal;
}

# What a single `${...}' (or `$x') of Makefile.in turns into.
sub _subst
{
	my ($self, $line, $node, $where) = @_;
	my $D = $self->{D};
	# `${A}/x' with an A of `.' would leave `./x' behind, so
	# it takes its slash with it.
	$line =~ s{\$(\{[^\}]+\}|.)(/?)}{
		my ($x, $slash) = ($1, $2);
		$x =~ s!^\{|\}$!!g;
		my $mod = $x =~ s!:(\w+)$!! ? $1 : "";
		my $val;
		if ($x eq '$') {
			$val = '$';
		} elsif ($x eq '@' or $x eq '.TARGET') {
			defined $node or die "E: $where: \${$x} outside of a recipe\n";
			$val = $node;
		} elsif ($x eq '^X' or $x eq "\030") {
			$val = $^X;
		} else {
			defined $D->{$x} or die "E: $where: undefined variable: \${$x}\n";
			$val = $D->{$x};
		}
		length $mod and $mod ne 'Q'
			and die "E: $where: unknown modifier :$mod\n";
		if ($val eq '.' && length $slash) {
			# `./' is no use to anyone
			($val, $slash) = ('', '');
		} elsif ($mod eq 'Q') {
			$val = shell_quote($val);
		}
		$val . $slash;
	}ge;
	$line;
}

# Makefile.in => { target => { recipe, deps, line } }
sub _read_rules
{
	my ($self) = @_;
	my $D = $self->{D};
	my $file = File::Spec->canonpath("$D->{A}/$D->{R}");
	open my $fh, '<:encoding(UTF-8)', $self->_fs($file)
		or die "E: open <$file: $!\n";

	my (%rule, @node, $stanza);
	while (<$fh>) {
		next if /^\s*#/ or /^\s*$/;
		my $where = "$D->{R} line $.";
		if (/^\t/) {
			@node or die "E: $where: unexpected tabulation\n";
			for my $node (@node) {
				my $rule = $rule{$node};
				if (defined $rule->{stanza} && $rule->{stanza} != $stanza) {
					die "E: $where: more than one recipe for `$node'\n";
				}
				$rule->{stanza} = $stanza;
				$rule->{recipe} .= $self->_subst($_, $node, $where);
			}
			next;
		}
		if (/:/) {
			my ($src, $dep) = split /:/, $_, 2;
			@node = split ' ', $src or die "E: $where: null target list\n";
			$stanza = $.;
			$dep = $self->_subst($dep, undef, $where);
			for my $node (@node) {
				_check_file($node, $where);
				my $rule = ($rule{$node} ||= { recipe => '', deps => [], line => $. });
				push @{ $rule->{deps} }, split ' ', $dep;
			}
			next;
		}
		die "E: $where: invalid line: $_";
	}
	close $fh;

	# Files that use `render' additionally depend on MY/option.mk.
	# This can't really be reflected via a "render: MY/option.mk"
	# rule, so...
	for my $rule (values %rule) {
		if (grep { basename($_) eq 'render' } @{ $rule->{deps} }) {
			push @{ $rule->{deps} }, 'MY/option.mk';
		}
	}
	\%rule;
}

# A node of the graph: what it takes to make one file in `b' from one
# in `a'.  `ok' says whether that can be done at all, and `why' not
# if it cannot.
sub _node
{
	my ($self, $file) = @_;
	my $D = $self->{D};
	return $self->{node}{$file} if $self->{node}{$file};

	my $rule = $self->{rules}{$file};
	my $apath = $self->apath($file);
	my $bpath = $self->bpath($file);
	basename($bpath) eq $D->{e}
		and die "E: $file: `$D->{e}' is reserved for directory markers.\n";

	my $node = $self->{node}{$file} = {
		file => $file,
		apath => $apath,
		bpath => $bpath,
		deps => [],
		recipe => '',
		ok => 1,
		why => [],
	};
	my $fail = sub { $node->{ok} = 0; push @{ $node->{why} }, @_; };

	unless ($rule) {
		$fail->("no rule to make it ($D->{R})");
		return $node;
	}
	unless (-f $self->_fs($apath)) {
		$fail->("source `$apath' is missing");
		return $node;
	}
	$node->{recipe} = $rule->{recipe};

	my %I = read_deps($self->_fs($apath));
	if (defined $I{HAVE} and $I{HAVE} ne $file) {
		die "E: $apath: You have $I{HAVE}, but I have $file?\n";
	}

	my @deps = ($apath, @{ $rule->{deps} });
	my $bdir = File::Spec->canonpath($D->{b});
	for my $dep (@deps, map { $self->_dep($_) } @{ $I{NEED} || [] }) {
		# What `b' holds is made by us, and need not be there yet.
		next if $dep eq $bdir or index($dep, "$bdir/") == 0;
		-e $self->_fs($dep) or $fail->("needs `$dep', which we don't seem to have");
	}
	push @deps, map { $self->_dep($_) } @{ $I{NEED} || [] };
	for my $want (map { $self->_dep($_) } @{ $I{WANT} || [] }) {
		if (-e $self->_fs($want)) {
			push @deps, $want;
		} else {
			$self->_warn("W: $file: WANT `$want' is missing;",
				" going on without it\n");
		}
	}

	my %iHaz;
	$node->{deps} = [ grep { !$iHaz{$_}++ } @deps ];
	$node;
}

=item B<plan>

Reads everything, resolves what is C<WANT>ed, and returns the build
as a hash reference.  Dies, listing every one of them, if anything
that is C<NEED>ed cannot be had.

  goals   [ { name, files => [ FILE ... ], dropped => [ [FILE, WHY] ] } ]
  node    { FILE => { file, apath, bpath, deps, recipe } }
  order   [ FILE ... ]    all files, in order of appearance
  dirs    [ { dir, marker, deps => [ MARKER ] } ]   parents first
  D       the definitions, as in MY/config.mk

=cut

sub plan
{
	my ($self) = @_;
	my $D = $self->{D};
	$self->{node} = {};
	$self->{rules} = $self->_read_rules;

	my $manifest = File::Spec->canonpath("$D->{A}/$D->{F}");
	my @spec = $self->read_manifest($self->_fs($manifest));

	my (@goal, @err, @order, %known);
	for my $spec (@spec) {
		my (@files, %iHaz, @dropped);
		for my $kind (qw( need want )) {
			for my $ent (@{ $spec->{$kind} }) {
				my $file = $ent->{file};
				my $node = $self->_node($file);
				if ($node->{ok}) {
					next if $iHaz{$file}++;
					push @files, $file;
					push @order, $file unless $known{$file}++;
					next;
				}
				my $why = join '; ', @{ $node->{why} };
				if ($kind eq 'need') {
					push @err, "E: $D->{F} line $ent->{line}: goal"
						. " `$spec->{name}' needs `$file': $why\n";
				} else {
					push @dropped, [ $file, $why ];
					$self->_warn("W: goal `$spec->{name}': dropping WANT",
						" `$file': $why\n");
				}
			}
		}
		push @goal, { name => $spec->{name}, files => \@files, dropped => \@dropped };
	}
	@err and die @err, "E: " . scalar(@err) . " problem"
		. (@err == 1 ? '' : 's') . "; no Makefile for you.\n";

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

	+{
		goals => \@goal,
		node => { map { $_ => $self->{node}{$_} } @order },
		order => \@order,
		dirs => \@dir,
		D => $D,
	};
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
	my $text = "#\n# resolved by `$self->{prog}'\n#\n";
	$text .= "MAKE $goal->{name}\n";
	$text .= "\tNEED $_\n" for @{ $goal->{files} };
	for my $drop (@{ $goal->{dropped} }) {
		$text .= "\t# WANT $drop->[0]: $drop->[1]\n";
	}
	$text;
}

=item B<generate> [ I<generator> ]

Writes F<MY/MANIFEST.I<goal>> for each goal, and the build file
for I<generator> (C<make>, the default; C<ninja> has yet to come).
The files that would not change are left alone, mtime and all.

=cut

my %generator = (
	make => [ 'RdKw::WwW::SiteConf::Make', 'Makefile' ],
);

sub generate
{
	my ($self, $G) = @_;
	$G = 'make' unless defined $G and length $G;
	my $gen = $generator{$G} or die "E: unknown generator `$G'"
		. ($G eq 'ninja' ? " (not implemented yet)" : "")
		. ".  Choose one of: " . join(', ', sort keys %generator) . "\n";
	my ($module, $outfile) = @$gen;
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
	for my $old (glob("$My/MANIFEST.*")) {
		my $name = basename($old);
		$name =~ /\AMANIFEST\.[A-Za-z0-9][-\w.+]*\z/ or next;
		$have{$name} or do {
			unlink $old;
			$self->_warn("Removing MY/$name\n");
		};
	}

	$plan->{prog} = "$self->{prog} -g -G $G";
	my $text = $module->can('emit')->($plan);
	$self->_report($outfile, update_file("$self->{B}/$outfile", $text));
	$plan;
}

sub _report
{
	my ($self, $name, $what) = @_;
	return unless $what;
	$self->_warn(($what eq 'created' ? "Writing" : "Updating"),
		($name =~ /^MANIFEST\./ ? " MY/$name" : " $name"), "\n");
}

=back

=cut

1;
