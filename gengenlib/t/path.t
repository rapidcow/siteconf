#!perl
#
# t/path.t - path manip, enroot and uproot

use 5.006;
use strict;
use warnings;
use Test::More tests => 46;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestConsole;

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

# Preserve identity
foreach my $ident ('', '.') {
	is(uproot($ident, 'index.html'), 'index.html');
	is(uproot($ident, '../secret'), '../secret');
	is(uproot($ident, '/etc/passwd'), undef, 'no way for identity to become absolute');
}

# The leading slash belongs to the root
is(uproot('/', '/etc'), 'etc');
is(uproot('/', '/'), '');
is(uproot('/', '//x'), '/x');
is(uproot('/', 'etc'), undef);
is(uproot('/', ''), undef);
is(uproot('/prefix', 'prefix'), undef);
is(uproot('prefix', '/prefix'), undef);
is(uproot('/prefix', '/prefix/x'), 'x');
is(uproot('a', 'a//x'), '/x');

is(enroot('', '/etc'), './/etc', "empty base is effectively a dot on absolute paths");
is(enroot('.', '/etc'), './/etc', "same");
is(enroot('', 'etc'), 'etc', "slash is omitted on relative paths");
is(enroot('.', 'etc'), 'etc', "same");
is(enroot('', ''), '', "idempotence");
is(enroot('.', ''), '', "idempotence with dot");
is(enroot('.', '.'), '.', "last dot remains dot?");
