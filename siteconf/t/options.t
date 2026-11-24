#!perl
#
# t/options.t - -S of siteconf -g: the options of the generators

use strict;
use warnings;
use Test::More tests => 29;

use File::Path qw( make_path );
use File::Temp qw( tempdir );
use FindBin;
use lib "$FindBin::Bin/lib";
use TestPaths qw( script_path perl5lib );
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;
use RdKw::WwW::SiteConf::Builder::Make;
use RdKw::WwW::SiteConf::Builder::Gmake;

my $script = script_path();

my $plan = {
	prog => 'test', D => {}, clean => [],
	goals => [ { name => 'all', files => [ 'site/x/y' ] } ],
	dirs => [
		{ dir => 'site', marker => 'site/.ok', deps => [] },
		{ dir => 'site/x', marker => 'site/x/.ok', deps => [ 'site/.ok' ] },
	],
	order => [ 'site/x/y' ],
	node => { 'site/x/y' => { bpath => 'site/x/y', deps => [ 'html/y', 'site/x/.ok' ], recipe => [] } },
};
sub emit { my ($class, %opt) = @_; $class->_text({ %$plan, opt => \%opt }) }

# --- -Sorder
unlike(emit('RdKw::WwW::SiteConf::Builder::Make', order => 1), qr/ \| /, 'make has no bar, whatever is asked');
unlike(emit('RdKw::WwW::SiteConf::Builder::Make', order => 1), qr/ORDER/, 'and no .ORDER');
like(emit('RdKw::WwW::SiteConf::Builder::Gmake'), qr!^site/x/y: html/y site/x/\.ok$!m, 'gmake: by default a marker is a prerequisite');
for my $off ([ order => 0 ], [ order => '' ], [ order => undef ]) {
	my $v = defined $off->[1] ? "`$off->[1]'" : 'undef';
	like(emit('RdKw::WwW::SiteConf::Builder::Gmake', @$off), qr!^site/x/y: html/y site/x/\.ok$!m, "gmake: order=$v does nothing");
}
my $gmake = emit('RdKw::WwW::SiteConf::Builder::Gmake', order => 1);
like($gmake, qr!^site/x/y: html/y \| site/x/\.ok$!m, 'gmake -Sorder=1: a marker is after the bar');
like($gmake, qr!^site/x/\.ok: \| site/\.ok$!m, '... so is the marker of a parent');

# --- what a generator knows
is_deeply([ RdKw::WwW::SiteConf::Builder::Make->options ], [qw( clean purge arg_max )], 'make: clean, purge, arg_max');
is_deeply([ sort RdKw::WwW::SiteConf::Builder::Gmake->options ], [qw( arg_max clean order purge )], 'gmake: arg_max, clean, order, purge');

# --- generate: no rule unless asked for, and what is unused is said
my $dir = tempdir(CLEANUP => 1);
make_path("$dir/html", "$dir/MY");
for my $f (qw( x html/a.css )) { open my $fh, '>', "$dir/$f" or die; close $fh }
open my $fh, '>', "$dir/Makefile.in" or die;
print $fh "a.css: \${A}/x\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n";
close $fh or die;
open $fh, '>', "$dir/MANIFEST" or die; print $fh "MAKE all\n\tNEED a.css\n"; close $fh or die;
write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
	R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok' }, prog => 'test');

# (what is said to STDERR)
sub said
{
	my ($G, %arg) = @_;
	my $err = '';
	{
		local *STDERR;
		open STDERR, '>', \$err or die;
		RdKw::WwW::SiteConf->new(B => $dir, %arg)->generate($G);
	}
	$err;
}
like(said(q(make), S => { order => 1 }), qr/-Sorder=1: unused by generator make/, q(make does not know order));
unlike(said(q(make), S => { order => undef }), qr/unused/, q(but a name alone is not said));
unlike(said(q(make), S => { order => 1 }, quiet => 1), qr/unused/, q(-q silences it));
like(said('make', S => { frob => 1 }), qr/-Sfrob=1: unused by generator make/, 'nobody knows frob');
unlike(said('make', S => { clean => 'purge' }), qr/unused/, 'make knows clean');

# --- the generators: by name (Builder::Name), and what they may not be
sub gen_error { my ($G, $o) = @_; eval { RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->generate($G, $o); 1 } ? '' : $@ }
my $lib = tempdir(CLEANUP => 1);
make_path("$lib/RdKw/WwW/SiteConf/Builder");
sub backend { open my $fh, '>', "$lib/RdKw/WwW/SiteConf/Builder/$_[0].pm" or die; print $fh $_[1]; close $fh or die }
# one that is there, but broken; one that writes many files, in
# directories of their own; and one that -G cannot name
backend(Broken => "package RdKw::WwW::SiteConf::Builder::Broken; die qq(broken here\\n);\n");
backend(Many => <<'PM');
package RdKw::WwW::SiteConf::Builder::Many;
sub options { () }
sub default_output { undef }
sub emit { ([ 'd/e/one.do', "1\n" ], [ 'two.do', "2\n" ]) }
sub build_command { ('many') }
1;
PM
backend(Odd_one => "1;\n");
unshift @INC, $lib;

like(gen_error('Make'), qr/invalid generator name: `Make'$/, 'a name -G cannot have');
like(gen_error('foo-2x'), qr/invalid generator name: `foo-2x'/, 'a part of a name begins with a letter');
like(gen_error('nope'), qr/unknown generator: `nope' \(RdKw::WwW::SiteConf::Builder::Nope is not installed/,
	'a generator that is not installed');
# (others may be installed: ninja, redo, or one in the works)
my @gen = RdKw::WwW::SiteConf::generators();
is(join(' ', grep { /\A(?:bmake|broken|gmake|make|many|odd_one)\z/ } map { $_->[0] } @gen),
	'bmake broken gmake make many', 'the generators are those installed that -G can name');
is_deeply([ map { $_->[0] } @gen ], [ sort map { $_->[0] } @gen ], '... in order');
is((map { $_->[1] } grep { $_->[0] eq 'many' } @gen)[0], "$lib/RdKw/WwW/SiteConf/Builder/Many.pm", '... with the file of each');
like(gen_error('broken'), qr/broken here/, 'a broken generator is not said to be missing');
like(said('many'), qr/Writing d\/e\/one\.do\n.*Writing two\.do\n.*To build, run: many$/s, 'many files, and what to run');
ok(-f "$dir/d/e/one.do" && -f "$dir/two.do", '... are written, directories and all');
like(gen_error('many', 'x'), qr/generator many writes a file for each target, and cannot name them `x'/,
	'... and cannot be named');
# (update_file writes by way of a temporary file of its own, so a file
# called tmp-x.do is only that)
backend(Tmp => <<'PM');
package RdKw::WwW::SiteConf::Builder::Tmp;
sub options { () }
sub default_output { undef }
sub emit { ([ 'd/tmp-x.do', "1\n" ], [ 'd/x.do', "2\n" ]) }
sub build_command { ('tmp') }
1;
PM
is(gen_error("tmp") . join('', map { open my $fh, '<', "$dir/d/$_" or die; <$fh> } qw( tmp-x.do x.do )),
	"1\n2\n", 'x.do and tmp-x.do are each written');

# --- siteconf -VV lists the generators and the codesets; -VVV where
# each generator is
{
	local $ENV{PERL5LIB} = join ':', $lib, perl5lib();
	my $vv = `"$^X" "$script" -VV 2>&1`;
	like($vv, qr/^generator make\ngenerator many$/m, '-VV: the generators');
	like($vv, qr/^argv:\S* env:\S* filesys:/m, '... and the codesets');
	like(`"$^X" "$script" -VVV 2>&1`, qr/^generator many "\Q$lib\E\/RdKw\/WwW\/SiteConf\/Builder\/Many\.pm"$/m,
		'-VVV: where each generator is');
}
