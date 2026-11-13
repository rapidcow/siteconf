#!perl
#
# t/list.t - siteconf -l: the names of a manifest, for other programs

use utf8;
use strict;
use warnings;
use Test::More;
use Encode ();
use File::Temp qw( tempdir );
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );

my $script = script_path();
$ENV{PERL5LIB} = perl5lib();
plan tests => 38;

my $dir = tempdir(CLEANUP => 1);
sub put
{
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
	print $fh $text;
	close $fh or die;
}

# (stdout, as bytes; stderr; whether it went well)
sub list
{
	# Exercise list syntax with a known encoding, even in a C locale.
	# A later -C can override this for the encoding checks below.
	my @arg = map { "'$_'" } '-C', 'filesys:UTF-8', @_;
	my $out = `cd '$dir' && '$^X' '$script' @arg 2>err`;
	my $ok = $? == 0;
	open my $fh, '<', "$dir/err" or die;
	my $err = do { local $/; <$fh> };
	($out, $err, $ok);
}

put('MANIFEST', <<'M');
MAKE all
	NEED index.html
	NEED r${U+00E9}sumé.html     # é, and é
	WANT extra/a${U+0020}b.html
	NEED index.html              # (once is enough)
MAKE small
	NEED index.html
	WANT x${U+003A}y
M

my $resume = Encode::encode('UTF-8' => 'résumé.html');
my ($out, $err, $ok) = list('-l');
ok($ok, '-l') or diag $err;
is($out, "index.html\n${resume}\nextra/a b.html\n",
	'... NEEDs, then WANTs, of the default goal; unescaped, once each,'
	. ' and spelled as the file system does');
is($err, '', '... and nothing else is said');
is((list('list'))[0], $out, 'list: the same');
is((list('-l', '-012'))[0], $out, '-012: the default');
is((list('-l', '-F', 'MANIFEST'))[0], $out, '-F');

($out) = list('-l', '-0');
($_ = $out) =~ s/\0/\n/g; is($_, (list('-l'))[0], '-0: NUL instead');
like($out, qr/\0\z/, '... which ends each name, the last too');
($out) = list('-l0');
like($out, qr/\A[^\0]+\0[^\0]+\0[^\0]+\0\z/, '-l0: bundled');
($out) = list('-l', '-072');
like($out, qr/\Aindex\.html:[^:]+:extra\/a b\.html:\z/, '-072: a colon');

is((list('-l', '-t', ':NEED'))[0] =~ tr/\n//, 2, '-t :NEED: what the default needs');
is((list('-l', '-t', ':WANT'))[0], "extra/a b.html\n", '-t :WANT');
is((list('-l', '-t', 'small'))[0], "index.html\nx:y\n", '-t goal: both');
is((list('-l', '-t', 'small:WANT'))[0], "x:y\n", '-t goal:WANT');
is((list('-l', '-t', 'small:'))[0], "index.html\nx:y\n", '-t goal: (nothing after)');
is((list('-l', '-t', 'small:WANT', '-t', 'all:WANT', '-t', 'small'))[0],
	"x:y\nextra/a b.html\nindex.html\n", '-t, more than once: joined, once each');

sub bad
{
	my ($re, $what, @arg) = @_;
	my ($out, $err, $ok) = list(@arg);
	ok(!$ok && $out eq '', "$what: fails, and lists nothing");
	like($err, $re, "$what: says why");
}
# (names are written as they come: those before the bad one are out already)
sub bad_late
{
	my ($re, $what, $sofar, @arg) = @_;
	my ($out, $err, $ok) = list(@arg);
	ok(!$ok && $out eq $sofar, "$what: fails, and lists no more");
	like($err, $re, "$what: says why");
}
bad(qr/\Asiteconf: `MANIFEST': no goal `nope'$/, 'no such goal', '-l', '-t', 'nope');
bad(qr/`-t all:need': expected NEED or WANT, not `need'/, 'no such type', '-l', '-t', 'all:need');
bad(qr/-0400: not a valid ASCII octal code point/, 'too big a separator', '-l', '-0400');
bad(qr/-0 is not permitted in mode -g \(make\)/, '-0 elsewhere', '-g', '-0');
bad(qr/-t is not permitted in mode -i \(init\)/, '-t elsewhere', '-i', '-t', 'all');
bad(qr/-B is not permitted in mode -l \(list\)/, '-B', '-l', '-B', '.');
bad(qr/\Asiteconf: cannot open file `nope': /, 'no manifest', '-l', '-F', 'nope');
bad_late(qr/x:y' conflicts with record separator -072/, 'a name with the separator',
	'index.html:', '-l', '-072', '-t', 'small');
bad_late(qr/\Asiteconf: MANIFEST: cannot encode "r\\x\{e9\}sum\\x\{e9\}\.html" in US-ASCII$/,
	'ASCII cannot spell résumé', "index.html\n", '-C', 'filesys:ascii', '-l');
($out, $err, $ok) = list('-C', 'filesys:ISO-8859-1', '-l');
ok($ok && $err eq '', 'Latin-1 can spell résumé') or diag $err;
is($out, Encode::encode('ISO-8859-1', "index.html\nrésumé.html\nextra/a b.html\n"),
	'... in the requested filesystem encoding');
put('BAD', "MAKE all\n\tNEED a\n\tNEED x\${U+D800}y\n");
bad_late(qr/\Asiteconf: BAD: cannot encode "x\\x\{d800\}y"/,
	'a name the file system cannot spell (not even with \x{...})',
	"a\n", '-l', '-F', 'BAD');
