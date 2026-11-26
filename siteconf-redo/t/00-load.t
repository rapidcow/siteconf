#!perl
#
# t/00-load.t - basic load

use 5.008;
use strict;
use warnings;
use Test::More tests => 2;
use FindBin;
use lib "$FindBin::Bin/lib";
use Tools qw( describe redo_cmd redo_path redo_sh );

BEGIN { use_ok('RdKw::WwW::SiteConf::Builder::Redo') or BAIL_OUT }
is($RdKw::WwW::SiteConf::Builder::Redo::VERSION, $RdKw::WwW::SiteConf::VERSION,
	'the version of siteconf');
diag( "Testing RdKw::WwW::SiteConf::Builder::Redo $RdKw::WwW::SiteConf::Builder::Redo::VERSION, Perl $], $^X" );
# (the programs that t/e2e-redo.t runs: redo, and what a .do runs)
diag( describe(q(redo ($REDO)), redo_cmd()) );
redo_path();
diag( describe(q(redo-ifchange (next to redo)), q(redo-ifchange)) );
# (the #! of a .do; the kernel finds its first word)
my $sh = redo_sh() || q(/bin/sh);
diag( describe(q(sh ($REDO_SH)), $sh) . ($sh =~ /\s/ ? qq(, as in: $sh) : q()) );
