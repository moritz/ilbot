package Ilbot::Cache;
use strict;
use warnings;
use Exporter qw/import/;
our @EXPORT_OK = qw/cache/;
use Memoize;
use CHI;

memoize('cache');

sub cache {
    my (%opt) = @_;
    my $namespace = $opt{namespace};
    $namespace = $namespace ? "ilbot-$namespace" : 'ilbot';
    CHI->new(
        driver      => 'File',
        root_dir    => '/tmp/CHI/ilbot/',
        namespace   => $namespace,
    );
}


1;
