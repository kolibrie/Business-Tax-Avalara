use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
	module_name          => 'Business::Tax::Avalara',
	license              => 'artistic',
	dist_author          =>
	[
		'Kate Kirby <kate@cpan.org>',
	],
	dist_version_from    => 'lib/Business/Tax/Avalara.pm',
	build_requires       =>
	{
		'Data::Dump'      => 0,
		'Test::Deep'      => 0,
		'Test::Exception' => 0,
		'Test::More'      => 0,
	},
	requires             =>
	{
		'perl'            => 5.006,
	},
	add_to_cleanup       =>
	[
		'Business-Tax-Avalara*',
	],
	create_makefile_pl   => 'traditional',
	recursive_test_files => 1,
	configure_requires   =>
	{
		'Module::Build'   => 0,
	},
	meta_merge           =>
	{
		resources         =>
		{
			repository => 'https://github.com/katekirby/Business-Tax-Avalara.git',
			homepage   => 'https://metacpan.org/release/Business-Tax-Avalara',
			bugtracker => 'http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Business-Tax-Avalara',
		},
	},
);

$builder->create_build_script();
