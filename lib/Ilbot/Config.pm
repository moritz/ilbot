package Ilbot::Config;
use 5.010;
use strict;
use warnings;
use Config::File qw/read_config_file/;

use parent 'Exporter';
our @EXPORT_OK = qw/config/;

my $path;
my %config;

my %known_files = (
    www => 1,
);

my %defaults = (
    www => { base_url => '/' },
);

sub import {
    my @config_paths = (@_,  'config', '/etc/ilbot');
    for my $p (@config_paths) {
        if (-e "$p/backend.conf") {
            $path = $p;
            last;
        }
    }
    unless (defined $path) {
        die "Cannot find config file 'backend.conf' in any of these directories:\n"
            . join(', '), map qq['$_'], @config_paths;
    }
    unless (-d "$path/template") {
        die "Missing directory '$path/template'";
    }
    $config{config_root} = $path;
    $config{template}    = "$path/template";
    $config{backend}     = read_config_file("$path/backend.conf");
    if (defined $config{backend}{LIB}) {
        unshift @INC, split /:/, $config{backend}{LIB}
    }
    __PACKAGE__->export_to_level(1, __PACKAGE__, 'config');
}

sub config {
    my @keys = @_;
    my $first = $keys[0];
    if ($known_files{$first}) {
        $config{$first} //= read_config_file("$path/$first.conf");
    }
    my $c = \%config;
    my $d = \%defaults;
    for (@keys) {
        $c = $c->{$_};
        $d = $d->{$_};
        $c //= $d;
        unless (defined $c) {
            die "Can't find config for @keys (config missing from $_)";
        }
    }
    return $c;
}


1;
