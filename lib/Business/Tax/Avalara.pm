package Business::Tax::Avalara;

use strict;
use warnings;

use Try::Tiny;
use Carp;
use LWP;
use HTTP::Request::Common;
use Encode qw();
use Data::Dump;
use JSON::PP;


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
	
	my $tax_results = $avalara_gateway->get_tax(
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
It takes in a perl hash of data to send to Avalara, generates the JSON, fetches a response,
and converts that back into a perl hash structure.

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
	
	my @required_fields = qw( customer_code company_code user_name password );
	foreach my $required_field ( @required_fields )
	{
		if ( !defined $args{ $required_field } )
		{
			die "Could not instantiate Business::Tax::Avalara module: Required field >$required_field< is missing.";
		}
	}
	
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

Makes a JSON request using the 'get_tax' method, parses the response, and returns a perl hash.

	my $tax_results = $avalara_gateway->get_tax(
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
See the Avalara documentation for the full description of the output, but the highlights are:

	{
		ResultCode     => 'Success',
		TaxAddresses   => [ array of address information ],
		TaxDate        => Date,
		TaxLines       =>
		[
			{
				Discount      => Discount,
				LineNo        => Line Number passed in,
				Rate          => Tax rate used,
				Tax           => Line item tax
				Taxability    => "true" or "false",
				Taxable       => Amount taxable,
				TaxCalculated => Line item tax
				TaxCode       => Tax Code used in the calculation
				Tax Details   => Details about state, county, city components of the tax
				
			},
			...
		],
		Timestamp      => Timestamp,
		TotalAmount    => Total amount before tax
		TotalDiscount  => Total Discount
		TotalExemption => Total amount exempt
		TotalTax       => Tax for the whole order
		TotalTaxable   => Amount that's taxable
	}
=cut

sub get_tax
{
	my ( $self, %args ) = @_;
	
	# Perl output, aka a hash ref, as opposed to JSON.
	my $tax_perl_output = {};
	try
	{
		my $request_json = $self->_generate_request_json( %args );
		my $result_json = $self->_make_request_json( $request_json );
		$tax_perl_output = $self->_parse_response_json( $result_json );
	}
	catch
	{
		carp( "Failed to fetch Avalara tax information: ", $_ );
		return undef;
	};
	
	return $tax_perl_output;
}


=head1 INTERNAL FUNCTIONS

=head2 _generate_request_json()

Generates the json to send to Avalara's web service.

Returns a JSON object.

=cut

sub _generate_request_json
{
	my ( $self, %args ) = @_;
	
	# Add in all the required elements.
	my @now = localtime();
	my $doc_date = defined $args{'doc_date'}
		? $args{'doc_date'}
		: sprintf( "%4d-%02d-%02d", $now[5] + 1900, $now[4] + 1, $now[3] );

	my $request =
	{
		DocDate      => $doc_date,
		CustomerCode => $self->{'customer_code'},
		CompanyCode  => $self->{'company_code'},
		Commit       => $args{'commit'} // 0,
	};
	
	$request->{'Addresses'} = [ $self->_generate_address_json( $args{'destination_address'}, 1 ) ];
	push @{ $request->{'Addresses'} },
		$self->_generate_address_json( $self->{'origin_address'} // $args{'origin_address'}, 2 );
	
	$request->{'Lines'} = [];
	
	my $counter = 1;
	foreach my $cart_line ( @{ $args{'cart_lines'} } )
	{
		push @{ $request->{'Lines'} }, $self->_generate_cart_line_json( $cart_line, $counter );
		$counter++;
	}
	
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
		$request->{ $optional_nodes{ $node_name } } = $args{ $node_name };
	}
	
	my $json = JSON::PP->new()->ascii()->pretty()->allow_nonref();
	return $json->encode( $request );
}


=head2 _generate_address_json()

Given an address hashref, generates and returns a data structure to be converted to JSON.

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

sub _generate_address_json
{
	my ( $self, $address, $address_code ) = @_;
	
	my $address_request = {};
	
	# Address code is just an internal identifier. In this module, 1 is destination, 2 is origin.
	$address_request->{'AddressCode'} = $address_code;
	
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
			$address_request->{ $nodes{ $node } } = $address->{ $node };
		}
	}
	
	return $address_request;
}


=head2 _generate_cart_line_json()

Generates a data structure from a cart_line hashref. Cart lines are:

	my $cart_line = {
		'line_number'         => $number (optional, will be generated if omitted.),
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

sub _generate_cart_line_json
{
	my ( $self, $cart_line, $counter ) = @_;
	
	my $cart_line_request = {};

	$cart_line_request->{'LineNo'} = $cart_line->{'line_number'} // $counter;	
	
	# By convention, destionation is address 1, origin is address 2, in this module.
	# It doesn't matter in the slightest, the labels just have to match.
	$cart_line_request->{'DestinationCode'} = 1;
	$cart_line_request->{'OriginCode'} = 2;
	
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
			$cart_line_request->{ $nodes{ $node } } = $cart_line->{ $node };
		}
	}
	
	return $cart_line_request;
}


=head2 _make_request_json()

Makes the https request to Avalara, and returns the response json.

=cut

sub _make_request_json
{
	my ( $self, $request_json ) = @_;
		
	my $request_server = $self->{'is_development'}
		? $AVALARA_DEVELOPMENT_REQUEST_SERVER
		: $AVALARA_REQUEST_SERVER;
	my $request_url = 'https://' . $request_server . '/1.0/tax/get';
	
	# Create a user agent object
	my $user_agent = LWP::UserAgent->new();
	$user_agent->agent( "perl/Business-Tax-Avalara/$VERSION" );
	
	# Create a request
	my $request = HTTP::Request::Common::POST(
		$request_url,
	);
	
	$request->authorization_basic(
		$self->{'user_name'},
		$self->{'password'},
	);
	
	$request->header( content_type => 'text/json' );
	$request->content( $request_json );
	$request->header( content_length => length( $request_json ) );
	
	# Pass request to the user agent and get a response back
	my $response = $user_agent->request( $request );
	
	# Check the outcome of the response
	if ( $response->is_success() )
	{
		return $response->content();
	}
	else
	{
		warn $response->status_line();
		warn $request->as_string();
		warn $response->as_string();
		die "Failed to fetch JSON response: " . $response->status_line() . "\n";
	}
	
	return;
}


=head2 _parse_response_json()

Converts the returned JSON into a perl hash.

=cut

sub _parse_response_json
{
	my ( $self, $response_json ) = @_;
	
	my $json = JSON::PP->new()->ascii()->pretty()->allow_nonref();
	return $json->decode( $response_json );
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
