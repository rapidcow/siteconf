#!perl
#
# t/strings.t - string literals, assignments in
# Makefile.in, and the MANIFEST that names its
# goals as it would a file

use utf8;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { $ENV{LANGUAGE} = 'C'; }
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use TestPaths qw( script_path perl5lib );
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;
use RdKw::WwW::SiteConf::Builder::Gmake;

my $script = script_path();
plan tests => 27;
$ENV{PERL5LIB} = perl5lib();

# A project with the files of `html', the MANIFEST and Makefile.in as given
sub project
{
	my (%f) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/MY", "$dir/html");
	my %file = (
		MANIFEST => "MAKE all\n\tNEED x\n",
		'Makefile.in' => "x: \${a}/x\n\tcp \${A}/\${a}/\${<:Q} \${B}/\${b}/\${\@:Q}\n",
		'html/x' => "x\n",
		%f,
	);
	for my $name (keys %file) {
		open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
		print $fh $file{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		e => '.ok', F => "$dir/MANIFEST", R => "$dir/Makefile.in" }, prog => 'test');
	$dir;
}
sub plan_of
{
	my ($dir, @goal) = @_;
	RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => [ @goal ], S => { clean => 'clean-&' })->plan;
}
sub failure
{
	my ($dir, @goal) = @_;
	eval { plan_of($dir, @goal); 1; } ? '' : $@;
}
# the runs of the recipe that makes `file'
sub recipe { [ map { [ @$_[0, 1] ] } @{ $_[0]{node}{$_[1]}{recipe} } ]; }
# its :Q words
sub words { [ map { $_->[1] } grep { $_->[0] eq 'word' } @{ $_[0]{node}{$_[1]}{recipe} } ]; }

my $mk = "# comment\n";

# --- assignments
{
	my $dir = project(MANIFEST => "MAKE all\n\tNEED feed/x.html\n", 'Makefile.in' => <<'M');
dir =  feed   # a comment
ext=.html
text=h u h  # this is a comment
	a${"\s"}
	 b
	# not a comment${"\s"}
# comment
	c
	${""}
from=${a}/${dir}
表=  表
${dir}/x${ext}: ${a}/x
	echo ${text:Q} ${from:Q} ${表:Q} ${表} ${"表":Q} ${U+8868:Q}
M
	my $p = plan_of($dir);
	is_deeply(words($p, 'feed/x.html'), [ "h u h\na \n b\n# not a comment \nc\n", 'html/feed', '表', '表', '表' ],
		'a value of lines, a variable of its own, a name of a letter, a string and U+');
	is_deeply(recipe($p, 'feed/x.html')->[6], [ text => ' 表 ' ], 'a variable that is not quoted is text') or diag explain recipe($p, 'feed/x.html');
}
{
	my $dir = project('Makefile.in' => <<'M');
var=          # this is a comment
	h u h # in a value
	a${"\s"}

# a comment between
	 b
x: ${a}/x
	echo ${var:Q}
M
	is_deeply(words(plan_of($dir), 'x'), [ "h u h # in a value\na \n b" ],
		'no first line; a # in a continuation is not a comment; a blank line is skipped');
}
{
	my $dir = project('Makefile.in' => "v=1\nv=2\n");
	like(failure($dir), qr/Makefile\.in line 2: \$\{v\} is already defined/, 'twice is an error');
	$dir = project('Makefile.in' => "a=1\n");
	like(failure($dir), qr/line 1: \$\{a\} is already defined/, 'what is configured, too');
	$dir = project('Makefile.in' => "v=\${w}\n");
	like(failure($dir), qr/line 1: undefined variable: \$\{w\}/, 'a variable has to be there already');
	$dir = project('Makefile.in' => "v=\${a:Q}\n");
	like(failure($dir), qr/line 1: :Q \(shell quote\) is not valid in a variable assignment/, 'no :Q in a value');
	$dir = project('Makefile.in' => "x: \${a}/x\n\techo \${v}\nv=1\n");
	like(failure($dir), qr/line 2: undefined variable: \$\{v\}/, 'a variable is not known before its line');
	$dir = project('Makefile.in' => "v=\${\"\\q\"}\n");
	like(failure($dir), qr/line 1: .*\\q.*: illegal escape/, 'a string that has no such escape');
	$dir = project('Makefile.in' => "v=\${\"abc\n");
	like(failure($dir), qr/line 1: unterminated/, 'a string that is not closed');
}

# --- a line break, or a carriage return, in a :Q word
for my $tool (qw( Gmake )) {
	my $class = "RdKw::WwW::SiteConf::Builder::$tool";
	my $dir = project('Makefile.in' => "x: \${a}/x\n\techo \${\"a\\nb\":Q}\n");
	my $p = plan_of($dir);
	$p->{prog} = 'test';
	ok(!eval { $class->_text($p); 1; }, "$tool: a line break cannot be said");
	like($@, qr/Makefile\.in line 2: \w+ cannot spell a line break in `a\\nb'|line break/, '... it says so');
	$dir = project('Makefile.in' => "x: \${a}/x\n\techo \${\"Icon\\r\":Q}\n");
	$p = plan_of($dir);
	$p->{prog} = 'test';
	ok(eval { $class->_text($p); 1; }, "$tool: a carriage return can") or diag $@;
}

# --- the MANIFEST
{
	my $dir = project(
		MANIFEST => "MAKE: default\n\tNEED: food\nMAKE:food\n\tNEED: \${\"some\\sbread\"} jam\n\tWANT:nothing\n",
		'Makefile.in' => "some\\ bread jam: \n\tcp \${a}/\${\@} \${b}/\${\@}\n",
	);
	$dir = project(
		MANIFEST => "MAKE: default\n\tNEED: food\nMAKE:food\n\tNEED: \${\"some\\sbread\"} jam\n\tWANT:nothing\n",
		'Makefile.in' => "\${\"some\\sbread\"} jam: \n\tcp \${a}/\${\@:Q} \${b}/\${\@:Q}\n",
		'html/some bread' => "bread\n", 'html/jam' => "jam\n",
	);
	my $p = plan_of($dir);
	is_deeply($p->{goals}[0]{files}, [ 'some bread', 'jam' ], 'NEED: a goal is what it stands for') or diag explain $p->{goals};
	is_deeply([ map { $_->{name} } @{ $p->{goals} } ], [ 'default' ], '... and only the first goal is made without -t');
	is_deeply([ map { $_->{name} } @{ plan_of($dir, 'default,food')->{goals} } ], [ 'default', 'food' ], '... -t takes a list');
	is_deeply([ map { $_->[0] } @{ $p->{goals}[0]{dropped} } ], [ 'nothing' ], 'its WANT is the WANT of the goal');

	$p = plan_of($dir, 'WANT:default');
	is_deeply($p->{goals}[0]{files}, [ 'some bread', 'jam' ], 'selected as WANT');
}
{
	my $dir = project(MANIFEST => "MAKE a\nNEED b\nMAKE b\nNEED c\nMAKE c\nNEED a\n");
	like(failure($dir), qr/MANIFEST line 6: cyclic goal: a -> b -> c -> a/, 'a cycle');
	$dir = project(MANIFEST => "MAKE a\nNEED x\nMAKE b\nNEED c\nMAKE c\nNEED b\n");
	like(failure($dir), qr/line 6: cyclic goal: b -> c -> b/, 'a cycle, not through the first');
	$dir = project(MANIFEST => "MAKE a\nWANT a\n");
	like(failure($dir), qr/line 2: cyclic goal: a -> a/, 'a goal that wants itself');
}
{
	# a rule is a file as well: the goal `site/x' and the target site/x
	my $dir = project(MANIFEST => "MAKE site/x\nNEED x\nMAKE other\nNEED x\n");
	like(failure($dir), qr/`site\/x' is the name of a rule, and a file \(`site\/x'\) is as well/, 'a goal that is a file');
	is(failure($dir, 'other'), '', '... but a goal that is not selected is not a rule');
	$dir = project(MANIFEST => "MAKE clean-x\nNEED x\n");
	is(failure($dir), '', 'a goal with a dash and a letter is fine');
	$dir = project(MANIFEST => "MAKE all\nNEED x\n");
	my $p = plan_of($dir);
	is_deeply([ map { $_->{name} } @{ $p->{clean} } ], [ 'clean-all' ], 'a cleaning rule, and no clash');
}
{
	# a name in a header says a string, too
	my $dir = project(
		MANIFEST => "MAKE all\nNEED page\n",
		'Makefile.in' => "page dep file: \n\tcp \${a}/\${\@:Q} \${b}/\${\@:Q}\n",
		'html/page' => "# NEED: \${a}/\${\"dep\\sfile\"}\n",
		'html/dep file' => "dep\n",
	);
	is(failure($dir), '', 'a header NEED: ${"..."} is the file with a blank in it');
	unlink "$dir/html/dep file" or die $!;
	like(failure($dir), qr/NEEDs `html\/dep file'/, '... and is not found when it is gone');
}

done_testing;
