#!perl
#
# t/strict.t - siteconf -g -A: every WANT that
# cannot be had is an error.

use strict;
use warnings;
use Test::More tests => 19;
use FindBin;
use lib "$FindBin::Bin/lib";

use File::Path qw( make_path );
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib );
use RdKw::WwW::GenGenLib qw( write_make );

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
	F => "$dir/MANIFEST", R => "$dir/Makefile.in", clean => 'clean-&',
}, prog => 'test');
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


my ($status, $out) = run('-g', '-t', 'small');
cmp_ok($status, '==', 0, 'without -A, a dropped WANT is no failure') or diag $out;
like($out, qr/^W:.*goal `small' WANTs `absent'/m, '... but a warning');
unlike($out, qr/^E:/m, '... and no error');

($status, $out) = run('-gA', '-t', 'small');
cmp_ok($status, '!=', 0, '-gA: a dropped WANT sets the exit status');
like($out, qr/^W:.*goal `small' WANTs `absent'/m, '... as an error');
like($out, qr/^W:/m, '... still a warning');
like(slurp('Makefile'), qr/^small: site\/present$/m, 'the build file is still written, without it');
like(slurp('Makefile'), qr/siteconf -gA -G make -t small/, '... saying -A in its header');

($status, $out) = run('-gAqt', 'small');
cmp_ok($status, '!=', 0, '-q does not hide the failure') or diag $out;
like($out, qr/^W:.*goal `small' WANTs `absent'/m, '... nor the warning');

($status, $out) = run('-gA', '-t', 'WANT:broken');
cmp_ok($status, '!=', 0, '-A with a WANT: goal');
like($out, qr/^W:.*goal `broken' WANTs `partial'/m, '... says what was dropped');

($status, $out) = run('-gA', '-t', 'other');
is($status, 0, '-A is fine if every WANT could be had') or diag $out;
unlike($out, qr/^[EW]:/m, '... and says nothing of the kind');

($status, $out) = run('-gA', '-t', 'NEED:broken');
isnt($status, 0, '-A and a NEED that cannot be had: still an error');

for my $mode ('-i', '-l') {
	($status, $out) = run($mode, '-A');
	isnt($status, 0, "-A is not for $mode");
	like($out, qr/-A is not permitted in mode/, '... and it says so');
}
