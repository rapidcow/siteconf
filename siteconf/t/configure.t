use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
use File::Temp qw( tempdir );
use Cwd ();

my $script = script_path();
eval { require File::ShareDir; 1 }
	or plan skip_all => 'File::ShareDir required, as by siteconf';
plan tests => 38;
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

# Does the file system (of the current directory) take these bytes
# for a name as they are, as we expect of it?  That is: a directory
# under a missing one of that name is ENOENT (and not EILSEQ, EINVAL,
# or whatever else it has to say about the name); one of that name
# can be made, is listed under those very bytes (not normalized, nor
# folded), and can be removed again.  Returns what was surprising, or
# undef if nothing was; leaves nothing behind.
sub fs_surprise {
	my ($name) = @_;
	return 'the name is already taken' if -e $name || -l $name;
	if (mkdir "$name/x") {
		rmdir "$name/x"; rmdir $name;
		return 'mkdir under a missing directory worked';
	}
	return "mkdir under a missing directory: $! (expected ENOENT)"
		unless $!{ENOENT};
	return 'a failed mkdir made something' if -e $name || -l $name;
	mkdir $name or return "mkdir: $!";
	my @found;
	if (opendir my $dh, '.') {
		@found = grep { $_ eq $name } readdir $dh;
		closedir $dh;
	}
	rmdir $name or return "rmdir: $!";
	return 'the name is not listed as it was given' unless @found == 1;
	return 'rmdir left something' if -e $name || -l $name;
	undef;
}

my ($status, $out) = run($script, 'init');
is($status, 0, 'init') or diag $out;

($status, $out) = run('configure', '-q');
is($status, 0, 'no -DB') or diag $out;
ok(-d 'MY', 'in the source tree');

($status, $out) = run('configure', '-q', '-DB=out');
is($status, 0, 'a leaf is made') or diag $out;
ok(-d 'out/MY', 'configured there');

($status, $out) = run('configure', '-q', '-DB=a/b/c');
isnt($status, 0, 'no intermediates by default');
like($out, qr/^E: cannot mkdir `a\/b\/c': .*non-leaf/, 'says why');
ok(!-e 'a', 'and made nothing');

# What configure says of a name, it says as CodeSets says it: under
# diag ascii, what is not ASCII is \x{...} (the name is UTF-8 bytes).
# The file system code set is pinned, so that the locale has no say;
# the file system itself still does, so ask it first.
SKIP: {
	my $why = fs_surprise("r\xc3\xa9");
	skip "file system: $why", 2 if defined $why;
	($status, $out) = run('configure', '-Cargv:UTF-8,stderr:UTF-8,diag:ascii,filesys:UTF-8', '-q', "-DB=r\xc3\xa9/x");
	isnt($status, 0, 'no intermediates, by any name');
	like($out, qr/^E: cannot mkdir "r\\x\{e9\}\/x": .*non-leaf/, '... said in ASCII under diag ascii');
}

($status, $out) = run('configure', '-q', '--mkpath', '-DB=a/b/c');
is($status, 0, '--mkpath') or diag $out;
ok(-d 'a/b/c/MY', 'made the whole chain');

($status, $out) = run('configure', '-q', '--mkpath', '-DB=a/b/c');
is($status, 0, '--mkpath where it all exists');

open my $fh, '>', 'f' or die; close $fh;
($status, $out) = run('configure', '-q', '--mkpath', '-DB=f/x/y');
isnt($status, 0, '--mkpath below a file');
like($out, qr/^E: cannot create `f': /, 'names the culprit');
unlike($out, qr/ at \S+ line \d+/, 'and has no position');

($status, $out) = run('configure', '-q', '-DB=');
is($status, 0, 'an empty -DB is the default') or diag $out;

mkdir "$tmp/abs" or die "mkdir: $!";
($status, $out) = run('configure', "-DB=$tmp/abs");
is($status, 0, 'an absolute -DB') or diag $out;
like($out, qr/^To generate build script, run: \S+ -g -B \Q$tmp\E\/abs$/m,
	'... is told to the user as it was given');

($status, $out) = run('configure', '-h');
like($out, qr/\[--mkpath\]/, 'usage mentions it');
like($out, qr/^  --mkpath /m, 'help does');
unlike($out, qr/Use of uninit/, 'no warnings');

SKIP: {
	skip 'root can write anywhere', 3 if $> == 0;
	mkdir 'ro' or die; chmod 0555, 'ro';
	($status, $out) = run('configure', '-q', '--mkpath', '-DB=ro/x/y');
	isnt($status, 0, '--mkpath where we may not');
	like($out, qr/^E: cannot create `ro\/x': .*denied/i, 'says so');
	($status, $out) = run('configure', '-q', '-DB=ro/x');
	like($out, qr/^E: cannot mkdir `ro\/x': .*denied/i, 'a leaf too');
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
	like($out, qr/`c' prefix must be a relative path/, '... and says so');

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
