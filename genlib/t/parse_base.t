#!perl
#
# t/parse_base.t - MY/*.mk, HAVE/NEED/WANT headers, base_url, TT2 stash

use 5.006;
use strict;
use warnings;
use utf8;
use Test::More tests => 7;
use File::Temp qw( tempdir );

use RdKw::WwW::GenLib qw( parse_base );

# --- parse_base
{
	my %O = (site_url => 'https://example.test/x?y#z', base_url => '/');
	ok(eval { parse_base(\%O); 1 }, 'inherits path') or diag $@;
	is($O{base_url}, '/x', 'base_url inherited');
	is($O{site_url}, 'https://example.test', 'site_url is host only');
	ok(!ref $O{site_url}, 'site_url is a plain string');

	%O = (site_url => 'https://example.test/x/', base_url => '/y/');
	ok(!eval { parse_base(\%O); 1 }, 'path in site_url vs. base_url');
	%O = (site_url => 'ftp://example.test');
	ok(!eval { parse_base(\%O); 1 }, 'scheme');
	%O = (base_url => '/');
	ok(!eval { parse_base(\%O); 1 }, 'missing site_url');
}
