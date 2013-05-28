package Ilbot::Config;
use 5.010;
use strict;
use warnings;
use Config::File qw/read_config_file/;
use HTML::Template 2.91;
use Data::Dumper;

use parent 'Exporter';
our @EXPORT = qw/config _template _backend _frontend/;

my $path;
my %config;

my %known_files = (
    www => 1,
);

my %defaults = (
    www => {
        base_url        => '/',
        no_cache        => 0,
        throttle        => 0,
        use_cache       => 1,
    },
    backend => {
        timzone         => 'local',
        search_context  => 4,
        use_cache       => 1,
    },
);

sub import {
    unless (defined $path) {
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
    }
    unless (-d "$path/template") {
        die "Missing directory '$path/template'";
    }
    $config{config_root} = $path;
    $config{template}    = "$path/template";
    $config{backend}     = read_config_file("$path/backend.conf");
    if (defined $config{backend}{lib}) {
        unshift @INC, split /:/, $config{backend}{lib}
    }
    __PACKAGE__->export_to_level(1, __PACKAGE__, @EXPORT);
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

sub _template {
    my $name = shift;
    my $path = config('template') . "/$name.tmpl";
    return HTML::Template->new(
        filename            => $path,
        loop_context_vars   => 1,
        global_vars         => 1,
        die_on_bad_params   => 0,
        default_escape      => 'html',
        utf8                => 1,
    );
}

sub _backend {
    require Ilbot::Backend::SQL;
    my $sql = Ilbot::Backend::SQL->new(
        config  => config('backend'),
    );
    if (config(backend => 'use_cache')) {
        require Ilbot::Backend::Cached;
        return Ilbot::Backend::Cached->new(
            backend  => $sql,
        );
    }
    return $sql;
}

sub _frontend {
    require Ilbot::Frontend;
    my $f = Ilbot::Frontend->new(
        backend => _backend(),
    );
    if (config(www => 'use_cache')) {
        require Ilbot::Frontend::Cached;
        return Ilbot::Frontend::Cached->new(
            frontend => $f,
            backend  => $f->backend,
        );
    }
}

1;
