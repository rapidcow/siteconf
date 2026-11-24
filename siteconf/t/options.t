#!perl
#
# t/options.t - -S of siteconf -g: the options of the generators

use strict;
use warnings;
use Test::More tests => 23;

use File::Path qw( make_path );
use File::Temp qw( tempdir );
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;
use RdKw::WwW::SiteConf::Backend::Make;
use RdKw::WwW::SiteConf::Backend::Gmake;

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
unlike(emit('RdKw::WwW::SiteConf::Backend::Make', order => 1), qr/ \| /, 'make has no bar, whatever is asked');
unlike(emit('RdKw::WwW::SiteConf::Backend::Make', order => 1), qr/ORDER/, 'and no .ORDER');
like(emit('RdKw::WwW::SiteConf::Backend::Gmake'), qr!^site/x/y: html/y site/x/\.ok$!m, 'gmake: by default a marker is a prerequisite');
for my $off ([ order => 0 ], [ order => '' ], [ order => undef ]) {
	my $v = defined $off->[1] ? "`$off->[1]'" : 'undef';
	like(emit('RdKw::WwW::SiteConf::Backend::Gmake', @$off), qr!^site/x/y: html/y site/x/\.ok$!m, "gmake: order=$v does nothing");
}
my $gmake = emit('RdKw::WwW::SiteConf::Backend::Gmake', order => 1);
like($gmake, qr!^site/x/y: html/y \| site/x/\.ok$!m, 'gmake -Sorder=1: a marker is after the bar');
like($gmake, qr!^site/x/\.ok: \| site/\.ok$!m, '... so is the marker of a parent');

# --- what a generator knows
is_deeply([ RdKw::WwW::SiteConf::Backend::Make->options ], [qw( clean purge )], 'make: clean, purge');
is_deeply([ sort RdKw::WwW::SiteConf::Backend::Gmake->options ], [qw( clean order purge )], 'gmake: clean, order, purge');

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

# --- the generators: by name (Backend::Name), and what they may not be
sub gen_error { my ($G, $o) = @_; eval { RdKw::WwW::SiteConf->new(B => $dir, quiet => 1)->generate($G, $o); 1 } ? '' : $@ }
my $lib = tempdir(CLEANUP => 1);
make_path("$lib/RdKw/WwW/SiteConf/Backend");
sub backend { open my $fh, '>', "$lib/RdKw/WwW/SiteConf/Backend/$_[0].pm" or die; print $fh $_[1]; close $fh or die }
# one that is there, but broken; one that writes many files, in
# directories of their own; and one that -G cannot name
backend(Broken => "package RdKw::WwW::SiteConf::Backend::Broken; die qq(broken here\\n);\n");
backend(Many => <<'PM');
package RdKw::WwW::SiteConf::Backend::Many;
sub options { () }
sub default_output { undef }
sub emit { ([ 'd/e/one.do', "1\n" ], [ 'two.do', "2\n" ]) }
sub build_command { ('many') }
1;
PM
backend(Odd_one => "1;\n");
unshift @INC, $lib;

like(gen_error('Make'), qr/unknown generator `Make'.  Choose one of: bmake, broken, gmake, make, many/, 'a name -G cannot have');
like(gen_error('nope'), qr/unknown generator `nope' \(RdKw::WwW::SiteConf::Backend::Nope is not installed\).  Choose one of: bmake, broken, gmake, make, many/,
	'a generator that is not installed');
is_deeply([ grep { !/\A(?:ninja|redo)\z/ } RdKw::WwW::SiteConf::generators() ], [qw( bmake broken gmake make many )],
	'the generators are those installed that -G can name');
like(gen_error('broken'), qr/broken here/, 'a broken generator is not said to be missing');
like(said('many'), qr/Writing d\/e\/one\.do\n.*Writing two\.do\n.*To build, run: many$/s, 'many files, and what to run');
ok(-f "$dir/d/e/one.do" && -f "$dir/two.do", '... are written, directories and all');
like(gen_error('many', 'x'), qr/generator many writes a file for each target, and cannot name them `x'/,
	'... and cannot be named');
# (update_file writes x.do by way of tmp-x.do)
backend(Clash => <<'PM');
package RdKw::WwW::SiteConf::Backend::Clash;
sub options { () }
sub default_output { undef }
sub emit { ([ 'd/tmp-x.do', "1\n" ], [ 'd/x.do', "2\n" ]) }
sub build_command { ('clash') }
1;
PM
like(gen_error('clash'), qr/generator clash cannot write both `d\/x\.do' and `d\/tmp-x\.do'/,
	'a file that another is written by way of');
