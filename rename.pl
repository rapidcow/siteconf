#!/usr/bin/env perl
# usage: perl rename.pl [-n] < rebase.txt
#
# Run this inside the notes checkout (the one with files named by
# 40-digit commit hashes).  For every such file, rewrite each commit
# hash mentioned in its contents, then rename the file itself if its
# own commit was rewritten.  -n only reports what would happen.

use 5.010;
use strict;
use warnings;

my $dry = @ARGV && $ARGV[0] eq '-n';

my %REPLACE;
while (<STDIN>) {
	$REPLACE{$1} = $2 if /^REPLACE ([0-9a-f]{40}) WITH ([0-9a-f]{40})$/;
}
die "no REPLACE lines on stdin; did you forget < rebase.txt?\n" unless %REPLACE;

opendir my $dh, '.' or die "opendir: $!\n";
my @files = sort grep { /\A[0-9a-f]{40}\z/ && -f } readdir $dh;
closedir $dh;

foreach my $name (@files) {
	open my $in, '<:raw', $name or die "$name: $!\n";
	my $content = do { local $/; <$in> };
	close $in;
	$content //= '';

	my $count = 0;
	(my $new = $content) =~ s{(?<![0-9a-f])([0-9a-f]{40})(?![0-9a-f])}{
		exists $REPLACE{$1} ? do { $count++; $REPLACE{$1} } : $1
	}ge;

	my $target = $REPLACE{$name} // $name;
	die "$name: $target already exists\n" if $target ne $name && -e $target;

	say "$name: $count hash(es) updated",
		($target ne $name ? ", renamed to $target" : ".");
	next if $dry;

	if ($new ne $content) {
		open my $out, '>:raw', $name or die "$name: $!\n";
		print { $out } $new or die "$name: write: $!\n";
		close $out or die "$name: close: $!\n";
	}
	if ($target ne $name) {
		rename $name, $target or die "rename $name: $!\n";
	}
}
