#!perl
# Goal selection and optional goals when generating a build file.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Temp qw( tempdir );
use File::Path qw( make_path );
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
    NEED other
M
put('Makefile.in', "present other partial: \n\tcp \${a}/\${\@} \${b}/\${\@}\n");
put('html/present', 'present');
put('html/other', 'other');
put('html/partial', "# NEED: missing-dependency\n");
write_make("$dir/MY/config.mk", {
	A => '.', B => '.', a => 'html', b => 'site', c => 'site', e => '.ok',
	F => "$dir/MANIFEST", R => "$dir/Makefile.in", clean => 'clean-&',
}, 'test');
sub plan_of { RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => [ @_ ])->plan }
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
like($@, qr/goal `broken' NEEDs `missing'/, 'without -t all goals retain their requirements');
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
is_deeply(names(plan_of('other', 'WANT:broken', 'small')), [qw(other broken small)], 'selection order');
is_deeply(names(plan_of('small', 'other', 'NEED:small')), [qw(small other)], 'duplicate goals appear once');
ok(eval { plan_of('broken', 'WANT:broken'); 1 }, 'last mode wins: WANT') or diag $@;
eval { plan_of('WANT:broken', 'NEED:broken') };
like($@, qr/goal `broken' NEEDs `missing'/, 'last mode wins: NEED');
eval { plan_of('WANT:broken', 'NEED:other', 'broken') };
like($@, qr/goal `broken' NEEDs `missing'/, 'an unprefixed goal restores normal requirements');

for my $case (
	['nope', qr/no goal `nope'/],
	['WANT:nope', qr/no goal `nope'/],
	['want:small', qr/expected NEED or WANT/],
	['small:WANT', qr/expected NEED or WANT/],
	['WANT:', qr/expected a goal name/],
	['', qr/expected a goal name/],
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
is_deeply([read_manifest("$dir/MY/MANIFEST.broken")->needed('broken')], ['present'],
	'resolved manifest contains only buildable files');
($status, $out) = run('-g', '-q', '-G', 'ninja', '-t', 'other', '-t', 'WANT:broken');
is($status, 0, 'selection works with Ninja too') or diag $out;
like(slurp('build.ninja'), qr/^default other$/m, 'first selected goal is the default');
ok(!-e "$dir/MY/MANIFEST.small", 'stale manifest removed when selection changes');
($status, $out) = run('-g', '-t', 'NEED:broken');
isnt($status, 0, 'CLI NEED still fails on missing requirements');
like($out, qr/goal `broken' NEEDs `missing'/, 'CLI says why');

done_testing;
