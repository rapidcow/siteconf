#!perl
#
# t/render.t - the web preset's renderer, as siteconf init writes it:
# how it finds its own place in the source tree (HAVE vs ${a})

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( project_root script_path perl5lib );
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::GenLib ();

for my $m (qw( Template )) {
	eval "require $m; 1" or plan skip_all => "$m is not installed";
}
my $script = script_path();
plan tests => 26;
# The preset comes from the built share (not from an installed one, which
# is what File::ShareDir would find if the build is not in front)
local $ENV{PERL5LIB} = join ':', project_root() . '/blib/lib', perl5lib();

my $tmp = tempdir(CLEANUP => 1);
chdir $tmp or die $!;
make_path('project/bin', 'B/MY');

sub slurp {
	open my $fh, '<', $_[0] or die "$_[0]: $!";
	local $/; <$fh>;
}
sub spew {
	my ($name, $text) = @_;
	(my $d = $name) =~ s{/[^/]*\z}{};
	make_path($d) if $d ne $name;
	open my $fh, '>', $name or die "$name: $!";
	print $fh $text;
	close $fh or die;
}

# Write the renderer the way anybody gets one
{
	open my $fh, '-|' or do {
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, $script, 'init', '-P', 'web', '-SA=project',
			'-o', 'render:bin/render-page',
			'-M', "RdKw::WwW::GenLib=$RdKw::WwW::GenLib::VERSION";
		die "exec: $!";
	};
	my $out = do { local $/; <$fh> };
	close $fh;
	ok($? == 0 && -f 'project/bin/render-page', 'siteconf init writes the renderer')
		or BAIL_OUT("init failed:\n$out");
}
spew('B/MY/option.mk', '');

# Render project/$file, whose header HAVEs $have, with ${a} set to $a
# (and whatever else in %D).  Returns (exit status, output or error).
sub render {
	my ($a, $have, $file, %D) = @_;
	write_make('B/MY/config.mk', {
		A => '.', B => '../B', a => $a, b => 'public', c => 'public',
		R => 'Makefile.in', F => 'MANIFEST', e => '.ok', %D }, 'test');
	my $header = defined $have ? "[%\n# HAVE: $have\n-%]\n" : '';
	spew("project/$file", $header . "[% location %]|[% locate('y.html') %]\n");
	unlink 'project/out.html';
	open my $fh, '-|' or do {
		chdir 'project' or die $!;
		open STDERR, '>&', STDOUT or die $!;
		exec $^X, 'bin/render-page', '-B', "$tmp/B", $file, 'out.html';
		die "exec: $!";
	};
	my $err = do { local $/; <$fh> };
	close $fh;
	my $status = $? >> 8;
	return ($status, $status ? $err : slurp('project/out.html'));
}

# A page that says where it is, however it spells it:
# the location is what is left after ${a}
for my $case (
	[ 'src', '${a}/x.html',         'src/x.html',     "x.html|y.html\n",        'braced ${a}' ],
	[ 'src', '${a}/art/x.html',     'src/art/x.html', "art/x.html|../y.html\n", 'in a directory' ],
	[ 'src', '$a/x.html',           'src/x.html',     "x.html|y.html\n",        'bare $a' ],
	[ 'src', 'src/x.html',          'src/x.html',     "x.html|y.html\n",        'literal prefix' ],
	[ 'src', '${A}/${a}/x.html',    'src/x.html',     "x.html|y.html\n",        '${A}/ in front' ],
	[ 'src', '${a}//x.html',        'src/x.html',     "x.html|y.html\n",        'a doubled slash does not leave a leading one' ],
	[ 'src/', '${a}/x.html',        'src/x.html',     "x.html|y.html\n",        'trailing slash in ${a}' ],
	[ 'src/', 'src/x.html',         'src/x.html',     "x.html|y.html\n",        '... and in a literal prefix' ],
	[ '.',   'x.html',              'x.html',         "x.html|y.html\n",        'a is `.\': bare name' ],
	[ '.',   '${a}/art/x.html',     'art/x.html',     "art/x.html|../y.html\n", 'a is `.\': ${a}/' ],
	[ '.',   '${A}/art/x.html',     'art/x.html',     "art/x.html|../y.html\n", 'a is `.\': ${A}/' ],
) {
	my ($a, $have, $file, $want, $name) = @$case;
	my ($status, $got) = render($a, $have, $file);
	is($got, $want, "HAVE $have, a = `$a': $name") or diag "(exit $status)";
}

# another variable of the configuration is expanded too
{
	my ($status, $got) = render('src', '${a}/${sub}/x.html', 'src/art/x.html', sub => 'art');
	is($got, "art/x.html|../y.html\n", 'a configured variable inside HAVE');
}

# a page that is not under ${a} is refused, saying why
{
	my ($status, $err) = render('src', 'other/x.html', 'src/x.html');
	isnt($status, 0, 'not under ${a}: fails');
	like($err, qr/HAVE `other\/x\.html' not under \$\{a\} \(which is `src'\)/, '... and says so');

	($status, $err) = render('src', '${b}/x.html', 'src/x.html');
	isnt($status, 0, 'HAVE in another variable: fails');
	like($err, qr/not under \$\{a\}/, '... and says so');

	($status, $err) = render('src', '${a}/x.html', 'src/x.html', a => 'src');
	is($status, 0, 'sanity: a good one still works');

	($status, $err) = render('src', undef, 'src/x.html');
	isnt($status, 0, 'no HAVE: fails');
	like($err, qr/HAVE declaration not found/, '... and says so');

	# a stray dollar sign is not a variable (and is not dropped)
	($status, $err) = render('src', '${a}/x$.html', 'src/x$.html');
	is($err, "x\$.html|y.html\n", 'a stray dollar sign in HAVE is a literal one');
}

# what is under ${a} is what a page may `locate' relative to
{
	my ($status, $got) = render('src', '${a}/art/deep/x.html', 'src/art/deep/x.html');
	is($got, "art/deep/x.html|../../y.html\n", 'location is relative to the page, however deep');
}

# the renderer is stateless between runs of different ${a}
{
	my ($s1, $o1) = render('one', '${a}/x.html', 'one/x.html');
	my ($s2, $o2) = render('two', '${a}/x.html', 'two/x.html');
	is($o1, $o2, 'same page, different a: same location');
	like($o1, qr/\Ax\.html\|/, '... that is relative to a');
}

# the page is the thing that is rendered: the output is the file's own text
{
	my ($status, $got) = render('src', '${a}/x.html', 'src/x.html');
	unlike($got, qr/HAVE/, 'the header is not in the output (it is a TT comment)');
	is(scalar(() = $got =~ /\n/g), 1, '... and only the one line is');
}
