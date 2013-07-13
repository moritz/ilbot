package Ilbot::Cache;
use strict;
use warnings;
use Exporter qw/import/;
our @EXPORT_OK = qw/cache/;
use Memoize;
use CHI;

use Ilbot::Config;

memoize('cache');

sub cache {
    my (%opt) = @_;
    return FakeCache->new unless config(backend => 'use_cache');
    my $namespace = $opt{namespace};
    $namespace = $namespace ? "ilbot-$namespace" : 'ilbot';
    CHI->new(
        driver      => 'File',
        root_dir    => '/tmp/CHI/ilbot/',
        namespace   => $namespace,
    );
}

{
    package FakeCache;
    sub new { bless [], shift };
    sub delete { };
}


1;
