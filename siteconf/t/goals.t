#!perl
#
# t/goal.t - Goal selection and optional goals
# when generating a build file (siteconf -g)

use strict;
use warnings;
use Test::More tests => 70;
use FindBin;
use lib "$FindBin::Bin/lib";

use File::Path qw( make_path );
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib );
use RdKw::WwW::GenGenLib qw( write_make read_manifest );
use RdKw::WwW::SiteConf;

my $script = script_path();
local $ENV{PERL5LIB} = perl5lib();
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/MY", "$dir/html");
sub put {
	my ($name, $text) = @_;
	open my $fh, '>', "$dir/$name" or die $!;
	print $fh $text;
	close $fh or die $!;
}
sub slurp { open my $fh, '<', "$dir/$_[0]" or return ''; local $/; <$fh> }
put('MANIFEST', <<'M');
MAKE broken
    NEED missing
    NEED partial
    WANT absent
    NEED present
MAKE small
    NEED present
    WANT absent
MAKE other
    NEED other.html
M
put('Makefile.in', "present other.html partial: \n\tcp \${a}/\${\@} \${b}/\${\@}\n");
put('html/present', 'present');
put('html/other.html', 'other');
put('html/partial', "# NEED: missing-dependency\n");
write_make("$dir/MY/config.mk", {
	A => '.', B => '.', a => 'html', b => 'site', c => 'site', e => '.ok',
	F => "$dir/MANIFEST", R => "$dir/Makefile.in",
}, prog => 'test');
sub plan_of { RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => [ @_ ], S => { clean => 'clean-&' })->plan }
sub names { [ map { $_->{name} } @{ $_[0]{goals} } ] }
sub run {
	open my $fh, '-|' or do {
		chdir $dir or die $!;
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, $script, @_;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	($? >> 8, $out);
}

eval { plan_of() };
like($@, qr/goal `broken' NEEDs `missing'/, 'without -t the first goal retains its requirements');
is_deeply(names(plan_of('small', 'other')), ['small', 'other'], 'without -t, the others are not made; with it they are');
{
	my $p = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => ['small,other'])->plan;
	is_deeply(names($p), ['small', 'other'], '-t goal,goal');
	$p = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => ['WANT:broken,small'])->plan;
	is_deeply(names($p), ['broken', 'small'], '... with a prefix for each');
}
my $p = plan_of('small');
is_deeply(names($p), ['small'], 'only the requested goal');
is_deeply($p->{goals}[0]{files}, ['present'], 'NEED stays needed; unavailable WANT is dropped');
is_deeply($p->{order}, ['present'], 'unselected goals do not enter the graph');
is_deeply([map { $_->{name} } @{ $p->{clean} }], ['clean-small'], 'clean rules follow selection');
is_deeply(plan_of('NEED:small'), $p, 'explicit NEED is the default');

$p = plan_of('WANT:broken');
is_deeply($p->{goals}[0]{files}, ['present'], 'WANT keeps buildable files');
is_deeply([map { $_->[0] } @{ $p->{goals}[0]{dropped} }], [qw(missing partial absent)],
	'WANT drops original NEEDs and WANTs in manifest order');
like($p->{goals}[0]{dropped}[1][1], qr/missing-dependency/, 'a missing prerequisite drops the whole file');
ok(!exists $p->{node}{partial}, 'no incomplete rule for the dropped file');
# How each goal was selected: [ name, as the default, as a goal of its own ]
sub how { [ map { [ $_->{name}, $_->{default}, $_->{select} ] } @{ $_[0]{goals} } ] }
is_deeply(how(plan_of('WANT:')), [ [ 'broken', 'WANT:', undef ] ], 'WANT: is the default goal, the first of the manifest');
for my $sel ([], [','], [''], ["  \t "], ['NEED:'], [', small'], [',,small']) {
	eval { plan_of(@$sel) };
	like($@, qr/goal `broken' NEEDs `missing'/, "... and so is " . (@$sel ? "-t `$sel->[0]'" : 'no -t'));
}
is_deeply(how(plan_of(',small')), [ [ 'small', ',small', undef ] ], '-t ,small: small is the default goal, and no more');
is_deeply(how(plan_of(',WANT:small')), [ [ 'small', ',WANT:small', undef ] ], '... WANT: too');
is_deeply(how(plan_of(',small,small')), [ [ 'small', ',small', 'small' ] ], '-t ,small,small: and a goal of its own');
for my $sel ([',small,,other'], [',small', ',other']) {
	is_deeply(how(plan_of(@$sel)), [ [ 'small', ',small', undef ], [ 'other', undef, 'other' ] ],
		"-t @{[ join ' -t ', @$sel ]}: the first default is the default");
}
is_deeply(how(plan_of("  small \t")), [ [ 'small', undef, 'small' ] ], '-t small (with white space): no default');
is_deeply(names(plan_of('small', 'WANT:')), [qw(broken small)], 'the default goal comes first, wherever it is');
is_deeply(how(plan_of('', ',small')), [ [ 'small', ',small', undef ] ], "-t '' is no field: -t '' -t ,small is small, the default");
is_deeply(how(plan_of('  ', 'small')), [ [ 'small', undef, 'small' ] ], "... and -t ' ' -t small no default at all");
is_deeply(how(plan_of('small', ',other')), [ [ 'other', ',other', undef ], [ 'small', undef, 'small' ] ], '-t small -t ,other: the default goal is first');
{
	my $sc = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => [ '', ' ' ], S => {});
	eval { $sc->plan };
	is_deeply($sc->{select_args}, [], "... and with -t '' -t ' ' alone, the header says no -t");
}
is_deeply(names(plan_of('other', 'WANT:broken', 'small')), [qw(other broken small)], 'selection order');
is_deeply(names(plan_of('small', 'other', 'NEED:small')), [qw(small other)], 'duplicate goals appear once');
ok(eval { plan_of('broken', 'WANT:broken'); 1 }, 'last mode wins: WANT') or diag $@;
eval { plan_of('WANT:broken', 'NEED:broken') };
like($@, qr/goal `broken' NEEDs `missing'/, 'last mode wins: NEED');
eval { plan_of('WANT:broken', 'NEED:other', 'broken') };
like($@, qr/goal `broken' NEEDs `missing'/, 'an unprefixed goal restores normal requirements');

for my $case (
	['nope', qr/missing goal `nope'/],
	['WANT:nope', qr/missing goal `nope'/],
	['want:small', qr/expected NEED or WANT/],
	['small:WANT', qr/expected NEED or WANT/],
) {
	eval { plan_of($case->[0]) };
	like($@, $case->[1], "bad selector: $case->[0]");
}

my ($status, $out) = run('-g', '-t', 'WANT:broken', '-t', 'small');
is($status, 0, 'CLI accepts -g -t') or diag $out;
like($out, qr/goal `broken' WANTs `missing'/, 'demoted NEED is reported as WANT');
like(slurp('Makefile'), qr/^broken: site\/present$/m, 'selected goal emitted');
unlike(slurp('Makefile'), qr/^other:/m, 'unselected goal omitted');
like(slurp('Makefile'), qr/-t WANT:broken -t small/, 'generation header preserves selectors');
is_deeply([read_manifest({}, "$dir/MY/MANIFEST")->needed('broken')], ['present'],
	'resolved manifest contains only buildable files');
($status, $out) = run('-g', '-q', '-G', 'gmake', '-t', 'other', '-t', 'WANT:broken');
is($status, 0, 'selection works with GNU Make too') or diag $out;
like(slurp('Makefile'), qr/^\.PHONY: [^\n]*\nother:/m, 'first selected goal is the default');
unlike(slurp('MY/MANIFEST'), qr/^MAKE small/m, 'the resolved manifest has the selected goals only');
($status, $out) = run('-g', '-t', 'NEED:broken');
isnt($status, 0, 'CLI NEED still fails on missing requirements');
like($out, qr/goal `broken' NEEDs `missing'/, 'CLI says why');

# -t , (as -t "${DEFAULT:-,}" says, if it is empty) is the first goal,
# whatever the generator
for my $G (qw( make gmake )) {
	($status, $out) = run('-g', '-q', '-G', $G, '-t', 'small', '-t', ',');
	like($out, qr/goal `broken' NEEDs `missing'/, "-G $G -t ,: the first goal, broken");
}

# The header says the goals as they were selected: the default first (,goal
# if named, , or WANT: if the first of the manifest), then the others, each
# once, by name, NEED: as no prefix
my @case = (
	[ [ 'NEED:small', '-t', 'WANT:', '-t', 'small' ], '-t WANT: -t small' ],
	[ [ 'small,WANT:other', '-t', 'WANT:,small' ], '-t WANT: -t small -t WANT:other' ],
	[ [ " small\tother \n" ], '-t small -t other' ],
	[ [ "WANT:, \t,small other" ], '-t WANT: -t small -t other' ],
	[ [ ',small' ], '-t ,small' ],
	[ [ ',small,small', '-t', ',other' ], '-t ,small -t small -t other' ],
);
for my $case (@case) {
	my ($t, $header) = @$case;
	($status, $out) = run('-g', '-q', '-t', @$t);
	is($status, 0, "-t @$t") or diag $out;
	like(slurp('Makefile'), qr/^# options: -G make \Q$header\E$/m, "... is $header in the header");
}
like(slurp('Makefile'), qr/^\.PHONY: [^\n]*\nsmall:/m, '... and the default goal is the first rule');

# -o /dev/null: no build file, and nothing to run
unlink "$dir/Makefile" or die $!;
($status, $out) = run('-g', '-o', '/dev/null', '-t', 'small');
is($status, 0, '-o /dev/null') or diag $out;
ok(!-e "$dir/Makefile", '... writes no Makefile');
unlike($out, qr/To build/, '... and says nothing to run');

done_testing;
