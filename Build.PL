#!/usr/bin/env perl
use utf8;  # vim:set ts=4 sw=4:

use strict;
use warnings;

use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POE::Component::Schedule',
    dist_author         => 'Olivier Mengué <dolmen@cpan.org>',
    license             => 'perl',
    meta_add            => {
        resources => {
            homepage => 'http://code.google.com/p/poe-component-schedule/',
            repository => 'http://poe-component-schedule.googlecode.com/svn/trunk/',
            bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Schedule',
        },
    },
    requires            => {
        'POE' => '1.003', # A not too old version
        'DateTime' => 0,
        'DateTime::Set' => '0.25',
        'DateTime::TimeZone' => ($^O eq 'hpux' ? '0.87' : 0),
        # HP-UX requires a plugin for local TZ detection
        ($^O eq 'hpux' ? ('DateTime::TimeZone::HPUX' => '1.04') : () ),
    },
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'cover_db' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
