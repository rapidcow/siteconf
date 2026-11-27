#!perl
#
# t/just.t - JUST-NEED and JUST-WANT:
# shallow no-recurse dependencies

use utf8;
use strict;
use warnings;
use Test::More tests => 21;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestDiag qw( fold );

BEGIN { $ENV{LANGUAGE} = 'C' }
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use RdKw::WwW::GenGenLib qw( write_make );
use RdKw::WwW::SiteConf;

sub project
{
	my (%f) = @_;
	my $dir = tempdir(CLEANUP => 1);
	make_path("$dir/MY", "$dir/html");
	my %file = (
		MANIFEST => "MAKE all\n\tNEED x\n",
		'Makefile.in' => "x: \${a}/x\n\tcp \${a}/\${<:Q} \${b}/\${\@:Q}\n",
		'html/x' => "x\n",
		%f,
	);
	for my $name (keys %file) {
		make_path($dir . '/' . ($name =~ m{(.*)/} ? $1 : '.'));
		open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die "$name: $!";
		print $fh $file{$name};
		close $fh or die;
	}
	write_make("$dir/MY/config.mk", { A => '.', B => '.', a => 'html', b => 'site', c => 'site',
		e => '.ok', F => "$dir/MANIFEST", R => "$dir/Makefile.in" }, prog => 'test');
	$dir;
}
sub plan_of { my ($dir, @g) = @_; RdKw::WwW::SiteConf->new(B => $dir, quiet => 1, goals => [ @g ])->plan; }
sub failure { my $dir = shift; eval { plan_of($dir, @_); 1; } ? '' : $@; }

my $cp = "\tcp \${a}/\${\@:Q} \${b}/\${\@:Q}\n";

# --- a header: what a JUST-NEED says is a dep, and what it says is not read
{
	my $dir = project(
		MANIFEST => "MAKE all\nNEED page\n",
		'Makefile.in' => "page a b c: \n$cp",
		'html/page' => "# NEED: \${a}/a\n# JUST-NEED: \${a}/b\n# JUST-WANT: \${a}/gone\n",
		'html/a' => "# NEED: \${a}/c\n",
		'html/b' => "# NEED: \${a}/nope\n",
		'html/c' => "c\n",
	);
	my $p = eval { plan_of($dir) } or diag $@;
	is_deeply($p->{node}{page}{deps}, [ qw( html/page html/a html/b html/c site/.ok ) ],
		'a header: NEED is followed, JUST-NEED is a dep and nothing more') or diag explain $p->{node}{page}{deps};
	ok(!grep({ $_ eq 'html/nope'; } @{ $p->{node}{page}{deps} }), 'what a JUST-NEED declares is not followed');
}
{
	my $dir = project(
		MANIFEST => "MAKE all\nNEED page\n",
		'Makefile.in' => "page: \n$cp",
		'html/page' => "# JUST-NEED: \${a}/missing\n",
	);
	like(fold(failure($dir)), qr/NEEDs `html\/missing' \(in header of `html\/page' line 1\), which we don't seem to have/,
		'a JUST-NEED that is not there is an error');
	$dir = project(
		MANIFEST => "MAKE all\nNEED page\n",
		'Makefile.in' => "page: \n$cp",
		'html/page' => "# JUST-WANT: \${a}/missing\n",
	);
	is(failure($dir), '', 'a JUST-WANT that is not there is dropped');
}

# --- Makefile.in: JUST:, JUST-NEED: and JUST-WANT:, and a tool whose header is not read
{
	my $dir = project(
		MANIFEST => "MAKE all\nNEED x\nNEED y\nNEED z\n",
		'Makefile.in' => "x: JUST:\${A}/tool\n$cp"
			. "y: JUST-NEED:\${A}/tool\n$cp"
			. "z: JUST-WANT:\${A}/tool \${A}/tool2\n$cp",
		'html/x' => "x\n", 'html/y' => "y\n", 'html/z' => "z\n",
		'tool' => "# NEED: needed-by-tool\n",
		'tool2' => "# NEED: needed-by-tool2\n",
		'needed-by-tool2' => "n\n",
	);
	my $p = eval { plan_of($dir) } or diag $@;
	is_deeply($p->{node}{x}{deps}, [ 'html/x', 'tool', 'site/.ok' ], 'JUST: is a dep, and the tool header is not read') or diag explain $p->{node}{x};
	is_deeply($p->{node}{y}{deps}, [ 'html/y', 'tool', 'site/.ok' ], 'JUST-NEED: is the same');
	is_deeply($p->{node}{z}{deps}, [ 'html/z', 'tool2', 'needed-by-tool2', 'tool', 'site/.ok' ],
		'JUST-WANT: is a dep that is kept (a tool2 beside it is read)') or diag explain $p->{node}{z}{deps};
	$dir = project('Makefile.in' => "x: JUST-FOO:y\n$cp");
	like(failure($dir), qr/must start with NEED:, WANT:, JUST:/, 'an unknown prefix is said so');
}

# --- the manifest: JUST-NEED, JUST-WANT, and what the resolved manifest says
{
	my $dir = project(
		MANIFEST => "MAKE all\n\tJUST-NEED one two\n\tJUST-WANT three four\n\tWANT five\n\tNEED x\n",
		'Makefile.in' => "one two three five x: \n$cp",
		'html/one' => "# NEED: \${a}/never\n", 'html/two' => "2\n", 'html/three' => "3\n",
		'html/five' => "5\n",
	);
	my $p = eval { plan_of($dir) } or diag $@;
	my $mf = RdKw::WwW::SiteConf->new(B => $dir, quiet => 1);
	is($p->{goals}[0]{just}{one}, 1, 'the plan says which are JUST');
	is_deeply([ map { $_->[0] } @{ $p->{goals}[0]{dropped} } ], [ 'four', ], 'JUST-WANT: one that cannot be had is dropped');
	is($mf->manifest_text($p->{goals}[0]),
		"MAKE all\n\tJUST-NEED one\n\tJUST-NEED two\n\tNEED x\n\tJUST-NEED three\n\tNEED five\n"
		. "#\tJUST-WANT four\t# no rule to make it (`$dir/Makefile.in').\n",
		'the resolved manifest: a JUST-WANT that was had is a JUST-NEED') or diag $mf->manifest_text($p->{goals}[0]);
}

# --- a goal that is named: what it stands for is JUST if the one that says so is
{
	my $dir = project(
		MANIFEST => "MAKE all\n\tJUST-NEED food\nMAKE food\n\tNEED x\n\tWANT x\n",
	);
	my $p = eval { plan_of($dir, 'all') } or diag $@;
	is_deeply($p->{goals}[0]{just}, { x => 1 }, 'a JUST-NEED of a goal makes its files JUST');
}

# --- both ways at once: the header is read, whichever comes first
for my $order ("NEED x\n\tNEED y\n", "NEED y\n\tNEED x\n") {
	my $dir = project(
		MANIFEST => "MAKE all\n\t$order",
		'Makefile.in' => "x: JUST:\${B}/\${b}/y\n$cp" . "y: \n$cp",
		'html/y' => "# NEED: \${a}/z\n",
		'html/z' => "z\n",
	);
	my $p = eval { plan_of($dir, 'all') } or diag $@;
	is_deeply($p->{node}{y}{deps}, [ 'html/y', 'html/z', 'site/.ok' ], 'a file that is JUST here and not there is read in full')
		or diag explain $p->{node}{y};
}

# --- what we make cannot be NEEDed or WANTed plainly, from anywhere
{
	my $dir = project(
		MANIFEST => "MAKE all\n\tNEED page\n",
		'Makefile.in' => "y z: \n$cp"
			. "page: \${A}/tool \${B}/\${b}/y WANT:\${B}/\${b}/z\n$cp",
		'html/y' => "y\n", 'html/z' => "z\n",
		'html/page' => "# NEED: \${a}/inc\n# WANT: \${B}/\${b}/z\n",
		'html/inc' => "# NEED: \${B}/\${b}/y\n",
		'tool' => "# NEED: \${B}/\${b}/y\n",
	);
	is(failure($dir), <<MSG, 'every plain edge to what we make, after the rest; then what to do');
E: 5 problems; no Makefile for you.
E: cannot NEED/WANT a file we make:
E:  `site/y' (NEEDed in $dir/Makefile.in line 3)
E:   (made by $dir/Makefile.in line 1),
E:  `site/z' (WANTed in $dir/Makefile.in line 3)
E:   (made by $dir/Makefile.in line 1),
E:  `site/y' (NEEDed in header of `html/inc' line 1)
E:   (made by $dir/Makefile.in line 1),
E:  `site/z' (WANTed in header of `html/page' line 2)
E:   (made by $dir/Makefile.in line 1),
E:  `site/y' (NEEDed in header of `tool' line 1)
E:   (made by $dir/Makefile.in line 1).
E: Please use JUST-NEED or JUST-WANT instead.
MSG

	$dir = project(
		MANIFEST => "MAKE all\n\tNEED page\n\tNEED gone\n",
		'Makefile.in' => "y gone: \n$cp" . "page: \${B}/\${b}/y\n$cp",
		'html/y' => "y\n", 'html/page' => '',
	);
	like(failure($dir), qr/\AE: goal `all' NEEDs `gone'.*\nE: 2 problems; no Makefile for you\.\nE: cannot NEED\/WANT a file we make:\n.*\nE:   \(made by .* line 1\)\.\nE: Please use JUST-NEED or JUST-WANT instead\.\n\z/s,
		'... and what cannot be made comes first');

	$dir = project(
		MANIFEST => "MAKE all\n\tNEED page\n",
		'Makefile.in' => "y: \n$cp" . "page: JUST:\${B}/\${b}/y \${B}/\${b}/y\n$cp",
		'html/y' => "y\n", 'html/page' => '',
	);
	like(failure($dir), qr/`site\/y' \(NEEDed in \S+ line 3\)/, 'a plain mention beside a JUST: is still one');
}
{
	my $dir = project(
		MANIFEST => "MAKE all\n\tNEED page\n",
		'Makefile.in' => "y z: \n$cp" . "page: JUST:\${B}/\${b}/y JUST-WANT:\${B}/\${b}/z\n$cp",
		'html/y' => "# NEED: \${a}/dep\n", 'html/dep' => "d\n", 'html/z' => "z\n",
		'html/page' => "# JUST: \${B}/\${b}/z\n# JUST-WANT: \${B}/\${b}/y\n",
	);
	my $p = eval { plan_of($dir) } or diag $@;
	is_deeply($p && $p->{node}{page}{deps}, [qw( html/page site/y site/z site/.ok )],
		'JUST:, JUST-NEED and JUST-WANT of what we make are fine') or diag explain $p && $p->{node}{page};
	is_deeply($p && $p->{node}{page}{kids}, [qw( y z )], '... and are edges');
	is_deeply($p && $p->{node}{y}{deps}, [qw( html/y html/dep site/.ok )],
		'... to a file whose own header is read all the same');
}
{
	# (that is for a rule, and the build dir is no rule's)
	my $dir = project(
		MANIFEST => "MAKE all\n\tNEED page\n",
		'Makefile.in' => "page: \${B}/MY/option.mk \${B}/\${b}/extern\n$cp",
		'html/page' => "# NEED: \${B}/\${b}/extern\n",
		'MY/option.mk' => '', 'site/extern' => '',
	);
	is(failure($dir), '', 'what no rule makes may be NEEDed, in ${B} or ${b}');
}

done_testing;
