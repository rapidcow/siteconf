#!perl
#
# t/clean.t - -Sclean: the name(s) of the cleaning rules

use strict;
use warnings;
use Test::More tests => 30;

use File::Path qw( make_path );
use File::Temp qw( tempdir );
# Pin LANGUAGE to C so gettext does not translate the messages matched below.
BEGIN { $ENV{LANGUAGE} = 'C' }
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;
use RdKw::WwW::SiteConf::Make;

# A project with the goals `all' (a.css, d/b.css) and `small' (a.css).
sub project {
	my ($manifest, %D) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/html/d", "$dir/MY");
	for my $f (qw( x html/a.css html/d/b.css )) {
		open my $fh, '>', "$dir/$f" or die; close $fh;
	}
	open my $fh, '>', "$dir/Makefile.in" or die;
	print $fh "a.css d/b.css: \${A}/x\n\tcp \${a}/\${\@} \${B}/\${b}/\${\@}\n";
	close $fh or die;
	open $fh, '>', "$dir/MANIFEST" or die;
	print $fh $manifest;
	close $fh or die;
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		R => "$dir/Makefile.in", F => "$dir/MANIFEST", e => '.ok', %D }, prog => 'test');
	$dir;
}
my $manifest = "MAKE all\n\tNEED a.css\n\tNEED d/b.css\nMAKE small\n\tNEED a.css\n";
# (the options of the generator, if any, follow the project)
sub plan_of { my $dir = shift; RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, S => { @_ })->plan }
sub names { join ' ', map { $_->{name} } @{ $_[0]{clean} } }
sub makefile { $_[0]{prog} = "test"; RdKw::WwW::SiteConf::Make->_emit($_[0]) }

# --- no -Sclean, no rule; a name alone is the default one
{
	is(names(plan_of(project($manifest))), '', 'none unless asked for');
	ok(eval { plan_of(project("MAKE clean\n\tNEED a.css\n")); 1 }, 'and then clean is no reserved name') or diag $@;
	my $plan = plan_of(project($manifest), clean => undef);
	is(names($plan), 'clean', 'default: one rule, clean');
	my $mk = makefile($plan);
	like($mk, qr/^\.PHONY: all small clean$/m, 'default: phony');
	like($mk, qr!^clean:\n\trm -f -- site/a\.css site/d/b\.css\n!m, 'default: removes all, not the markers');
	is(names(plan_of(project($manifest), clean => '')), 'clean', 'empty: the default too');
}

# --- a name
{
	my $plan = plan_of(project($manifest), clean => 'distclean');
	is(names($plan), 'distclean', 'a rule of another name');
	like(makefile($plan), qr/^\.PHONY: all small distclean$/m, 'phony');
	unlike(makefile($plan), qr/^clean:/m, 'no clean');
}

# --- one for each goal
{
	my $plan = plan_of(project($manifest), clean => 'clean-&');
	is(names($plan), 'clean-all clean-small', 'a rule for each goal');
	is_deeply($plan->{clean}[0]{files}, [qw( site/a.css site/d/b.css )], 'all: what it makes');
	is_deeply($plan->{clean}[1]{files}, ['site/a.css'], 'small: what it makes');
	my $mk = makefile($plan);
	like($mk, qr/^\.PHONY: all small clean-all clean-small$/m, 'phony');
	like($mk, qr!^clean-small:\n\trm -f -- site/a\.css\n!m, 'recipe');
	unlike($mk, qr/\.ok\b.*\n.*\brm\b|\brm\b.*\.ok/, 'no marker removed');
	is(names(plan_of(project($manifest), clean => '&-x-&')), 'all-x-all small-x-small', 'every & is the goal');
}

# --- none, and then clean is free
{
	my $plan = plan_of(project($manifest), clean => '&');
	is(names($plan), '', 'a lone &: no rules');
	unlike(makefile($plan), qr/clean/, 'nothing in the Makefile');
	my $plan2 = eval { plan_of(project("MAKE clean\n\tNEED a.css\n"), clean => '&') };
	ok($plan2, 'a goal called clean') or diag $@;
	ok(eval { plan_of(project("MAKE clean\n\tNEED a.css\n"), clean => 'purge'); 1 }, 'ditto for another name') or diag $@;
	ok(!eval { plan_of(project("MAKE purge\n\tNEED a.css\n"), clean => 'purge'); 1 }
		&& $@ =~ /reserved/, 'but not the name itself');
	ok(!eval { plan_of(project("MAKE clean\n\tNEED a.css\n"), clean => undef); 1 }
		&& $@ =~ /reserved/, 'clean is reserved once there is such a rule');
}

# --- collisions and bad names
{
	my $m = "MAKE a\n\tNEED a.css\nMAKE a-x\n\tNEED a.css\n";
	ok(!eval { plan_of(project($m), clean => '&-x'); 1 }
		&& $@ =~ /`a-x' is also the name of a goal/, 'a rule named like a goal');
	ok(!eval { plan_of(project($manifest), clean => 'MY'); 1 }
		&& $@ =~ /`MY'/, 'a rule named like MY');
	ok(!eval { plan_of(project($manifest), clean => 'a b'); 1 }
		&& $@ =~ /letters, digits/, 'a bad name');
	ok(!eval { plan_of(project($manifest), clean => 'x/&'); 1 }
		&& $@ =~ /letters, digits/, 'a slash');
}

# --- many files: several rm lines, none too long, each file once
{
	my @file = map { sprintf 'site/%s/%04d.html', 'x' x 100, $_ } 1 .. 500;
	my $mk = makefile({ D => {}, goals => [], dirs => [], order => [], node => {},
		clean => [ { name => 'clean', files => [@file] } ] });
	my @rm = $mk =~ /^\trm -f -- (.*)$/mg;
	cmp_ok(@rm, '>', 1, 'split over several lines');
	is(scalar(grep { length > 16384 } @rm), 0, 'every line within the budget');
	is_deeply([ map { split ' ' } @rm ], \@file, 'each file once, in order');
	$mk = makefile({ D => {}, goals => [], dirs => [], order => [], node => {},
		clean => [ { name => 'clean', files => [ 'x' x 20000, 'y' ] } ] });
	is(scalar(() = $mk =~ /^\trm -f -- /mg), 2, 'a name over the budget has its own line');
}
