#!perl
#
# t/path.t - path manip, enroot and uproot

use 5.006;
use strict;
use warnings;
use Test::More tests => 24;

use RdKw::WwW::GenGenLib qw(enroot uproot);

is(enroot('site', ''), 'site/', 'affix trailing slash for empty file component');
is(enroot('site', '', ''), 'site/', 'affixation is idempotent');
is(enroot('site'), 'site/', 'affixation is unconditional');

is(enroot('site', '.'), 'site/.', '. is literal');
is(enroot('site', './'), 'site/./', './ is literal');
is(enroot('site/', '.'), 'site/.', 'one leading slash is okay');
is(enroot('site//', '.'), 'site//.', 'two leading slashes is not');
is(enroot('site', '/'), 'site//', 'literal concatenation');

is(uproot('site', 'site'), '');
is(uproot('site', 'site/'), '');
is(uproot('site', 'site/.'), '.');
is(uproot('site', 'site/./'), './');
is(uproot('site', 'site//'), '/');
is(uproot('site', 'site///'), '//');

is(uproot('site/', 'site'), '');
is(uproot('site/', 'site/'), '');
is(uproot('site/', 'site/.'), '.');
is(uproot('site/', 'site/./'), './');
is(uproot('site/', 'site//'), '/');
is(uproot('site/', 'site///'), '//');

is(uproot('site//', 'site'), undef);
is(uproot('site//', 'site/'), '');
is(uproot('site//', 'site//'), '');
is(uproot('site//', 'site///'), '/');

done_testing;
