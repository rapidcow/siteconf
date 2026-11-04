#!perl
#
# t/deps.t - dependency graph

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 13;
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw( read_deps );

my $dir = tempdir(CLEANUP => 1);
sub spew {
	my ($name, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
	print $fh $text;
	close $fh or die;
	"$dir/$name";
}

# --- read_deps
{
	my $f = spew('a.html', <<'HTML');
[%
# HAVE: index.html
# NEED: skel/HTML skel/FOOT
# WANT: data/x
# NEED: more
-%]
# NEED: ignored, this is body text
HTML
	is_deeply({ read_deps($f) }, {
		HAVE => 'index.html',
		NEED => [qw( skel/HTML skel/FOOT more )],
		WANT => [qw( data/x )],
	}, 'TT2 header');

	$f = spew('b.css', "/*\n * HAVE: b.css\n * NEED: c.css\n */\n");
	is_deeply({ read_deps($f) }, { HAVE => 'b.css', NEED => ['c.css'] },
		'C comment header (several lines)');

	$f = spew('c.bin', "binary\n" . ("x\n" x 40) . "# HAVE: too-late\n");
	is_deeply({ read_deps($f) }, {}, 'no header, no peeking far down');

	{
		open my $fh, '>:raw', "$dir/e.png" or die;
		print $fh "\x89PNG\r\n\x1a\n\0\xff\xfe\n# HAVE: nope\n" x 3;
		close $fh or die;
		my @w; local $SIG{__WARN__} = sub { push @w, @_ };
		is_deeply({ read_deps("$dir/e.png") }, {}, 'binary: no header');
		is_deeply(\@w, [], '... and no warnings');
	}

	$f = spew('d', "# HAVE: a\n# HAVE: b\n");
	ok(!eval { read_deps($f); 1 }, 'two HAVEs');
	like($@, qr/HAVE too many/, '... too many');
}

# --- read_deps: BASIC and DOS
{
	for my $head ("REM HAVE: a\nREM NEED: b\n", "rem HAVE: a\nrem NEED: b\n",
		"\@REM HAVE: a\n\@REM NEED: b\n", ":: HAVE: a\n:: NEED: b\n",
		"' HAVE: a\n' NEED: b\n") {
		my $f = spew('rem', "\@echo off\n$head\necho hi\n");
		is_deeply({ read_deps($f) }, { HAVE => 'a', NEED => ['b'] },
			'header in ' . (split ' ', $head)[0]);
	}
	my $f = spew('remark', "REMEMBER HAVE: a\n");
	is_deeply({ read_deps($f) }, {}, 'REM is a word');
}
