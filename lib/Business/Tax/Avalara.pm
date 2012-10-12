package Business::Tax::Avalara;

use strict;
use warnings;

use XML::LibXML qw();
use XML::Hash;
use Try::Tiny;
use Carp;
use LWP::UserAgent;


=head1 NAME

Business::Tax::Avalara - An interface to Avalara's REST webservice

=head1 SYNOPSYS

	use Business::Tax::Avalara;
	my $avalara_gateway = Business::Tax::Avalara->new(
		customer_code  => $customer_code,
		company_code   => $company_code,
		user_name      => $user_name,
		password       => $password,
		origin_address =>
		{
			line_1      => '1313 Mockingbird Lane',
			postal_code => '98765',
		},
	);
	
	$avalara_gateway->get_tax(
		destination_address =>
		{
			line_1      => '42 Evergreen Terrace',
			city        => 'Springfield',
			postal_code => '12345',
		},
		cart_lines =>
		[
			{
				sku      => '42ACE',
				quantity => 1,
				amount   => '8.99',
			},
			{
				sku      => '9FCE2',
				quantity => 2,
				amount   => '38.98',
			}
		],
		
	);
	

=head1 DESCRIPTION

Business::Tax::Avalara is a simple interface to Avalara's REST-based sales tax webservice.
It takes in a perl hash of data to send to Avalara, generates the XML, fetches a response,
and converts that back into a perl hash structure.

Currently, json output is not supported, though Avalara can return that. (Feel free to
let me know if anyone would find that useful.)

This module only supports the 'get_tax' method at the moment.

=head1 VERSION

Version 1.0.0

=cut

our $VERSION = '1.0.0';
our $AVALARA_REQUEST_SERVER = 'rest.avalara.net';
our $AVALARA_DEVELOPMENT_REQUEST_SERVER = 'development.avalara.net';

=head1 FUNCTIONS

=head2 new()

Creates a new Business::Tax::Avalara object with various options that do not change
between requests.

	my $avalara_gateway = Business::Tax::Avalara->new(
		customer_code  => $customer_code,
		company_code   => $company_code,
		user_name      => $user_name
		pasword        => $password,
		is_development => boolean (optional), default 0
		origin_address => $origin_address (optional),
	);
	
The fields customer_code, company_code, user_name, and password should be
provided by your Avalara representative. Account number and License key
are synonyms for user_name and password, respectively.

is_development should be set to 1 to use the development URL, and 0 for
production uses.

origin_address can either be set here, or passed into get_tax, depending on if
it changes per request, or if you're always shipping from the same location.
It is a hash ref, see below for formatting details.

Returns a Business::Tax::Avalara object.

=cut

sub new
{
	my ( $class, %args ) = @_;
	
	# TODO: Require customer_code, company_code
	
	my $self = {
		customer_code  => $args{'customer_code'},
		company_code   => $args{'company_code'},
		is_development => $args{'is_development'} // 0,
		user_name      => $args{'user_name'},
		password       => $args{'password'},
		origin_address => $args{'origin_address'},
	};
	
	bless $self, $class;
	return $self;
}


=head2 get_tax()

Makes an XML request using the 'get_tax' method, parses the response, and returns a perl hash.

	$avalara_gateway->get_tax(
		destination_address   => $address_hash,
		origin_address        => $address_hash (may be specified in new),
		document_date         => $date (optional), default is current date
		cart_lines            => $cart_line_hash,
		customer_usage_type   => $customer_usage_type (optional),
		discount              => $order_level_discount (optional),
		purchase_order_number => $purchase_order_number (optional),
		exemption_number      => $exemption_number (optional),
		detail_level          => $detail_level (optional), default 'Tax',
		document_type         => $document_type (optional), default 'SalesOrder'
		payment_date          => $date (optional),
		reference_code        => $reference_code (optional),
		
	);

See below for the definitions of address and cart_line fields. The field origin_address
may be specified here if it changes between transactions, or in new if it's largely static.

detail level is one of 'Tax', 'Summary', 'Document', 'Line', or 'Diagnostic'.
See the Avalara documentation for the distinctions.

document_type is one of 'SalesOrder', 'SalesInvoice', 'PurchaseOrder', 'PurchaseInvoice',
'ReturnOrder', and 'ReturnInvoice'.

Returns a perl hashref based on the Avalara return.
# TODO: Document the output.
=cut

sub get_tax
{
	my ( $self, %args ) = @_;
	
	# Perl output, aka a hash ref, as opposed to XML or JSON.
	my $tax_perl_output = {};
	try
	{
		my $request_xml = $self->_generate_request_xml( %args );
		my $result_xml = $self->_make_request( $request_xml );
		$tax_perl_output = $self->_parse_response_xml( $result_xml );
	}
	catch
	{
		carp( "Failed to fetch Avalara tax information: ", $_ );
		return undef;
	};
	
	return $tax_perl_output;
}


=head1 INTERNAL FUNCTIONS

=head2 _generate_request_xml()

Generates the XML to send to Avalara's web service.

Returns an XML DOM object.

=cut

sub _generate_request_xml
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


=head2 _generate_address_xml()

Given an address hashref, generates and returns an address XML node.

An address hashref is defined as:

	my $address = {
		line_1        => $first_line_of_address,
		line_2        => $second_line_of_address,
		line_3        => $third_line_of_address,
		city          => $city,
		region        => $state_or_province,
		country       => $iso_2_code,
		postal_code   => $postal_or_ZIP_code,
		latitude      => $latitude,
		longitude     => $longitude,
		tax_region_id => $tax_region_id,
	};
	
All fields are optional, though without enough to identify an address, your results will
be less than satisfying.

Country coes are ISO 3166-1 (alpha 2) format, such as 'US'.

=cut

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


=head2 _generate_cart_line_xml()

Generates an XML node from a cart_line hashref. Cart lines are:

	my $cart_line = {
		'item_code'           => $item_code
		'sku'                 => $sku, # Use sku OR item_code
		'tax_code'            => $tax_code,
		'customer_usage_type' => $customer_usage_code
		'description'         => $description,
		'quantity'            => $quantity,
		'amount'              => $amount, # Extended price, ie, price * quantity
		'discounted'          => $is_included_in_discount, # Boolean
		'tax_included'        => $is_tax_included, # Boolean
		'ref_1'               => $reference_1,
		'ref_2'               => $reference_2,
	}
	
One of item_code or sku, quantity, and amount are required fields.

Customer usage type determines the type of item (sometimes called entity or use code). In some
states, different types of items have different tax rates.

=cut

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


=head2 _make_request()

Makes the https request to Avalara, and returns the response xml.

=cut

sub _make_request
{
	my ( $self, $request_xml ) = @_;
	#  'https://rest.avalara.net/1.0/tax/get';
	
	
	my $request_server = $self->{'is_development'}
		? $AVALARA_DEVELOPMENT_REQUEST_SERVER
		: $AVALARA_REQUEST_SERVER;
	my $request_url = 'https://' . $request_server . '/1.0/tax/get';
	
	# Create a user agent object
	my $user_agent = LWP::UserAgent->new();
	$user_agent->agent( "perl/Business-Tax-Avalara/$VERSION" );
	
	# Set the httpd authentication credentials
	$user_agent->credentials(
		$request_server . ':80',
		'1.0/tax/get',
		$self->{'user_name'},
		$self->{'password'},
	);
	
	# Create a request
	my $request = HTTP::Request->new(POST => $request_url);
	$request->content_type('text/xml');
	$request->content( $request_xml );
	
	# Pass request to the user agent and get a response back
	my $response = $user_agent->request( $request );
	
	# Check the outcome of the response
	if ( $response->is_success() )
	{
		return $response->content();
	}
	else
	{
		die "Failed to fetch XML response: " . $response->status_line() . "\n";
	}
	
	return;
}


=head2 _parse_response_xml()

Converts the returned XML into a perl hash.

=cut

sub _parse_response_xml
{
	my ( $self, $response_xml ) = @_;
	my $response_hash = {};
	
	my $xml_document;
	try
	{
		$xml_document = $self->_parse_xml( $response_xml );
	}
	catch
	{
		die "Failed to parse xml document: $_\n";
	};
	
	my $xml_converter = XML::Hash->new();
	$response_hash = $xml_converter->fromDOMtoHash( $xml_document );

	return $response_hash;
}


=head2 _parse_xml()

Parses the XML string into a DOM object.

=cut

sub _parse_xml
{
	my ( $self, $xml ) = @_;
	
	my $xml_document;
	try
	{
		my $parser = XML::LibXML->new();
		$xml_document = $parser->load_xml( string => $xml );
	}
	catch
	{
		die "Could not parse XML: $_\n";
	};
	
	# TODO: Add some sanity checks here.
	
	return $xml_document;
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
