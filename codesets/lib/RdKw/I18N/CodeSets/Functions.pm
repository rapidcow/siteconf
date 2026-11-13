package RdKw::I18N::CodeSets::Functions;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.00_00';
$VERSION = eval $VERSION;

use Exporter ();
our @ISA = qw( Exporter );

=head1 NAME

RdKw::I18N::CodeSets::Functions - functional interface for CodeSets.pm

=head1 SYNOPSIS

    use RdKw::I18N::CodeSets::Functions qw( diag to_fs un_fs );

    open my $fh, '<', to_fs($file, { prog => $0 })
        or die diag("cannot open file %q: %m", $file) . "\n";
    my @names = un_fs(readdir $dh);

=head1 DESCRIPTION

A functional interface to the methods of L<RdKw::I18N::CodeSets> that
are used the most, each for the code sets of the process
(L<RdKw::I18N::CodeSets/locale>).  Nothing is exported by default.
Arguments, results, context and options are as the methods have them;
the code sets themselves, and the other methods that get or set them,
are not here.

=head1 FUNCTIONS

=over

=item B<diag>( I<format>, I<arg>, ... )

=item B<diag_name>( I<name>, inner => 0 )

L<RdKw::I18N::CodeSets/diag> and L<RdKw::I18N::CodeSets/diag_name>.

=item B<to_fs>( I<name>, ...[, { I<option> => I<value>, ... }] )

=item B<un_fs>( I<bytes>, ...[, { I<option> => I<value>, ... }] )

L<RdKw::I18N::CodeSets/to_fs> and L<RdKw::I18N::CodeSets/un_fs>.

=item B<to_argv>( I<arg>, ...[, { I<option> => I<value>, ... }] )

=item B<un_argv>( I<bytes>, ...[, { I<option> => I<value>, ... }] )

=item B<encode_argv>([ I<check> ])

=item B<decode_argv>([ I<check> ])

L<RdKw::I18N::CodeSets/to_argv>, L<RdKw::I18N::CodeSets/un_argv>,
L<RdKw::I18N::CodeSets/encode_argv> and
L<RdKw::I18N::CodeSets/decode_argv>.

=item B<getenv>( I<name>, ...[, { check => I<check> }] )

=item B<setenv>( I<name> => I<value>, ...[, { check => I<check> }] )

=item B<unsetenv>( I<name>, ... )

L<RdKw::I18N::CodeSets/getenv>, L<RdKw::I18N::CodeSets/setenv> and
L<RdKw::I18N::CodeSets/unsetenv>.

=item B<initstd>([ I<file> => I<fallback>, ... ])

L<RdKw::I18N::CodeSets/initstd>.

=back

=cut

use RdKw::I18N::CodeSets;

our @EXPORT_OK = qw(
	diag diag_name
	to_fs un_fs
	to_argv un_argv encode_argv decode_argv
	getenv setenv unsetenv
	initstd
);
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# (so that Carp blames our caller, not us)
our @CARP_NOT = ('RdKw::I18N::CodeSets');

# Each is a method of locale; the call is the last thing we do, so
# that it knows the context (and, for diag, $! is as we got it:
# locale saves it).
sub diag        { RdKw::I18N::CodeSets->locale->diag(@_) }
sub diag_name   { RdKw::I18N::CodeSets->locale->diag_name(@_) }
sub to_fs       { RdKw::I18N::CodeSets->locale->to_fs(@_) }
sub un_fs       { RdKw::I18N::CodeSets->locale->un_fs(@_) }
sub to_argv     { RdKw::I18N::CodeSets->locale->to_argv(@_) }
sub un_argv     { RdKw::I18N::CodeSets->locale->un_argv(@_) }
sub encode_argv { RdKw::I18N::CodeSets->locale->encode_argv(@_) }
sub decode_argv { RdKw::I18N::CodeSets->locale->decode_argv(@_) }
sub getenv      { RdKw::I18N::CodeSets->locale->getenv(@_) }
sub setenv      { RdKw::I18N::CodeSets->locale->setenv(@_) }
sub unsetenv    { RdKw::I18N::CodeSets->locale->unsetenv(@_) }
sub initstd     { RdKw::I18N::CodeSets->locale->initstd(@_) }

=head1 SEE ALSO

L<RdKw::I18N::CodeSets>

=cut

1;
