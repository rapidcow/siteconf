use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Cwd ();
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib fs_surprise );

my $script = script_path();
eval { require File::ShareDir; 1 }
	or plan skip_all => 'File::ShareDir required, as by siteconf';
plan tests => 44;
local $ENV{PERL5LIB} = perl5lib();
my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;

sub run {
	open my $fh, '-|' or do {
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, @_;
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	($? >> 8, $out);
}

my ($status, $out) = run($script, 'init');
is($status, 0, 'init') or diag $out;

($status, $out) = run('configure', '-q');
is($status, 0, 'no -DB') or diag $out;
ok(-d 'MY', 'in the source tree');

($status, $out) = run('configure', '-q', '-DB=out');
isnt($status, 0, 'a leaf is NOT made') or diag $out;
ok(!-d 'out/MY', 'NOT configured there');

($status, $out) = run('configure', '-q', '-DB=a/b/c');
isnt($status, 0, 'no mkdir at all');
like($out, qr/^E: cannot chdir .*/, 'says why');
ok(!-e 'a', 'and made nothing');

# What configure says of a name, it says as CodeSets says it: under
# diag ascii, what is not ASCII is \x{...} (the name is UTF-8 bytes).
# The file system code set is pinned, so that the locale has no say;
# the file system itself still does, so ask it first.
SKIP: {
	my $why = fs_surprise("r\xc3\xa9");
	skip "file system: $why", 2 if defined $why;
	($status, $out) = run('configure', '-Cargv:UTF-8,stderr:UTF-8,diag:ascii,filesys:UTF-8', '-q', "-DB=r\xc3\xa9/x");
	isnt($status, 0, 'no intermediates mkdir, even if it is not encodeable');
	like($out, qr/^E: cannot chdir .*/, '... said in ASCII under diag ascii');
}

($status, $out) = run('configure', '-q', '-DB=');
is($status, 0, 'an empty -DB is the default') or diag $out;

mkdir "$tmp/abs" or die "mkdir: $!";
($status, $out) = run('configure', "-DB=$tmp/abs");
is($status, 0, 'an absolute -DB') or diag $out;
like($out, qr/^To generate build script, run: \S+ -g -B \Q$tmp\E\/abs$/m,
	'... is told to the user as it was given');

($status, $out) = run('configure', '-h');
unlike($out, qr/\[--mkpath\]/, 'usage does not mention it');
unlike($out, qr/^  --mkpath /m, 'help does not');
unlike($out, qr/Use of uninit/, 'no warnings');

SKIP: {
	skip 'root can write anywhere', 3 if $> == 0;
	mkdir 'ro' or die; chmod 0555, 'ro';
	($status, $out) = run('configure', '-q', '--mkpath', '-DB=ro/x/y');
	isnt($status, 0, '--mkpath where we may not');
	like($out, qr/^E: cannot chdir to \$\{B\}/, 'says so');
	($status, $out) = run('configure', '-q', '-DB=ro/x');
	like($out, qr/^E: cannot chdir to \$\{B\}/, 'a leaf too');
	chmod 0755, 'ro';
}

# --- c, the cache: -Dc, then -Sc, then -Db
sub cof {
	my ($dir) = @_;
	open my $fh, '<', "$dir/MY/config.mk" or return "(no config.mk)";
	local $/; my $t = <$fh>;
	$t =~ /^c=\t(.*)$/m ? $1 : '(absent)';
}
{
	mkdir 'cc' or die; my $here = Cwd::getcwd();
	chdir 'cc' or die;
	($status, $out) = run($script, 'init');
	is($status, 0, 'init for c') or diag $out;
	run('configure', '-q');
	is(cof('.'), 'site', 'c is always written; with nothing said it is b');
	run('configure', '-q', '--reset', '-Db=pub');
	is(cof('.'), 'pub', '-Db makes c');
	run('configure', '-q', '-Db=other');
	is(cof('.'), 'other', 'a c that was b follows it');
	run('configure', '-q', '-Dc=cache');
	is(cof('.'), 'cache', '-Dc');
	run('configure', '-q', '-Db=x');
	is(cof('.'), 'cache', 'a c of its own stays');
	($status, $out) = run('configure', '-q', '-Dc=/abs');
	isnt($status, 0, 'c is relative');
	like($out, qr/\$\{c\} prefix must be a relative path/, '... and says so');

	chdir $here or die; mkdir 'cs' or die; chdir 'cs' or die;
	($status, $out) = run($script, 'init', '-Sc=scache');
	is($status, 0, '-Sc is allowed') or diag $out;
	run('configure', '-q', '-Db=q');
	is(cof('.'), 'scache', '-Sc over -Db');
	run('configure', '-q', '--reset', '-Db=q', '-Dc=dd');
	is(cof('.'), 'dd', '-Dc over -Sc');
	($status, $out) = run($script, 'init', '-Sc=/abs');
	isnt($status, 0, '-Sc is relative too');
	run('configure', '-q', '--reset', '-Db=site', '-Dc=site');
	run('configure', '-q', '-Db=other');
	is(cof('.'), 'other', 'an explicit c equal to b still means no distinction');
	chdir $here or die;
}

# --- values: what a line cannot hold is ${U+XXXX}, and -D says it so too
{
	my $here = Cwd::getcwd();
	mkdir 'esc' or die; chdir 'esc' or die;
	($status, $out) = run($script, 'init');
	is($status, 0, 'init (escapes)') or diag $out;
	sub slurp { open my $fh, '<:encoding(UTF-8)', $_[0] or die "$_[0]: $!"; local $/; <$fh> }

	($status, $out) = run('configure', '-q', '-Dx=a b', '-Dy=my dir/sub dir', '-Dz=a${U+20}b',
		"-Dnl=a\nb", '-Dlead= x', "-Oo=t\tab");
	is($status, 0, 'configure with escapes') or diag $out;
	my $conf = slurp('MY/config.mk');
	like($conf, qr/^x=\ta b$/m, '${U+20} in -D is a space; a lone one is written as it is');
	like($conf, qr/^y=\tmy dir\/sub dir$/m, 'a space between others stays');
	like($conf, qr/^z=\ta\$\{\$\}\{U\+20\}b$/m, '${$} before { is a literal $, and written so');
	like($conf, qr/^nl=\ta\$\{U\+000A\}b$/m, 'a newline is written as an escape, not refused');
	like($conf, qr/^lead=\t\$\{U\+0020\}x$/m, 'a space at the end is too');
	like(slurp('MY/option.mk'), qr/^o=\tt\$\{U\+0009\}ab$/m, 'so is a tab in -O');
	($status, $out) = run('configure', '-q');
	is($status, 0, 'configure again, from what was saved') or diag $out;
	like(slurp('MY/config.mk'), qr/^nl=\ta\$\{U\+000A\}b$/m, '... and it reads and writes back the same');

	($status, $out) = run('configure', '-q', '-Ddab=${U+110000}');
	cmp_ok($status, '==', 0, "everything is okay");
	like(slurp('MY/config.mk'), qr/^dab=\t\$\{\$\}\{U\+110000\}$/m, '... because escapes are not interpreted >:]');
	chdir $here or die;
}
