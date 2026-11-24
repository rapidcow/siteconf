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
and for the arguments to F</bin/sh>. By default each recipe line runs in a fresh shell.

=head2 Methods

=over

=item B<options>

By default recipes use C<sh -c> with textual shell quoting.
C<-Srecipe_mode=cmdline> passes each C<:Q> expansion as a shell argument.
Use C<:Q> at an unquoted shell word position in this mode. The shell sees
the recipe arguments as its positional parameters. C<-Sarg_prefix=arg>
first saves them as C<arg1>, C<arg2>, etc., then shifts them away.
Choose a prefix the recipe does not use.

C<-Srecipe_mode=exec> runs a simple external command directly. Literal
C<cd [--] dir &&> prefixes supply its working directory. Commands outside
the supported literal-word syntax run through the default shell form.

C<-Sclean> and C<-Spurge> add tasks for the first goal. Run them with
C<doit run clean> or C<doit run purge>. Purge includes intermediate
products. As with make, C<-Sclean=clean-&> adds a task per selected goal.

=item B<default_output>

F<dodo.py>.

=item B<emit> I<plan>, I<file>

Return the build module as a name and its contents.

=item B<build_command> I<generator>, I<builddir>, I<file>, I<goal>

Return the shell words for running doit in the build directory.

=back

=cut

sub _status { $! = 0; $? = shift; @_; }

sub options { qw(recipe_mode arg_prefix clean purge) }
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

# Parse only literal shell words. Leave expansions, redirects, pipelines,
# assignments and shell builtins to sh. A :Q run is one literal fragment,
# including when a suffix follows it in the same shell word.
sub _exec
{
	my ($line, $word) = @_;
	my (@args, @cd);
	pos($line) = 0;
	while (pos($line) < length $line) {
		$line =~ /\G[ \t]+/gc and next;
		if ($line =~ /\G&&/gc) {
			@args && shift(@args) eq 'cd' or return;
			shift @args if @args && $args[0] eq '--';
			@args == 1 && length $args[0] && $args[0] !~ /^-/ or return;
			# A later absolute cd could hide an earlier failed cd.
			return if @cd && $args[0] =~ m{^/};
			push @cd, shift @args;
			next;
		}
		my $start = pos($line);
		my $arg = '';
		while (1) {
			if ($line =~ /\G\0(\d+)\0/gc) { $arg .= $word->[$1] }
			elsif ($line =~ /\G([a-zA-Z0-9_.,:%+\/@=-]+)/gc) { $arg .= $1 }
			elsif ($line =~ /\G'([^'\0]*)'/gc) { $arg .= $1 }
			elsif ($line =~ /\G"([^"\\\x24\x60\0]*)"/gc) { $arg .= $1 }
			else { last }
		}
		return if pos($line) == $start;
		push @args, $arg;
	}
	return unless @args && length $args[0];
	# Include reserved words and builtins of common /bin/sh implementations.
	return if $args[0] =~ /=/ || $args[0] =~ /\A(?:!|:|\.|alias|bg|bind|break|builtin|caller|case|cd|command|compgen|complete|continue|declare|dirs|disown|do|done|echo|elif|else|enable|esac|eval|exec|exit|export|false|fc|fg|fi|for|function|getopts|hash|help|history|if|in|jobs|kill|let|local|logout|mapfile|popd|printf|pushd|pwd|read|readarray|readonly|return|select|set|shift|shopt|source|suspend|test|then|time|times|trap|true|type|typeset|ulimit|umask|unalias|unset|until|wait|while|\[|\[\[)\z/;
	(\@args, @cd ? join('/', @cd) : undef);
}

sub _action
{
	my ($ignore, $line, $word, $mode, $prefix) = @_;
	my ($argv, $cwd);
	($argv, $cwd) = _exec($line, $word) if $mode eq 'exec';
	unless ($argv) {
		my @args;
		if ($mode eq 'cmdline') {
			$line =~ s/\0(\d+)\0/
				push(@args, $word->[$1]);
				'"$' . '{' . $prefix . scalar(@args) . '}"'
			/ge;
			if (@args && length $prefix) {
				my @save = map { $prefix . $_ . '=${' . $_ . '}' } 1 .. @args;
				$line = join('; ', @save, 'shift ' . scalar(@args), $line);
			}
		} else {
			$line =~ s/\0(\d+)\0/RdKw::WwW::SiteConf::shell_quote($word->[$1])/ge;
		}
		$argv = ['/bin/sh', '-c', $line, 'sh', @args];
	}
	'[' . ($ignore ? 'True' : 'False') . ', ' . _list(@$argv) . ', '
		. (defined $cwd ? _literal($cwd) : 'None') . ']';
}

sub _commands
{
	my ($runs, $mode, $prefix) = @_;
	my ($text, @word) = ('');
	for (@$runs) {
		my ($kind, $s, $where) = @$_;
		die _status 0, tagmsg(E => diag(__("%s: NUL in shell command"), $where)) if $s =~ /\0/;
		if ($kind eq 'word') {
			# Keep quoted substitutions intact across make line splitting
			# and dollar unescaping, including a newline inside a name.
			$text .= "\0" . scalar(@word) . "\0";
			push @word, $s;
		} else {
			$text .= $s;
		}
	}
	my @cmd;
	for (RdKw::WwW::SiteConf::recipe_commands($text)) {
		my ($ignore, $line) = @$_;
		$line =~ s/\$\$/\$/g;
		push @cmd, _action($ignore, $line, \@word, $mode, $prefix);
	}
	@cmd;
}

sub emit
{
	my ($class, $plan, $file) = @_;
	die _status 0, tagmsg(E => diag(__("%q: doit needs an output name of the form name.py"), $file))
		if defined $file && $file !~ /\A[^.]+\.py\z/;
	my $out = "# -*- coding: utf-8 -*-\n" . RdKw::WwW::SiteConf::header_comment($plan);
	my $opt = $plan->{opt} || {};
	my $mode = exists $opt->{recipe_mode} ? ($opt->{recipe_mode} || '') : 'shell';
	die _status 0, tagmsg(E => diag(__("unknown recipe mode %q"), $mode))
		unless $mode =~ /\A(?:cmdline|exec|shell)\z/;
	my $prefix = $opt->{arg_prefix};
	if (exists $opt->{arg_prefix}) {
		defined $prefix && $prefix =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/ && $mode eq 'cmdline'
			or die _status 0, tagmsg(E => diag(__("-Sarg_prefix needs a shell identifier and -Srecipe_mode=cmdline")));
	}
	my @goal = @{ $plan->{goals} };
	my @default = @goal ? _goal($goal[0]{name}) : ();
	$out .= "\nimport errno\nimport os\nimport sys\nfrom doit.action import CmdAction\nfrom doit.tools import config_changed\n\n";
	$out .= "DOIT_CONFIG = {'default_tasks': " . _list(@default) . "}\n";
	$out .= <<'PY';

class _IgnoreFailure(CmdAction):
    def execute(self, out=None, err=None):
        try:
            super().execute(out, err)
        except OSError as error:
            print(error, file=err or sys.stderr)


def _file(name, target, inputs, commands):
    actions = []
    parent = os.path.dirname(target)
    if parent:
        actions.append(CmdAction(['mkdir', '-p', '--', parent], shell=False))
    for ignore, argv, cwd in commands:
        action = _IgnoreFailure if ignore else CmdAction
        actions.append(action(argv, shell=False, cwd=cwd))
    return dict(basename=name, targets=[target], file_dep=inputs,
                actions=actions, clean=True,
                uptodate=[config_changed({'commands': commands})])


def task_siteconf():
PY
	my %marker = map { $_->{marker} => 1 } @{ $plan->{dirs} };
	for my $f (@{ $plan->{order} }) {
		my $node = $plan->{node}{$f};
		my $target = $node->{bpath};
		my @cmd = _commands($node->{recipe}, $mode, defined $prefix ? $prefix : '');
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
	my @clean = @{ $plan->{clean} || [] };
	for my $rule (@clean) {
		my $name = _literal(_goal($rule->{name}));
		$out .= "    yield dict(basename=$name, actions=[CmdAction([sys.executable, __file__, $name], shell=False)])\n";
	}
	$out .= "    pass\n" unless @goal || @clean || @{ $plan->{order} };
	if (@clean) {
		$out .= "\n\nif __name__ == '__main__':\n    files = {\n";
		for my $rule (@clean) {
			$out .= '        ' . _literal(_goal($rule->{name})) . ': ' . _list(@{ $rule->{files} }) . ",\n";
		}
		$out .= <<'PY';
    }
    warnings = []
    for path in files[sys.argv[1]]:
        try:
            os.remove(path)
        except OSError as error:
            if error.errno != errno.ENOENT:
                warnings.append("W: %r: %s" % (path, error.strerror))
    for warning in warnings:
        print(warning, file=sys.stderr)
    sys.exit(bool(warnings))
PY
	}
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
