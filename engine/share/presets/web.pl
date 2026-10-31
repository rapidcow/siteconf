# The `web' preset: a static site.  It insists on a site_url, and sees
# to it that it and base_url agree (and are in the shape `locate' wants).
# Template and URI are not core; say so now, not halfway through make.
BEGIN { push @NEED, [ 'Template', 0 ], [ 'URI', 0 ], [ 'RdKw::WwW::GenLib', 0 ]; }

sub preset_finish
{
	my ($D, $O) = @_;
	$O->{base_url} = '/' unless defined $O->{base_url} && length $O->{base_url};
	defined $O->{site_url} && length $O->{site_url}
		or die "E: no site_url; configure with -Osite_url=https://example.org\n";
	eval { RdKw::WwW::GenLib::parse_base($O); 1 } or do {
		my $err = $@;
		$err =~ s/^/E: /mg;
		die $err;
	};
}
