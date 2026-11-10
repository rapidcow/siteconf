#!perl
#
# t/provider.t - what is loaded is what is declared

use 5.008;
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use Cwd qw( getcwd );

eval { require Template; 1 } or plan skip_all => 'Template is not installed';
require RdKw::WwW::GenGenLib::Template::Provider;
Template::Constants->import(qw( STATUS_ERROR STATUS_DECLINED ));
my $P = 'RdKw::WwW::GenGenLib::Template::Provider';

my $cwd = getcwd();
my $dir = tempdir(CLEANUP => 1);
chdir $dir or die $!;
mkdir $_ or die $! for qw( site include B B/public );

sub spew
{
	my ($path, $text) = @_;
	open my $fh, '>:encoding(UTF-8)', $path or die "$path: $!";
	print $fh $text;
	close $fh or die $!;
}

my %D = ( A => '../..', B => 'B', a => 'site', b => 'public', c => 'public', inc => 'include' );
sub provider
{
	$P->new({ SOURCE => 'entry', INCLUDE_PATH => [qw( site include )],
		D => \%D, ENCODING => 'UTF-8', @_ });
}

# Process site/entry, with these header lines and this body
sub render
{
	my ($headers, $body, $vars, @opt) = @_;
	spew('site/entry', "[%#\n# HAVE: \${a}/entry\n$headers-%]\n$body");
	my $p = eval { provider(@opt) } or return (undef, undef, $@);
	my $tt = Template->new({ LOAD_TEMPLATES => [ $p ] });
	my $out = '';
	my $ok = $tt->process('entry', $vars || {}, \$out);
	($ok, $out, $ok ? undef : $tt->error());
}

spew('include/allowed', 'allowed');
spew('include/secret', 'secret');

my ($ok, $out, $err) = render("# NEED: \${inc}/allowed\n", '[% INCLUDE allowed %]');
ok($ok, 'declared INCLUDE works') or diag $err;
is($out, 'allowed', 'the header is not output');

($ok, $out) = render("# NEED: include/allowed\n", '[% INCLUDE allowed %]');
ok($ok, 'declared by any spelling (here, literally)');

for my $directive (qw( INCLUDE PROCESS WRAPPER INSERT )) {
	my $body = "[% $directive secret %]";
	$body .= '[% END %]' if $directive eq 'WRAPPER';
	($ok, $out, $err) = render('', $body);
	ok(!$ok, "$directive: an undeclared file is refused");
	like("$err", qr/undeclared dependency `include\/secret'/, '... by name');
}

($ok, $out) = render('', '[% BLOCK local %]local[% END %][% INCLUDE local %]');
is($out, 'local', 'a local BLOCK needs no declaration');

($ok, $out) = render("# NEED: \${inc}/allowed\n", '[% INCLUDE $x %]', { x => 'allowed' });
is($out, 'allowed', 'nor does a name chosen when processing, if it is declared');
($ok, $out, $err) = render('', '[% INCLUDE $x %]', { x => 'secret' });
ok(!$ok, '... and it is refused if not');

($ok, $out, $err) = render("# WANT: \${inc}/absent\n", 'fine');
is($out, 'fine', 'a WANT that is not there is fine, unused');
($ok, $out, $err) = render("# WANT: \${inc}/absent\n", '[% INCLUDE absent %]');
like("$err", qr/absent: not found/, '... and not found, used');

# --- deep: what the declared declare is declared, too
spew('include/outer', "[%# NEED: \${inc}/secret -%]\n[% INCLUDE secret %]");
($ok, $out, $err) = render("# NEED: \${inc}/outer\n", '[% INCLUDE outer %]');
is($out, 'secret', 'what an INCLUDE declares, it may INCLUDE') or diag $err;
spew('include/outer', '[% INCLUDE secret %]');
($ok, $out, $err) = render("# NEED: \${inc}/outer\n", '[% INCLUDE outer %]');
like("$err", qr/undeclared dependency `include\/secret'/, '... but nothing else');
($ok, $out, $err) = render("# NEED: \${inc}/outer \${inc}/secret\n", '[% INCLUDE outer %]');
is($out, 'secret', 'the source may declare it for it');

# what is built is declared, but not followed
mkdir 'B/public/gen' or die;
spew('B/public/gen/x', "[%# NEED: \${inc}/secret -%]\n");
spew('site/entry', "[%#\n# NEED: \${B}/\${b}/gen/x\n-%]\n");
my $p = provider();
ok($p->{ALLOWED}{'B/public/gen/x'} && !$p->{ALLOWED}{'include/secret'},
	'what is built is declared, and not followed');

# --- shallow: nothing is read, and anything is loaded
($ok, $out, $err) = render('', '[% INCLUDE secret %]', {}, CHECK_DEPS => 0);
is($out, 'secret', 'CHECK_DEPS => 0: anything goes') or diag $err;
spew('site/entry', "[%#\n# HAVE: elsewhere\n# NEED: \${nope}/x\n-%]\n");
ok(eval { provider(CHECK_DEPS => 0) }, '... and no header is read') or diag $@;

# --- what a header may say
spew('site/entry', "[%#\n# HAVE: elsewhere\n-%]\n");
ok(eval { provider() }, 'HAVE is not ours to check') or diag $@;
ok(!eval { provider(CHECK_HAVE => 1) }, '... unless CHECK_HAVE');
like($@, qr/HAVE `elsewhere', but it is `site\/entry'/, '... which says so');
ok(!eval { provider(CHECK_HAVE => 1, CHECK_DEPS => 0) }, '... shallow, too');
spew('site/entry', "[%#\n# HAVE: \${A}/site/entry\n-%]\n");
ok(eval { provider(CHECK_HAVE => 1) }, '... by any spelling') or diag $@;
spew('site/entry', "x\n");
ok(!eval { provider(CHECK_HAVE => 1) }, '... and a HAVE there must be');
spew('site/entry', "[%#\n# NEED: \${nope}/x\n-%]\n");
ok(!eval { provider() }, 'an undefined variable is an error');
like($@, qr/no such variable \$\{nope\}/, '... and says so');
spew('include/hidden', "[%# NEED: \${nope}/x -%]\n");
spew('site/entry', "[%#\n# NEED: \${inc}/hidden\n-%]\n");
ok(!eval { provider() }, '... further down, too');
ok(!eval { $P->new({ SOURCE => 'entry', COMPILE_DIR => 'c' }) }, 'COMPILE_DIR is refused');
ok(!eval { $P->new({ INCLUDE_PATH => ['site'] }) }, 'SOURCE is required');
ok(!eval { $P->new({ SOURCE => 'nowhere', INCLUDE_PATH => ['site'] }) }, 'and must be found');

# --- names, and the cache
spew('site/entry', "[%#\n# NEED: \${inc}/allowed\n-%]\n");
$p = provider();
my ($data, $status) = $p->fetch('allowed');
ok(!$status, 'fetch') or diag $data;
delete $p->{ALLOWED}{'include/allowed'};
($data, $status) = $p->fetch('allowed');
is($status, STATUS_ERROR(), 'a cached template is still checked');
for my $name ('../include/allowed', "$dir/include/allowed", './allowed', 'x/../allowed') {
	($data, $status) = $p->fetch($name);
	is($status, STATUS_ERROR(), "no other name: $name");
}
($data, $status) = $p->fetch('ghost');
is($status, STATUS_DECLINED(), 'what is not there is declined');

spew('site/allowed', 'shadow');
$p = provider();
($data, $status) = $p->fetch('allowed');
is($status, STATUS_ERROR(), 'an undeclared namesake earlier in the path is not skipped');
like($data, qr/undeclared dependency `site\/allowed'/, '... and named');
unlink 'site/allowed';

# --- ENCODING reaches the provider (Template's own does not)
spew('include/allowed', "caf\x{e9}");
($ok, $out) = render("# NEED: \${inc}/allowed\n", '[% INCLUDE allowed %]');
is($out, "caf\x{e9}", 'decoded as UTF-8');

chdir $cwd or die $!;
done_testing;
