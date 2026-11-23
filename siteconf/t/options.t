#!perl
#
# t/options.t - -S of siteconf -g: the options of the generators

use strict;
use warnings;
use Test::More tests => 16;

use File::Path qw( make_path );
use File::Temp qw( tempdir );
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;
use RdKw::WwW::SiteConf::Make;
use RdKw::WwW::SiteConf::GMake;
use RdKw::WwW::SiteConf::Ninja;

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
sub emit { my ($class, %opt) = @_; $class->_emit({ %$plan, opt => \%opt }) }

# --- -Sorder
unlike(emit('RdKw::WwW::SiteConf::Make', order => 1), qr/ \| /, 'make has no bar, whatever is asked');
unlike(emit('RdKw::WwW::SiteConf::Make', order => 1), qr/ORDER/, 'and no .ORDER');
like(emit('RdKw::WwW::SiteConf::GMake'), qr!^site/x/y: html/y site/x/\.ok$!m, 'gmake: by default a marker is a prerequisite');
for my $off ([ order => 0 ], [ order => '' ], [ order => undef ]) {
	my $v = defined $off->[1] ? "`$off->[1]'" : 'undef';
	like(emit('RdKw::WwW::SiteConf::GMake', @$off), qr!^site/x/y: html/y site/x/\.ok$!m, "gmake: order=$v does nothing");
}
my $gmake = emit('RdKw::WwW::SiteConf::GMake', order => 1);
like($gmake, qr!^site/x/y: html/y \| site/x/\.ok$!m, 'gmake -Sorder=1: a marker is after the bar');
like($gmake, qr!^site/x/\.ok: \| site/\.ok$!m, '... so is the marker of a parent');

# --- what a generator knows
is_deeply([ RdKw::WwW::SiteConf::Make->_options ], [qw( clean purge )], 'make: clean, purge');
is_deeply([ sort RdKw::WwW::SiteConf::GMake->_options ], [qw( clean order purge )], 'gmake: clean, order, purge');
is_deeply([ RdKw::WwW::SiteConf::Ninja->_options ], [], 'ninja: none');

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
like(said('ninja', S => { clean => 'purge' }), qr/-Sclean=purge: unused by generator ninja/, 'ninja does not know clean');
unlike(said('ninja', S => { clean => undef }), qr/unused/, 'but a name alone is not said');
unlike(said('ninja', S => { clean => 'purge' }, quiet => 1), qr/unused/, '-q silences it');
like(said('make', S => { frob => 1 }), qr/-Sfrob=1: unused by generator make/, 'nobody knows frob');
unlike(said('make', S => { clean => 'purge' }), qr/unused/, 'make knows clean');
