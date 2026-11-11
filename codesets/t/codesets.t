#!perl
#
# t/codesets.t - categories, how they are set, and what is got

use 5.008;
use strict;
use warnings;
use Test::More tests => 40;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;
use Encode ();
use Encode::Locale ();

use RdKw::I18N::CodeSets;
my $CS = 'RdKw::I18N::CodeSets';

sub canon { Encode::find_encoding($_[0])->name }

# --- unset is undef
{
	my $cs = $CS->new;
	is($cs->$_, undef, "new: $_ is not set") for qw( stdin stdout stderr argv env filesys );
	is($cs->console, undef, '... nor console');
}

# --- set: by canonical name, and locale per category
{
	my $cs = $CS->new(argv => 'UTF-8', env => 'latin1', filesys => 'locale', stdout => 'locale');
	is($cs->argv, 'utf-8-strict', 'argv: canonical name');
	is($cs->env, 'iso-8859-1', 'env: canonical name');
	is($cs->filesys, canon('locale_fs'), 'filesys: locale is locale_fs');
	is($cs->stdout, canon('console_out'), 'stdout: locale is console_out');
	$cs->argv(undef);
	is($cs->argv, undef, 'undef unsets');
	ok(!eval { $CS->new(argv => 'no-such-thing'); 1 }, 'unknown encoding');
	like($@, qr/\Aunknown encoding "no-such-thing" for argv\n\z/, '... says so');
	ok(!eval { $CS->new(argh => 'UTF-8'); 1 }, 'unknown category');
	like($@, qr/\Aunknown category "argh"\n\z/, '... says so');
}

# --- what is got can be given to another category
{
	my $cs = $CS->new(argv => 'locale');
	$cs->stdout($cs->argv) if !defined $cs->stdout;
	is($cs->stdout, canon('locale'), 'stdout from argv: locale of argv');
	$cs = $CS->new(argv => 'ascii');
	$cs->stdout($cs->argv);
	is($cs->stdout, 'ascii', 'stdout from argv: as it is');
}

# --- new: in order, as parse
{
	my $cs = $CS->new(stderr => 'ascii', console => 'latin1');
	is($cs->stderr, 'iso-8859-1', 'new: console overrides what came before');
	$cs = $CS->new(console => 'latin1', stderr => 'ascii');
	is($cs->stdin, 'iso-8859-1', 'new: console sets stdin');
	is($cs->stdout, 'iso-8859-1', '... and stdout');
	is($cs->stderr, 'ascii', '... but stderr is set apart later');
	is($cs->console, undef, 'console: not all the same');
	is($cs->console_in, 'iso-8859-1', 'console_in: stdin');
	$cs = $CS->new(console => 'latin1', console_out => 'ascii');
	is($cs->stdout, 'ascii', 'new: console_out after console');
	is($cs->stdin, 'iso-8859-1', '... console_in left alone');
	$cs->console('UTF-8');
	is($cs->console, 'utf-8-strict', 'console: sets them all');
	ok(!eval { $CS->new('argv'); 1 }, 'new: odd number of arguments');
}

# --- parse: in order, UTF-8 if omitted
{
	my $cs = $CS->parse(qw( console:latin1 stderr:ascii argv filesys:locale diag:ascii ));
	is($cs->stdout, 'iso-8859-1', 'parse: console');
	is($cs->stderr, 'ascii', '... overridden later');
	is($cs->argv, 'utf-8-strict', '... omitted is UTF-8');
	is($cs->filesys, canon('locale_fs'), '... locale');
	is($cs->diag_mode, 'ascii', '... diag');
	$cs = $CS->parse(qw( stderr:ascii console:latin1 ));
	is($cs->stderr, 'iso-8859-1', 'parse: console overrides what came before');
	is($CS->parse('diag')->diag_mode, 'unicode', 'parse: diag alone is unicode');
	ok(!eval { $CS->parse(':UTF-8'); 1 }, 'parse: no category');
	like($@, qr/\Ano category in codeset ":UTF-8"\n\z/, '... says so');
}

# --- the process's own
{
	isa_ok($CS->locale, $CS, 'locale: before it is set');
	my $cs = $CS->new(argv => 'ascii');
	is($CS->locale($cs), $cs, 'locale: set');
	is($CS->locale, $cs, '... and got');
}
