package Business::Tax::Avalara;

use strict;
use warnings;

use XML::LibXML qw();
use Try::Tiny;
use Carp;

=head1 NAME

Business::Tax::Avalara - An interface to Avalara's REST webservice


=head1 DESCRIPTION

TODO

=head1 VERSION

Version 1.0.0

=cut

our $VERSION = '1.0.0';
our $AVALARA_REQUEST_URL = 'https://rest.avalara.net/1.0/tax/get';


sub new
{
	my ( $class, %args ) = @_;
	
	# TODO: Require customer_code, company_code
	
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
	
	# Perl nodeput, aka a hash ref, as opposed to XML or JSON.
	my $tax_perl_nodeput = {};
	try
	{
		my $request_xml = $self->generate_request_xml( %args );
		my $result_xml = $self->make_request( $request_xml );
		$tax_perl_nodeput = $self->parse_response_xml( $result_xml );
	}
	catch
	{
		carp( "Failed to fetch Avalara tax information: ", $_ );
		return undef;
	};
	
	return $tax_perl_nodeput;
}


sub generate_request_xml
{
	my ( $self, %args ) = @_;
	my $document_node = XML::LibXML->createDocument( '1.0', 'UTF-8' );
	my $root_node = $document_node->createElement( 'GetTaxRequest' );
	$document_node->setDocumentElement( $root_node );
	
	# Add in all the required nodes.
	my @now = localtime();
	my $doc_date = defined $args{'doc_date'}
		? $args{'doc_date'}
		: sprintf( "%4d-%02d-%02d", $now[5] + 1900, $now[4] + 1, $now[3] );
		
	my $doc_date_node = $document_node->createElement( 'DocDate' );
	$doc_date_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $doc_date ) ) );
	$root_node->appendChild( $doc_date_node );
	
	my $customer_code_node = $document_node->createElement( 'CustomerCode' );
	$customer_code_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $self->{'customer_code'} ) ) );
	$root_node->appendChild( $customer_code_node );
	
	my $addresses_node = $document_node->createElement( 'Addresses' );
	my $destination_address_node = $self->_generate_address_xml( $document_node, $args{'destination_address'}, 1 );
	$addresses_node->appendChild( $destination_address_node );
	my $origin_address_node = $self->_generate_address_xml( $document_node, $self->{'origin_address'} // $args{'origin_address'}, 2 );
	$addresses_node->appendChild( $origin_address_node );
	$root_node->appendChild( $addresses_node );
	
	my $cart_lines_node = $document_node->createElement( 'Lines' );
	my $counter = 1;
	foreach my $cart_line ( @{ $args{'cart_lines'} } )
	{
		$cart_lines_node->appendChild( $self->_generate_cart_line_xml( $document_node, $cart_line, $counter ) );
		$counter++;
	}
	$root_node->appendChild( $cart_lines_node );
	
	my $commit_node = $document_node->createElement( 'Commit' );
	$commit_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $args{'commit'} // 0 ) ) );
	$root_node->appendChild( $commit_node );
	
	my %optional_nodes =
	(
		customer_usage_type   => 'CustomerUsageType',
		discount              => 'Discount',
		purchase_order_number => 'PurchaseOrderNo',
		exemption_number      => 'ExemptionNo',
		detail_level          => 'DetailLevel',
		document_type         => 'DocType',
		payment_date          => 'PaymentDate',
		reference_code        => 'ReferenceCode',
	);
	
	foreach my $node_name ( keys %optional_nodes )
	{
		next if ( !defined $args{ $node_name } );
		my $node = $document_node->createElement( $optional_nodes{ $node_name } );
		$node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $args{ $node_name } ) ) );
		$root_node->appendChild( $node );
	}
	
	return $document_node;
}


sub _generate_address_xml
{
	my ( $self, $document_node, $address, $address_code ) = @_;
	
	my $address_node = $document_node->createElement( 'Address' );
	
	# Address code is just an internal identifier. In this module, 1 is destination, 2 is origin.
	my $address_code_node = $document_node->createElement( 'AddressCode' );
	$address_code_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $address_code ) ) );
	$address_node->appendChild( $address_code_node );
	
	my %nodes =
	(
		'line_1'        => 'Line1',
		'line_2'        => 'Line2',
		'line_3'        => 'Line3',
		'city'          => 'City',
		'region'        => 'Region',
		'country'       => 'Country',
		'postal_code'   => 'PostalCode',
		'latitude'      => 'Latitude',
		'longitude'     => 'Longitude',
		'tax_region_id' => 'TaxRegionId',
	);
	
	foreach my $node ( keys %nodes )
	{
		if ( defined $address->{ $node } )
		{
			my $sub_node = $document_node->createElement( $nodes{ $node } );
			$sub_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $address->{ $node } ) ) );
			$address_node->appendChild( $sub_node );
		}
	}
	
	return $address_node;
}



sub _generate_cart_line_xml
{
	my ( $self, $document_node, $cart_line, $counter ) = @_;
	
	my $cart_line_node = $document_node->createElement( 'Line' );
	
	my $counter_node = $document_node->createElement( 'LineNo' );
	$counter_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $counter ) ) );
	$cart_line_node->appendChild( $counter_node );
	
	# By convention, destionation is address 1, origin is address 2, in this module.
	# It doesn't matter in the slightest, the labels just have to match.
	my $destination_code = $document_node->createElement( 'DestinationCode' );
	$destination_code->appendChild( XML::LibXML::Text->new( latin1_to_utf8( 1 ) ) );
	$cart_line_node->appendChild( $destination_code );
	
	my $origin_code = $document_node->createElement( 'OriginCode' );
	$origin_code->appendChild( XML::LibXML::Text->new( latin1_to_utf8( 2 ) ) );
	$cart_line_node->appendChild( $origin_code );
	
	my %nodes =
	(
		'item_code'           => 'ItemCode',
		'sku'                 => 'ItemCode', # Use sku OR item_code
		'tax_code'            => 'TaxCode', # TODO: Give some interface for this
		'customer_usage_type' => 'CustomerUsageType',
		'description'         => 'Description',
		'quantity'            => 'Qty',
		'amount'              => 'Amount', # Extended price, ie, price * quantity
		'discounted'          => 'Discounted', # Boolean
		'tax_included'        => 'TaxIncluded', # Boolean
		'ref_1'               => 'Ref1',
		'ref_2'               => 'Ref2',
	);
	
	foreach my $node ( keys %nodes )
	{
		if ( defined $cart_line->{ $node } )
		{
			my $sub_node = $document_node->createElement( $nodes{ $node } );
			$sub_node->appendChild( XML::LibXML::Text->new( latin1_to_utf8( $cart_line->{ $node } ) ) );
			$cart_line_node->appendChild( $sub_node );
		}
	}
	
	return $cart_line_node;
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

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License version 3 as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; withnode even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/

=cut

1;
