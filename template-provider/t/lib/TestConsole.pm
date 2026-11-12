package TestConsole;

use strict;
use warnings;
use Test::More ();

# Use locale encoding for wide-characters, since console
# output/error is often meant for humans and not machine-
# consumable.  Fall back to ASCII \x{...} when a Unicode
# character cannot be encoded, however.
{
	require Encode;
	require Encode::Locale;
	require PerlIO::encoding;
	local $PerlIO::encoding::fallback = Encode::PERLQQ();
	my $tb = Test::More->builder;
	binmode $tb->$_, ':encoding(console_out)' for qw( output failure_output todo_output );
}

# What gengenlib says is said as it is written, whatever the locale
# and whatever catalogs are installed.
$ENV{LANGUAGE} = 'C';

1;
