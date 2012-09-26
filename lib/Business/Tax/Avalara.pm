package Business::Tax::Avalara;

use strict;
use warnings;

=head1 NAME

Business::Tax::Avalara - An interface to Avalara's REST webservice


=head1 DESCRIPTION

TODO

=head1 VERSION

Version 1.0.0

=cut

our $VERSION = '1.0.0';


sub new
{
	my ( $class, %args ) = @_;
	
	my $self = {
		'customer_code' => $args{'customer_code'},
		'company_code'  => $args{'company_code'},
		'detail_level'  => $args{'detail_level'},
	};
	
	bless $self, $class;
	return $self;
}


sub get_tax
{
	my ( $self, %args ) = @_;
	
}


=head1 AUTHOR

Kate Kirby, C<< <kate at cpan.org> >>.


=head1 BUGS

Please report any bugs or feature requests to C<bug-business-tax-avalara at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Business-Tax-Avalara>. 
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Business::Tax::Avalara


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Business-Tax-Avalara>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Business-Tax-Avalara>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Business-Tax-Avalara>

=item * Search CPAN

L<http://search.cpan.org/dist/Business-Tax-Avalara/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to ThinkGeek (L<http://www.thinkgeek.com/>) and its corporate overlords
at Geeknet (L<http://www.geek.net/>), for footing the bill while we eat pizza
and write code for them!


=head1 COPYRIGHT & LICENSE

Copyright 2012 Kate Kirby.

This program is free software; you can redistribute it and/or modify it
under the terms of the Artistic License or the GPL 3.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
