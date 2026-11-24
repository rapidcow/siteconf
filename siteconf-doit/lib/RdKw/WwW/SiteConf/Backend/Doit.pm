package RdKw::WwW::SiteConf::Backend::Doit;

use 5.008;
use strict;
use warnings;
use version;
use RdKw::I18N::CodeSets::Functions qw( diag tagmsg );
use RdKw::L10N::TextDomain ':module' => 'RdKw::WwW::SiteConf::L10N';
use RdKw::WwW::SiteConf 0.03_00 ();

our $VERSION = '0.03_00';
$VERSION = version->parse($VERSION);

=head1 NAME

RdKw::WwW::SiteConf::Backend::Doit - Python 3 doit backend for siteconf

=head1 DESCRIPTION

C<siteconf -g -G doit> writes F<dodo.py> in the build directory.
Run C<doit> there to build the first selected goal, or C<doit run goal>
for a named goal. For names containing C<*> or C<=>, use the C<goal:>
prefix and spell those characters as C<%2a> and C<%3d>. The command
printed by siteconf uses this spelling. C<doit clean> removes the default goal's products.
Use C<-o name.py> to choose another module and C<doit -f name.py> to load it.

The module is ASCII. Python string literals spell non-ASCII characters
with Unicode escapes. Python uses its filesystem encoding for file names
and for the arguments to F</bin/sh>. Each recipe line runs in a fresh shell.

=head2 Methods

=over

=item B<options>

None.

=item B<default_output>

F<dodo.py>.

=item B<emit> I<plan>, I<file>

Return the build module as a name and its contents.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

Return the shell words for running doit in the build directory.

=back

=cut

sub _status { $! = 0; $? = shift; @_; }

sub options { () }
sub default_output { 'dodo.py' }

sub _literal
{
	my ($s) = @_;
	$s =~ s/(['\\])/\\$1/g;
	$s =~ s/([^\x20-\x7e])/ord($1) > 0xffff ? sprintf('\\U%08x', ord $1) : sprintf('\\u%04x', ord $1)/ge;
	"'$s'";
}

sub _list { '[' . join(', ', map { _literal($_) } @_) . ']' }

# A colon is unavailable in a siteconf goal. Escape doit's wildcard and
# assignment syntax in private task names, keeping common paths readable.
sub _task_name
{
	my ($kind, $s) = @_;
	$s =~ s/([%*=])/sprintf('%%%02x', ord $1)/ge;
	"$kind:$s";
}

sub _goal
{
	my ($name) = @_;
	$name =~ /[*=]/ ? _task_name('goal', $name) : $name;
}

sub _commands
{
	my ($runs) = @_;
	my ($text, @word) = ('');
	for (@$runs) {
		my ($kind, $s, $where) = @$_;
		die _status 0, tagmsg(E => diag(__("%s: NUL in shell command"), $where)) if $s =~ /\0/;
		if ($kind eq 'word') {
			# Keep quoted substitutions intact across make line splitting
			# and dollar unescaping, including a newline inside a name.
			$text .= "\0" . scalar(@word) . "\0";
			push @word, RdKw::WwW::SiteConf::shell_quote($s);
		} else {
			$text .= $s;
		}
	}
	my @cmd;
	for (RdKw::WwW::SiteConf::recipe_commands($text)) {
		my ($ignore, $line) = @$_;
		$line =~ s/\$\$/\$/g;
		$line =~ s/\0(\d+)\0/$word[$1]/ge;
		push @cmd, '[' . ($ignore ? 'True' : 'False') . ', ' . _literal($line) . ']';
	}
	@cmd;
}

sub emit
{
	my ($class, $plan, $file) = @_;
	die _status 0, tagmsg(E => diag(__("%q: doit needs an output name of the form name.py"), $file))
		if defined $file && $file !~ /\A[^.]+\.py\z/;
	my $out = "# -*- coding: utf-8 -*-\n" . RdKw::WwW::SiteConf::header_comment($plan);
	my @goal = @{ $plan->{goals} };
	my @default = @goal ? _goal($goal[0]{name}) : ();
	$out .= "\nimport os\nimport subprocess\nfrom doit.tools import config_changed\n\n";
	$out .= "DOIT_CONFIG = {'default_tasks': " . _list(@default) . "}\n";
	$out .= <<'PY';

def _build(target, commands):
    parent = os.path.dirname(target)
    if parent:
        os.makedirs(parent, exist_ok=True)
    for ignore, command in commands:
        argv = ['/bin/sh', '-c', command]
        if ignore:
            subprocess.call(argv)
        else:
            subprocess.check_call(argv)


def _file(name, target, inputs, commands):
    return dict(basename=name, targets=[target], file_dep=inputs,
                actions=[(_build, [target, commands])], clean=True,
                uptodate=[config_changed({'commands': commands})])


def task_siteconf():
PY
	my %marker = map { $_->{marker} => 1 } @{ $plan->{dirs} };
	for my $f (@{ $plan->{order} }) {
		my $node = $plan->{node}{$f};
		my $target = $node->{bpath};
		my @cmd = _commands($node->{recipe});
		die _status 0, tagmsg(E => diag(__("%#q: no recipe to make it"), $target)) unless @cmd;
		my @deps = grep { !$marker{$_} } @{ $node->{deps} };
		$out .= '    yield _file(' . _literal(_task_name('file', $target)) . ', '
			. _literal($target) . ', ' . _list(@deps) . ", [\n";
		$out .= "        $_,\n" for @cmd;
		$out .= "    ])\n";
	}
	for my $g (@goal) {
		my @deps = map { _task_name('file', $plan->{node}{$_}{bpath}) } @{ $g->{files} };
		$out .= '    yield dict(basename=' . _literal(_goal($g->{name}))
			. ', actions=None, task_dep=' . _list(@deps) . ")\n";
	}
	$out .= "    pass\n" unless @goal || @{ $plan->{order} };
	[ $file, $out ];
}

sub build_command
{
	my ($class, $prog, $B, $file, $goal) = @_;
	my $q = \&RdKw::WwW::SiteConf::shell_quote;
	my @cmd = ($prog, 'run', (defined $file ? ('-f', $q->($file)) : ()),
		(defined $goal ? $q->(_goal($goal)) : ()));
	$B eq '.' ? @cmd : ('(', 'cd', $q->($B), '&&', @cmd, ')');
}

1;
