#!/usr/bin/perl

# Test that the module passes perlcritic
use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

my @MODULES = (
	'Perl::Critic 1.105',
	'Test::Perl::Critic 1.02',
);

# Don't run tests during end-user installs
use Test::More;
unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} ) {
	plan( skip_all => "Author tests not required for installation" );
}

# Load the testing modules
foreach my $MODULE ( @MODULES ) {
	eval "use $MODULE";
	if ( $@ ) {
		$ENV{RELEASE_TESTING}
		? die( "Failed to load required release-testing module $MODULE" )
		: plan( skip_all => "$MODULE not available for testing" );
	}
}

print "# Perl::Critic ".eval('$Perl::Critic::VERSION')."\n";
all_critic_ok();

1;
