#!perl -T

use strict;
use warnings;

use Test::More;

use Business::Tax::Avalara;

eval 'use AvalaraConfig';
$@
	? plan( skip_all => 'Local connection information for Avalara required to run tests.' )
	: plan( tests => 4 );

my $config = AvalaraConfig->new();

like(
	$config->{'user_name'},
	qr/\w/,
	'The username is defined.',
);

like(
	$config->{'password'},
	qr/\w/,
	'The password is defined.',
);

like(
	$config->{'customer_code'},
	qr/\w/,
	'The customer_code is defined.',
);

like(
	$config->{'company_code'},
	qr/\w/,
	'The company_code is defined.',
);

