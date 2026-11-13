#!perl
#
# t/codesets.t - categories, how they are set, and what is got

use 5.008;
use strict;
use warnings;
use Test::More tests => 129;
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

# --- set: by canonical name; locale unsets
{
	my $cs = $CS->new(argv => 'UTF-8', env => 'latin1', filesys => 'locale', stdout => 'locale');
	is($cs->argv, 'utf-8-strict', 'argv: canonical name');
	is($cs->env, 'iso-8859-1', 'env: canonical name');
	is($cs->filesys, undef, 'filesys: locale is not set');
	is($cs->_encoding('filesys'), canon('locale_fs'), '... and is spelled as locale_fs');
	$cs->argv(undef);
	is($cs->argv, undef, 'undef unsets');
	ok(!eval { $CS->new(argv => 'no-such-thing'); 1 }, 'unknown encoding');
	like($@, qr/\Aunknown encoding "no-such-thing" for argv\n\z/, '... says so');
	ok(!eval { $CS->new(argh => 'UTF-8'); 1 }, 'unknown category');
	like($@, qr/\Aunknown category "argh"\n\z/, '... says so');
}

# --- what is got can be given to another category
{
	my $cs = $CS->new(argv => 'locale', stdout => 'latin1');
	$cs->stdout($cs->argv);
	is($cs->stdout, undef, 'stdout from argv: unset, as argv is');
	$cs = $CS->new(argv => 'ascii');
	$cs->stdout($cs->argv);
	is($cs->stdout, 'ascii', 'stdout from argv: as it is');
}

# --- all: sets everything, and returns a copy that parse takes
{
	my $cs = $CS->new(argv => 'UTF-8', stderr => 'ascii', diag => 'unicode');
	is_deeply($cs->all, { stdin => undef, stdout => undef, stderr => 'ascii',
		argv => 'utf-8-strict', env => undef, filesys => undef, diag => 'unicode' },
		'all: every category and diag, undef if not set');
	$cs->all->{argv} = 'ascii';
	is($cs->argv, 'utf-8-strict', '... a copy');
	my $other = $CS->new(env => 'latin1', filesys => 'latin1');
	is($other->parse($cs->all), $other, 'parse: of what all returns');
	is_deeply($other->all, $cs->all, '... makes it the same');
	is($other->diag_mode, 'unicode', '... diag set after stderr');
	is_deeply($CS->new->parse($cs->all)->all, $cs->all, '... of a new one too');
	$other = $CS->new(env => 'latin1', filesys => 'latin1');
	is_deeply($other->parse($cs)->all, $cs->all, 'parse: of another, the same');
	is_deeply($CS->new(env => 'latin1')->parse($cs, { prog => 'me' })->all, $cs->all, '... with options');
	ok(!eval { $other->parse([]); 1 } && $@ =~ /\Anot a codeset: ARRAY/, 'parse: not of any other reference');
	$other->parse('env:latin1', $cs->all, 'argv:ascii', { prog => 'me' });
	is_deeply([ $other->env, $other->argv ], [ undef, 'ascii' ], 'parse: all among specs, in order, with options');
	ok(!eval { $other->parse({ argv => 'UTF-8', argh => 'UTF-8' }, { prog => 'me' }); 1 }, 'parse: a hash with an unknown category');
	is($@, qq{me: unknown category "argh"\n}, '... says so');
	ok(!eval { $other->parse({ console => 'UTF-8' }); 1 }, 'parse: a hash that is not options, nor from all');
	like($@, qr/\Aparse: unknown option console at /, '... is options still');
	is_deeply($cs->all('latin1'), { (map { $_ => 'iso-8859-1' } qw( stdin stdout stderr argv env filesys )), diag => undef },
		'all: sets every category, and diag follows stderr again');
	ok(!eval { $cs->all('no-such-thing'); 1 }, 'all: unknown encoding');
	like($@, qr/\Aunknown encoding "no-such-thing" for stdin\n\z/, '... says so');
	is($cs->argv, 'iso-8859-1', '... leaving it as it was');
	is_deeply({ %{ $cs->all('locale') && $cs } }, {}, 'all: locale resets to new');
	is($cs->all(0)->{filesys}, 'ascii', 'all: 0 is ascii');
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
	my $cs = $CS->new->parse(qw( console:latin1 stderr:ascii argv filesys:locale diag:ascii ));
	is($cs->stdout, 'iso-8859-1', 'parse: console');
	is($cs->stderr, 'ascii', '... overridden later');
	is($cs->argv, 'utf-8-strict', '... omitted is UTF-8');
	is($cs->filesys, undef, '... locale is not set');
	is($cs->diag_mode, 'ascii', '... diag');
	$cs = $CS->new->parse(qw( stderr:ascii console:latin1 ));
	is($cs->stderr, 'iso-8859-1', 'parse: console overrides what came before');
	is($CS->new->parse('diag')->diag_mode, 'unicode', 'parse: diag alone is unicode');
	ok(!eval { $CS->new->parse(':UTF-8'); 1 }, 'parse: no category');
	like($@, qr/\Ano category in codeset ":UTF-8"\n\z/, '... says so');
}

# --- parse: commas, and an encoding alone
{
	my $cs = $CS->new->parse('filesys:UTF-8,console:ascii');
	is($cs->filesys, 'utf-8-strict', 'parse: commas');
	is($cs->console, 'ascii', '... all of them');
	is($cs->argv, undef, '... and nothing else');
	$cs = $CS->new->parse('latin1');
	is($cs->$_, 'iso-8859-1', "parse: an encoding alone sets $_") for qw( stdin stdout stderr argv env filesys );
	is($CS->new->parse('0')->filesys, 'ascii', 'parse: 0 is ascii');
	is($CS->new->parse('1')->filesys, 'utf-8-strict', 'parse: 1 is UTF-8');
	is($CS->new->parse('ANSI_X3.4-1968')->stderr, 'ascii', 'parse: ASCII by another name');
	is_deeply({ %{ $CS->new->parse('0')->parse('locale') } }, {}, 'parse: locale alone resets to new');
	is($CS->new->parse('console:0')->stdout, 'ascii', 'parse: 0 for a category');
	is($CS->new->parse('diag:0')->diag_mode, 'ascii', 'parse: diag:0');
	is($CS->new(diag => 1, stderr => 'ascii', diag => 1)->diag_mode, 'unicode', 'new: diag 1');
	is_deeply({ %{ $CS->new->parse('') } }, {}, 'parse: nothing');
	is_deeply({ %{ $CS->new->parse('argv,') } }, { argv => 'utf-8-strict' }, 'parse: a comma at the end');
	ok(!eval { $CS->new->parse('nope'); 1 }, 'parse: neither');
	like($@, qr/\Aunknown category or encoding "nope"\n\z/, '... says so');
	ok(!eval { $CS->new->parse('argv,,env'); 1 }, 'parse: nothing between commas');
}

# --- stderr in ASCII: diag too
{
	is($CS->new->parse('diag:unicode,stderr:ascii')->diag_mode, 'ascii', 'stderr:ascii sets diag');
	is($CS->new->parse('diag:unicode,console:ascii')->diag_mode, 'ascii', '... console:ascii');
	is($CS->new->parse('diag:unicode,console_out:US-ASCII')->diag_mode, 'ascii', '... console_out:US-ASCII');
	is($CS->new->parse('stderr:ascii,diag:unicode')->diag_mode, 'unicode', '... until told otherwise');
	is($CS->new->parse('stderr:UTF-8,diag:unicode,stdout:ascii')->diag_mode, 'unicode', '... stdout is not stderr');
	is($CS->new->parse('0')->diag_mode, 'ascii', '... 0');
	is($CS->new->parse('0,1')->diag_mode, 'unicode', '... all: diag follows stderr again');
	is($CS->new->parse('diag:ascii,all:UTF-8')->diag_mode, 'unicode', '... all:UTF-8');
}

# --- of an object: parse is the object itself, new is a copy
{
	my $base = $CS->new(argv => 'ascii');
	my $cs = $base->parse('filesys:latin1');
	is($cs, $base, 'parse: the object itself');
	is($cs->argv, 'ascii', '... with what it had');
	is($cs->filesys, 'iso-8859-1', '... and what it was told');
	ok(!eval { $base->parse('env:UTF-8,nope'); 1 }, 'parse: one bad spec');
	is($base->env, undef, '... the object left as it was');
	ok(!eval { $base->parse('nope', { prog => 'me' }); 1 }, 'parse: prog');
	is($@, qq{me: unknown category or encoding "nope"\n}, '... says who first');
	ok(!eval { $base->parse('argv:nope', { prog => 'me' }); 1 }, '... an unknown encoding');
	like($@, qr/\Ame: /, '... too');
	ok(!eval { $CS->parse('argv'); 1 }, 'parse: not of a class');
	$cs = $base->new(argv => 'UTF-8');
	is($cs->argv, 'utf-8-strict', 'new of an object: overrides');
	is($base->argv, 'ascii', '... the object left alone');
	isa_ok($cs, $CS);
}

# --- parse_from_env: of the object itself
{
	my $cs = $CS->new(argv => 'ascii');
	local $ENV{CS_TEST};
	delete $ENV{CS_TEST};
	is($cs->parse_from_env('CS_TEST'), $cs, 'parse_from_env: unset: the object');
	is($cs->argv, 'ascii', '... as it was');
	$ENV{CS_TEST} = 'filesys:latin1,stdout:0';
	is($cs->parse_from_env('CS_TEST', prog => 'E'), $cs, 'parse_from_env: the object');
	is($cs->filesys, 'iso-8859-1', '... told');
	is($cs->stdout, 'ascii', '... split by commas');
	is($cs->argv, 'ascii', '... over what it had');
	$ENV{CS_TEST} = 'stdin:UTF-8,nope';
	ok(!eval { $cs->parse_from_env('CS_TEST', prog => 'E'); 1 }, 'parse_from_env: nonsense');
	is($@, qq{E: CS_TEST: unknown category or encoding "nope"\n}, '... said, by prog and name');
	is($cs->stdin, undef, '... and nothing applied');
	ok(!eval { $cs->parse_from_env('CS_TEST'); 1 }, 'parse_from_env: no prog');
	is($@, qq{CS_TEST: unknown category or encoding "nope"\n}, '... said by name');
	ok(!eval { $cs->parse_from_env('CS_TEST', nope => 1); 1 }, 'parse_from_env: unknown option');
}

# --- parse_from_argv: the -C at the front, and how many
{
	my $cs = $CS->new;
	my @argv = ('-C', 'argv:ascii', '-C0', '-Cfilesys', '-i', '-C', 'stdin:UTF-8', 'x');
	is($cs->parse_from_argv(\@argv, prog => 'E'), 4, 'parse_from_argv: how many');
	is_deeply(\@argv, ['-i', '-C', 'stdin:UTF-8', 'x'], '... taken off, up to the first other');
	is($cs->argv, 'ascii', '... -C 0: all, after argv:ascii');
	is($cs->filesys, 'utf-8-strict', '... glued');
	is($cs->stdin, 'ascii', '... and none after');

	@argv = ('-iC0');
	is($CS->new->parse_from_argv(\@argv), 0, 'parse_from_argv: -iC0 is not ours');
	@argv = ('--', '-C0');
	is($CS->new->parse_from_argv(\@argv), 0, '... nor what comes after --');
	is_deeply(\@argv, ['--', '-C0'], '... which is left');

	$cs = $CS->new(argv => 'ascii');
	@argv = ('-C1', '-C', 'nope', 'x');
	ok(!eval { $cs->parse_from_argv(\@argv, prog => 'E'); 1 }, 'parse_from_argv: nonsense');
	is($@, qq{E: -C (argv 3): unknown category or encoding "nope"\n}, '... said, by prog and where');
	is_deeply([ $cs->argv, scalar @argv ], ['ascii', 4], '... and nothing applied or taken');
	@argv = ('-C1', '-C');
	ok(!eval { $cs->parse_from_argv(\@argv); 1 }, 'parse_from_argv: -C last');
	is($@, "-C (argv 2): no codeset after it\n", '... said, where');
	ok(!eval { $cs->parse_from_argv('-C0'); 1 }, 'parse_from_argv: not an array');
	ok(!eval { $CS->parse_from_argv([]); 1 }, '... nor of the class');
}

# --- the process's own
{
	isa_ok($CS->locale, $CS, 'locale: before it is set');
	my $cs = $CS->new(argv => 'ascii');
	is($CS->locale($cs), $cs, 'locale: set');
	is($CS->locale, $cs, '... and got');
}
