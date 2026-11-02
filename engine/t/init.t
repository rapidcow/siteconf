use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path getcwd);
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my $root = getcwd();
my $script = abs_path('blib/script/siteconf');
-f $script or plan skip_all => 'run make first';
local $ENV{PERL5LIB} = join ':', map { abs_path($_) } grep { !ref && -d } @INC;
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
is($status, 0, 'existing mapped renderer accepted');
is(slurp('bin/render-page'), "custom renderer\n", 'existing renderer preserved');
ok(!-e 'configure', 'configure suppressed');

my $nullmode = (stat '/dev/null')[2];
($status, $out) = invoke('init', '-P', 'web', '-o', 'render:/dev/null');
is($status, 0, 'renderer suppressed');
ok(-x 'configure' && !-e 'render', 'only configure written');
is((stat '/dev/null')[2], $nullmode, 'null device permissions untouched');

($status, $out) = invoke('init', '-P', 'web', '-SA=project', '-o', 'configure:/dev/null');
is($status, 0, 'renderer can be written alone');
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

for my $case (
    [ ['init', '-o', 'unknown:foo'], qr/unknown output name/ ],
    [ ['init', '-o', 'render:'], qr/empty output path/ ],
    [ ['init', '-o', 'render:foo'], qr/preset does not supply/ ],
    [ ['make', '-o', 'render:foo'], qr/only for init/ ],
) {
    ($status, $out) = invoke(@{ $case->[0] });
    isnt($status, 0, "reject @{$case->[0]}");
    like($out, $case->[1], 'useful diagnostic');
}
chdir $root or die $!;
done_testing;
