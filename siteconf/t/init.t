use strict;
use warnings;
use Test::More;
use Cwd qw(getcwd);
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use RdKw::WwW::GenGenLib qw( read_make );

my $root = getcwd();
my $script = script_path();
plan tests => 125;
local $ENV{PERL5LIB} = perl5lib();
my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;
make_path('tools', 'bin', 'project');

sub invoke {
	open my $fh, '-|' or do {
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, $script, @_;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	return ($? >> 8, $out);
}
sub slurp {
	open my $fh, '<', $_[0] or die "$_[0]: $!";
	local $/; <$fh>;
}

# Outputs are named relative to us; render, relative to the project root.
my ($status, $out) = invoke('init', '-P', 'web', '-SA=project',
	'-o', 'configure:tools/setup', '-o', 'render:bin/render-page');
isnt($status, 0, 'render cannot go in a directory that is not there');
make_path('project/bin');
unlink 'tools/setup';
($status, $out) = invoke('init', '-P', 'web', '-SA=project',
	'-o', 'configure:tools/setup', '-o', 'render:bin/render-page');
is($status, 0, 'mapped init succeeds') or diag $out;
ok(-x 'tools/setup' && -x 'project/bin/render-page', 'both mapped outputs executable');
ok(!-e 'bin/render-page', 'render mapping is relative to the project root');
like(slurp('tools/setup'), qr/^\tA => "project",$/m, 'root is a default like any other');
my $renderer = slurp('project/bin/render-page');
like($renderer, qr/^# HAVE: bin\/render-page$/m, 'renderer HAVE is its mapped name');
like($renderer, qr/^#\s+cd -- \$A && \$\{\^X\} bin\/render-page /m, 'Makefile example runs it by that name');
like($renderer, qr/^# bin\/render-page \(render\) - /m, 'renamed renderer says what it is');
open my $rh, '>', 'project/bin/render-page' or die $!;
print $rh "custom renderer\n";
close $rh;

($status, $out) = invoke('init', '-P', 'web', '-SA=project',
	'-o', 'configure:/dev/null', '-o', 'render:bin/render-page');
is($status, 0, 'suppressed configure is not a failure');
like($out, qr/Not changing project\/bin\/render-page/, 'existing renderer reported');
is(slurp('project/bin/render-page'), "custom renderer\n", 'existing renderer preserved');
ok(!-e 'configure', 'configure suppressed');

my $nullmode = (stat '/dev/null')[2];
($status, $out) = invoke('init', '-P', 'web', '-o', 'render:/dev/null');
is($status, 0, 'renderer suppressed') or diag $out;
ok(-x 'configure' && !-e 'render', 'only configure written');
is((stat '/dev/null')[2], $nullmode, 'null device permissions untouched');

($status, $out) = invoke('init', '-P', 'web', '-SA=project', '-o', 'configure:/dev/null');
is($status, 0, 'renderer can be written alone');
ok(-x 'project/render', 'default renderer goes in the project root');
my $plain = slurp('project/render');
like($plain, qr/^# HAVE: render$/m, 'default renderer HAVE');
like($plain, qr/^# render - /m, 'default renderer name');

($status, $out) = invoke('init', '-o', 'unused', '-o', 'configure:bin/a:b');
is($status, 0, 'last mapping wins and destination can contain a colon');
ok(-x 'bin/a:b' && !-e 'unused', 'correct destination');
($status, $out) = invoke('init', '-o', './literal:colon');
is($status, 0, 'escaped bare colon filename');
ok(-x 'literal:colon', 'bare destination written');
($status, $out) = invoke('init', '-P', 'web', '-o', 'tools/legacy', '-SA=project');
is($status, 0, 'legacy bare output works');
ok(-x 'tools/legacy', 'legacy configure destination');
is(slurp('project/render'), $plain, 'existing default renderer unchanged');

# -DA is a default like the others; -SA and -DA are the same thing.
($status, $out) = invoke('init', '-DA=/some/where', '-o', 'tools/da');
is($status, 0, '-DA is accepted') or diag $out;
like(slurp('tools/da'), qr/^\tA => "\/some\/where",$/m, '-DA is baked in');
($status, $out) = invoke('init', '-SA=x', '-DA=y', '-o', 'tools/sada');
isnt($status, 0, '-SA with -DA is rejected');
like($out, qr/-SA and -DA are the same thing/, '... and says so');
($status, $out) = invoke('init', '-SB=x', '-DB=y', '-o', 'tools/sbdb');
isnt($status, 0, '-SB with -DB is rejected');
($status, $out) = invoke('init', '-SA=', '-o', 'tools/empty');
isnt($status, 0, 'empty -SA is rejected');
($status, $out) = invoke('init', '-DA=', '-o', 'tools/empty');
isnt($status, 0, 'empty -DA is rejected');
($status, $out) = invoke('init', '-P', 'web', '-DA=project',
	'-o', 'configure:/dev/null', '-o', 'render:bin/da-render');
is($status, 0, '-DA places render like -SA') or diag $out;
ok(-x 'project/bin/da-render', '... in the project root');

# Existing outputs are skipped independently, without aborting init.
my $configure = slurp('configure');
($status, $out) = invoke('init', '-P', 'web', '-Otitle=changed', '-SA=project',
	'-o', 'render:bin/render-page');
is($status, 1, 'existing configure gives status 1');
is(slurp('configure'), $configure, 'configure is not overwritten by default');
is(slurp('project/bin/render-page'), "custom renderer\n", 'renderer is not overwritten by default');
like($out, qr/^Not changing configure$/m, 'skipped configure reported');
like($out, qr/^Not changing project\/bin\/render-page$/m, 'skipped renderer reported');
like($out, qr/You already have configure/, 'missing configure is an error');
like($out, qr/-f to overwrite/, '... that suggests -f');
($status, $out) = invoke('init', '-q', '-P', 'web', '-SA=project', '-o', 'render:bin/render-page');
is($status, 1, 'quiet does not change skipped-configure status');
is($out, '', 'quiet says nothing');

($status, $out) = invoke('init', '-P', 'web', '-SA=project', '-o', 'render:bin/new-render');
is($status, 1, 'skipped configure does not stop renderer creation');
ok(-x 'project/bin/new-render', 'renderer created after skipping configure');
like($out, qr/^Wrote project\/bin\/new-render$/m, 'new renderer reported');

($status, $out) = invoke('init', '-P', 'web', '-SA=project', '-o', 'configure:new-configure',
	'-o', 'render:bin/render-page');
is($status, 0, 'skipped renderer does not affect success');
like($out, qr/^Wrote new-configure$/m, 'written configure reported');
unlike($out, qr/You already have/, 'no error for a skipped renderer');

($status, $out) = invoke('init', '-f', '-P', 'web', '-Otitle=changed', '-SA=project',
	'-o', 'render:bin/render-page');
is($status, 0, 'force overwrites existing outputs');
isnt(slurp('configure'), $configure, 'configure replaced');
is(slurp('project/bin/render-page'), $renderer, 'renderer replaced');
like($out, qr/^Overwrote configure$/m, 'configure overwrite reported');
like($out, qr/^Overwrote project\/bin\/render-page$/m, 'renderer overwrite reported');
($status, $out) = invoke('init', '-f', '-o', 'brand-new');
is($status, 0, 'force can create a new output');
is($out, "Wrote brand-new\n", 'force does not imply an overwrite');
($status, $out) = invoke('init', '-f', '-q');
is($status, 0, 'quiet force succeeds');
is($out, '', 'quiet suppresses overwrite messages');

for my $flags ([], ['-f'], ['-q']) {
	($status, $out) = invoke('init', @$flags, '-P', 'web',
		'-o', 'configure:/dev/null', '-o', 'render:/dev/null');
	is($status, 0, "fully suppressed output is fine (@$flags)");
	is($out, '', '... and quiet');
}
is((stat '/dev/null')[2], $nullmode, 'force leaves null device permissions alone');

# Names we cannot write in a HAVE (or the Makefile example);
# rejected before anything is written.
for my $bad ('a b', '"quoted', "tab\there", 'what?', 'quoted"', 'bin/"x"') {
	($status, $out) = invoke('init', '-P', 'web', '-SA=project',
		'-o', 'configure:bad-name', '-o', "render:$bad");
	isnt($status, 0, "reject render name <$bad>");
	like($out, qr/^siteconf: dangerous name for render: .* is not supported/, 'useful diagnostic');
	ok(!-e "project/$bad" && !-e 'bad-name', 'nothing written');
}
# (and a no-break space, which is not white space: see t/unicode.t)
for my $ok ('what?.pl', 'a"b') {
	($status, $out) = invoke('init', '-P', 'web', '-SA=project',
		'-o', 'configure:/dev/null', '-o', "render:$ok");
	is($status, 0, "accept render name <$ok>") or diag $out;
}

# A $ in the name is a $ in its HAVE (and in the rulebook)
($status, $out) = invoke('init', '-P', 'web', '-SA=project',
	'-o', 'configure:/dev/null', '-o', 'render:bin/re$nder');
is($status, 0, 'a render named with a $') or diag $out;
like(slurp('project/bin/re$nder'), qr/^# HAVE: bin\/re\$\{\$\}nder$/m, '... HAVEs it, escaped');

for my $case (
	[ ['init', '-o', 'unknown:foo'], qr/unknown output name/ ],
	[ ['init', '-o', 'render:'], qr/empty output path/ ],
	[ ['init', '-o', 'render:foo'], qr/preset does not supply/ ],
	[ ['make', '-o', 'render:foo'], qr/only for init/ ],
	[ ['make', '-f'], qr/-f is not permitted in mode -g \(make\)/ ],
) {
	($status, $out) = invoke(@{ $case->[0] });
	isnt($status, 0, "reject @{$case->[0]}");
	like($out, $case->[1], 'useful diagnostic');
}
{
	# subtest: definition and option defaults use configure syntax
	my @args = ('-Dtailwind', '-Dexplicit=', '-Dchain=a=b', '-D', 'separate',
		'-Otheme', '-Oempty=', '-Omessage=hello world', '-Ochain=a=b', '-O', 'separate');
	my ($status, $out) = invoke('init', '-o', 'defaults', @args);
	is($status, 0, 'bare definitions and options accepted') or diag $out;
	like(slurp('defaults'),
		qr/^# options: -Dtailwind -Dexplicit= -Dchain=a=b -Dseparate -Otheme -Oempty= '-Omessage=hello world' -Ochain=a=b -Oseparate$/m,
		'options comment preserves bare names, explicit empties, and values');
	is(system($^X, 'defaults', '-q', '-DB=defaults-state'), 0, 'generated configure runs');
	my %D = read_make('defaults-state/MY/config.mk');
	my %O = read_make('defaults-state/MY/option.mk');
	is_deeply([@D{qw(tailwind explicit chain separate)}], ['', '', 'a=b', ''], 'definition defaults');
	is_deeply([@O{qw(theme empty message chain separate)}], ['', '', 'hello world', 'a=b', ''], 'option defaults');
	($status, $out) = invoke('init', '-o', 'defaults-repeat',
		'-Dtailwind=old', '-Dtailwind', '-Otheme=old', '-Otheme', '-Otheme=new');
	is($status, 0, 'repeated values accepted') or diag $out;
	like(slurp('defaults-repeat'), qr/^# options: -Dtailwind=old -Dtailwind -Otheme=old -Otheme -Otheme=new$/m,
		'options comment keeps repeated arguments in order');
	is(system($^X, 'defaults-repeat', '-q', '-DB=repeat-state'), 0, 'configure with repeated defaults');
	%D = read_make('repeat-state/MY/config.mk');
	%O = read_make('repeat-state/MY/option.mk');
	is_deeply([$D{tailwind}, $O{theme}], ['', 'new'], 'last value wins, including a bare name');
	# ... and a value says what a line cannot hold, as in configure
	($status, $out) = invoke('init', '-o', 'escaped', '-Dpath=evil${U+20}path', '-Oraw=a${$}{U+20}b',
		'-Onl=a${U+000A}b');
	is($status, 0, 'escapes in defaults') or diag $out;
	is(system($^X, 'escaped', '-q', '-DB=escaped-state'), 0, 'configure with escaped defaults');
	%D = read_make('escaped-state/MY/config.mk');
	%O = read_make('escaped-state/MY/option.mk');
	is($D{path}, 'evil path', '${U+20} is a space in a default');
	is($O{raw}, 'a${U+20}b', '${$}{U+20} is not one');
	is($O{nl}, "a\nb", 'a newline can be a default');
	($status, $out) = invoke('init', '-o', 'bad-escape', '-Dx=${U+110000}');
	isnt($status, 0, 'no such code point as a default');
	for my $kind (qw(D O)) {
		for my $arg ('', '=value') {
			($status, $out) = invoke('init', '-o', 'bad-default', "-$kind", $arg);
			isnt($status, 0, "-$kind rejects an empty name");
			like($out, qr/\Q-$kind\E: empty name/, 'says why');
			ok(!-e 'bad-default', 'writes nothing');
		}
	}
}
chdir $root or die $!;
done_testing;
