#!perl
#
# t/parse_base.t - MY/*.mk, HAVE/NEED/WANT headers, base_url, TT2 stash

use utf8;
use 5.006;
use strict;
use warnings;
use Test::More tests => 11;

use File::Temp qw( tempdir );

use RdKw::WwW::GenLib qw( parse_base );

# --- parse_base
{
	my %O = (site_url => 'https://example.test/x?y#z', base_url => '/');
	ok(eval { parse_base(\%O); 1; }, 'inherits path') or diag $@;
	is($O{base_url}, '/x', 'base_url inherited');
	is($O{site_url}, 'https://example.test', 'site_url is host only');
	ok(!ref $O{site_url}, 'site_url is a plain string');

	%O = (site_url => 'https://example.test/x/', base_url => '/y/');
	ok(!eval { parse_base(\%O); 1; }, 'path in site_url vs. base_url');
	%O = (site_url => 'example.test', base_url => '/');
	ok(!eval { parse_base(\%O); 1; }, 'no scheme');
	%O = (site_url => 'gemini://example.test', base_url => '/');
	ok(eval { parse_base(\%O); 1; }, 'non-www scheme') or diag $@;
	is($O{site_url}, 'gemini://example.test', 'non-www site_url');
	%O = (base_url => '/');
	ok(!eval { parse_base(\%O); 1; }, 'missing site_url');
	like($@, qr/\Aparse_base: /, 'default prog');
	%O = (base_url => '/');
	eval { parse_base(\%O, prog => 'E'); 1; };
	like($@, qr/\AE: [^\n]*\n\z/, 'prog says the prefix');
}
