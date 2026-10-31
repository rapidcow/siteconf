# The `web' preset: a static site.  It insists on a site_url, and sees
# to it that it and base_url agree (and are in the shape `locate' wants).
use RdKw::WwW::GenLib qw(parse_base);

sub preset_finish
{
	my ($D, $O) = @_;
	$O->{base_url} = '/' unless defined $O->{base_url} && length $O->{base_url};
	defined $O->{site_url} && length $O->{site_url}
		or die "E: no site_url; configure with -Osite_url=https://example.org\n";
	eval { parse_base($O); 1 } or do {
		my $err = $@;
		$err =~ s/^/E: /mg;
		die $err;
	};
}
