#!perl
#
# t/make.t - make file serialization and MY/*.mk state tests

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 14;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use File::Temp qw( tempdir );

use RdKw::WwW::GenGenLib qw(
	read_make write_make update_file
	load_state
);

my $dir = tempdir(CLEANUP => 1);

# --- write_make / read_make / update_file
{
	my $f = "$dir/x.mk";
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'==', 2, 'write_make creates');
	is_deeply({ read_make($f) }, { b => 'site', aa => 'a b', c => 'é' },
		'read_make reads it back');
	like(do { open my $fh, '<', $f; local $/; <$fh> }, qr/^b=\tsite\nc=.*\naa=/m,
		'short keys first');

	# Preserve the mtime of an unchanged file.
	utime 1000000000, 1000000000, $f;
	cmp_ok(write_make($f, { b => 'site', aa => 'a b', c => 'é' }, 'test'),
		'==', 0, 'unchanged');
	is((stat $f)[9], 1000000000, 'mtime kept');
	cmp_ok(write_make($f, { b => 'docs' }, 'test'),
		'==', 1, 'changed');
	ok(!-e "$dir/tmp-x.mk", 'no temporary left behind');
	ok(!eval { write_make($f, { k => "a\nb" }, 'test'); 1 }, 'newline refused');
	ok(!eval { write_make($f, { 'a=b' => 1 }, 'test'); 1 }, 'bad name refused');
}

# --- load_state
{
	mkdir "$dir/MY" or die;
	ok(!eval { load_state($dir); 1 }, 'unconfigured');
	like($@, qr/not configured/, '... says so');
	write_make("$dir/MY/config.mk", { a => 'html' }, 't');
	write_make("$dir/MY/option.mk", { base_url => '/' }, 't');
	my ($D, $O) = @{+{ load_state($dir) }}{ qw(config option) };
	is($D->{a}, 'html', 'D from config.mk');
	is($O->{base_url}, '/', 'O from option.mk');
	ok(!exists $D->{base_url}, 'namespaces are separate');
}
