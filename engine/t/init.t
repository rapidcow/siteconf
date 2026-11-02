use strict;
use warnings;
use Test::More;
use Cwd qw(getcwd);
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $root = getcwd();
my $script = script_path();
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

my ($status, $out) = invoke('init', '-P', 'web', '-SA=../project',
    '-o', 'configure:tools/setup', '-o', 'render:bin/render-page');
is($status, 0, 'mapped init succeeds') or diag $out;
ok(-x 'tools/setup' && -x 'bin/render-page', 'both mapped outputs executable');
ok(!-e 'project/render', 'explicit mapping is relative to invocation directory');
like(slurp('tools/setup'), qr/my \$A = "\.\.\/project";/, 'root still relative to configure');
my $renderer = slurp('bin/render-page');
open my $rh, '>', 'bin/render-page' or die $!;
print $rh "custom renderer\n";
close $rh;
($status, $out) = invoke('init', '-P', 'web', '-o', 'configure:/dev/null', '-o', 'render:bin/render-page');
is($status, 1, 'suppressed configure gives status 1');
like($out, qr/No files changed since target files already exist\. To overwrite, pass -f\./, 'existing output warning');
is(slurp('bin/render-page'), "custom renderer\n", 'existing renderer preserved');
ok(!-e 'configure', 'configure suppressed');

my $nullmode = (stat '/dev/null')[2];
($status, $out) = invoke('init', '-P', 'web', '-o', 'render:/dev/null');
is($status, 0, 'renderer suppressed');
ok(-x 'configure' && !-e 'render', 'only configure written');
is((stat '/dev/null')[2], $nullmode, 'null device permissions untouched');

($status, $out) = invoke('init', '-P', 'web', '-SA=project', '-o', 'configure:/dev/null');
is($status, 1, 'renderer written alone still gives status 1');
unlike($out, qr/No files changed/, 'no warning when renderer was written');
ok(-x 'project/render', 'suppressed configure uses default location for renderer');

($status, $out) = invoke('init', '-o', 'unused', '-o', 'configure:bin/a:b');
is($status, 0, 'last mapping wins and destination can contain a colon');
ok(-x 'bin/a:b' && !-e 'unused', 'correct destination');
($status, $out) = invoke('init', '-o', './literal:colon');
is($status, 0, 'escaped bare colon filename');
ok(-x 'literal:colon', 'bare destination written');
($status, $out) = invoke('init', '-P', 'web', '-o', 'tools/legacy', '-SA=../project');
is($status, 0, 'legacy bare output works');
ok(-x 'tools/legacy', 'legacy configure destination');
is(slurp('project/render'), $renderer, 'default renderer content unchanged');

# Existing outputs are skipped independently, without aborting init.
my $configure = slurp('configure');
($status, $out) = invoke('init', '-P', 'web', '-Otitle=changed',
    '-o', 'render:bin/render-page');
is($status, 1, 'existing configure gives status 1');
is(slurp('configure'), $configure, 'configure is not overwritten by default');
is(slurp('bin/render-page'), "custom renderer\n", 'renderer is not overwritten by default');
is($out, "No files changed since target files already exist. To overwrite, pass -f.\n",
    'one warning when all outputs exist');
($status, $out) = invoke('init', '-q', '-P', 'web', '-o', 'render:bin/render-page');
is($status, 1, 'quiet does not change skipped-configure status');
is($out, '', 'quiet suppresses no-change warning');

($status, $out) = invoke('init', '-P', 'web', '-o', 'render:bin/new-render');
is($status, 1, 'skipped configure does not stop renderer creation');
ok(-x 'bin/new-render', 'renderer created after skipping configure');
is($out, "Wrote bin/new-render\n", 'new file message, no no-change warning');

($status, $out) = invoke('init', '-P', 'web', '-o', 'configure:new-configure',
    '-o', 'render:bin/render-page');
is($status, 0, 'skipped renderer does not affect success');
is($out, "Wrote new-configure\n", 'only written output reported');

($status, $out) = invoke('init', '-f', '-P', 'web', '-Otitle=changed',
    '-o', 'render:bin/render-page');
is($status, 0, 'force overwrites existing outputs');
isnt(slurp('configure'), $configure, 'configure replaced');
is(slurp('bin/render-page'), $renderer, 'renderer replaced');
is($out, "Overwrote configure\nOverwrote bin/render-page\n", 'overwrites reported distinctly');
($status, $out) = invoke('init', '-f', '-o', 'brand-new');
is($status, 0, 'force can create a new output');
is($out, "Wrote brand-new\n", 'force does not imply an overwrite');
($status, $out) = invoke('init', '-f', '-q');
is($status, 0, 'quiet force succeeds');
is($out, '', 'quiet suppresses overwrite messages');

for my $flags ([], ['-f'], ['-q']) {
    ($status, $out) = invoke('init', @$flags, '-P', 'web',
        '-o', 'configure:/dev/null', '-o', 'render:/dev/null');
    is($status, 1, 'suppressed configure gives status 1 even with extra flags');
    is($out, @$flags && $flags->[0] eq '-q' ? '' : "No files changed.\n",
        'fully suppressed output has no existing-files explanation or overwrite advice');
}
is((stat '/dev/null')[2], $nullmode, 'force leaves null device permissions alone');

for my $case (
    [ ['init', '-o', 'unknown:foo'], qr/unknown output name/ ],
    [ ['init', '-o', 'render:'], qr/empty output path/ ],
    [ ['init', '-o', 'render:foo'], qr/preset does not supply/ ],
    [ ['make', '-o', 'render:foo'], qr/only for init/ ],
    [ ['make', '-f'], qr/-f is not for make/ ],
) {
    ($status, $out) = invoke(@{ $case->[0] });
    isnt($status, 0, "reject @{$case->[0]}");
    like($out, $case->[1], 'useful diagnostic');
}
chdir $root or die $!;
done_testing;
