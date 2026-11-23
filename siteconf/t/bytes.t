#!perl
#
# t/bytes.t - a file system encoding that spells a character with
# ASCII bytes (Shift_JIS, GBK, Big5, ... do) must not change what a name
# or a :Q value means to make or the shell.  Quoting is by bytes, after
# the encoding; a name that could be changed is an error.

use utf8;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use TestPaths qw( perl5lib );
use Encode ();

$ENV{PERL5LIB} = perl5lib();

# Perl code run with the file system encoding $enc; what it prints, in hex
sub in_enc
{
	my ($enc, $code) = @_;
	local $ENV{SITECONF_CODESETS} = "filesys:$enc,console:ascii";
	# (as the script does, for what the environment says)
	open my $fh, '-|', $^X, '-e', "use strict; use warnings;
		use RdKw::I18N::CodeSets; use RdKw::WwW::SiteConf;
		RdKw::I18N::CodeSets->locale->parse_from_env('SITECONF_CODESETS', prog => 't');
		\n$code" or die "$!";
	my $out = do { local $/; <$fh> };
	close $fh;
	$out;
}

sub hex_of { join ' ', map { sprintf '%02x', ord } split //, $_[0] }

# Characters, in cp932: 表 is 95 5c, ー is 81 5b, ～ is 81 60, あ is 82 a0
my %chr = (
	hyo => "\x{8868}", chou => "\x{30FC}", wave => "\x{FF5E}", a => "\x{3042}", yen => "\x{A5}",
);
my $try = join ',', map { sprintf 'qq{\\x{%x}}', ord } @chr{qw( hyo chou wave a yen )};
my $out = in_enc('cp932', <<"CODE");
for my \$s ($try, 'plain/name.html') {
	my \$b = eval { RdKw::WwW::SiteConf::fs_text(\$s, 'here') };
	print defined \$b ? "ok\\n" : "no: \$@";
}
CODE
my @line = split /\n/, $out;
is($line[3], 'ok', 'cp932: あ (82 a0) is a name') or diag $out;
my $cp932 = qr/in file system encoding \(cp932\), which contains ASCII metacharacters/;
like($out, qr/^no: .*here: U\+8868 is encoded as 0x95 0x5C $cp932$/m, 'cp932: 表 has a \\ in it');
like($out, qr/^no: .*U\+30FC is encoded as 0x81 0x5B $cp932$/m, 'cp932: ー has a [ in it');
like($out, qr/^no: .*U\+FF5E is encoded as 0x81 0x60 $cp932$/m, 'cp932: ～ has a ` in it');
like($out, qr/^no: .*U\+00A5 is encoded as 0x5C $cp932$/m, 'cp932: ¥ is encoded as a \\ (one way)');
is(scalar(() = $out =~ /^ok$/mg), 2, '... and nothing else, nor ASCII, is refused') or diag $out;

# A stateful encoding spells a character with an ESC, among others
$out = in_enc('iso-2022-jp', <<'CODE');
my $b = eval { RdKw::WwW::SiteConf::fs_text("\x{3042}", 'here') };
print defined $b ? "ok\n" : "no: $@";
CODE
like($out, qr/^no: .*here: U\+3042 is encoded as 0x1B .* in file system encoding \(iso-2022-jp\), which contains ASCII metacharacters$/,
	'iso-2022-jp: no name (it is not an ASCII superset)') or diag $out;

# A word (the last :Q) is spelled first, then quoted: the shell hands back
# the same bytes, and a make `$' is written twice
$out = in_enc('cp932', <<'CODE');
my @run = (
	[ word => "\x{8868}'\x{3042}", 'here' ],
	[ text => ' ', 'here' ],
	[ word => "a\$b\x{30FC}", 'here' ],
);
binmode STDOUT;
print RdKw::WwW::SiteConf::recipe_bytes(\@run);
CODE
is(hex_of($out), hex_of("'\x95\x5c'\\''\x82\xa0' 'a\$\$b\x81\x5b'"),
	'a word is quoted by bytes, and a $ is $$') or diag hex_of($out);
{
	(my $sh = $out) =~ s/\$\$/\$/g;	# (make reads $$ as $)
	open my $fh, '-|', 'sh', '-c', "printf %s $sh" or die $!;
	binmode $fh;
	my $got = do { local $/; <$fh> };
	close $fh;
	is(hex_of($got), hex_of("\x95\x5c'\x82\xa0a\$b\x81\x5b"), 'the shell gets the bytes, a trail byte of \\ too');
}

# ... also where a byte is a quote: here only ISO-2022-JP has one, and
# it is spelled out of its own state, so a shell that reads bytes still
# gets them back
$out = in_enc('iso-2022-jp', <<'CODE');
binmode STDOUT;
my $s = "\x{3042}'\x{4e9c}";
print RdKw::WwW::SiteConf::recipe_bytes([ [ word => $s, 'here' ] ]);
CODE
{
	(my $sh = $out) =~ s/\$\$/\$/g;
	open my $fh, '-|', 'sh', '-c', "printf %s $sh" or die $!;
	binmode $fh;
	my $got = do { local $/; <$fh> };
	close $fh;
	my $want = Encode::encode('iso-2022-jp', "\x{3042}'\x{4e9c}");
	is(hex_of($got), hex_of($want), 'iso-2022-jp: a word comes back as it was, with its ESC and $');
}

# Text is the author's, as is (echo "表" is what they meant); so is a
# variable that is not quoted
$out = in_enc('cp932', <<'CODE');
binmode STDOUT;
print RdKw::WwW::SiteConf::recipe_bytes([ [ text => "echo \"\x{8868}\"", 'Makefile.in line 3' ] ]);
CODE
is(hex_of($out), hex_of("echo \"\x95\x5c\""), 'text is bytes as it is, whatever they are') or diag $out;

# What it does for UTF-8 (every byte of a character is above ASCII)
$out = in_enc('UTF-8', <<'CODE');
binmode STDOUT;
print RdKw::WwW::SiteConf::fs_text("\x{8868}\x{30FC}\x{FF5E}\x{1F600}", 'here');
CODE
is($out, Encode::encode('UTF-8', "\x{8868}\x{30FC}\x{FF5E}\x{1F600}"), 'UTF-8 is as it was');

# The command line is in a comment, which a line break would end, and
# which is ASCII whatever the locale: what is not printable ASCII is
# quoted as Perl would quote it
for my $backend (qw( Make GMake Ninja )) {
	my $class = "RdKw::WwW::SiteConf::$backend";
	eval "require $class" or die $@;
	my $plan = { prog => "t\x{e9}st -g",
		args => [ '-F', "a\nb: ; evil", '-t', 'a b', '-t', "r\x{e9}sum\x{e9}" ],
		D => { e => '.ok' }, goals => [], clean => [], dirs => [], order => [], node => {} };
	my $text = eval { $class->_emit($plan) };
	ok(defined $text, "$backend: a line break and a non-ASCII name in the command line are written") or diag $@;
	is(($text =~ /^(# \(generated.*\n#\n# options:.*\n)/m)[0],
		"# (generated by `\"t\\x{e9}st\" -g' :D)\n"
		. "#\n"
		. "# options: -F \"a\\nb: ; evil\" -t 'a b' -t \"r\\x{e9}sum\\x{e9}\"\n",
		'... in ASCII, on one line') or diag $text;
}

done_testing;
