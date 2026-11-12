package TestConsole;

use strict;
use warnings;
use Test::More ();

# What Test::More says (names, and got and expected when a test fails)
# is said as the locale says, with \x{...} where it cannot, as siteconf
# says it.  It prints to its own handles, not to STDOUT and STDERR.
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
