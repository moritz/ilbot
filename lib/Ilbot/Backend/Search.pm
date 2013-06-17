package Ilbot::Backend::Search;

use Lucy::Index::Indexer;
use Lucy::Plan::Schema;
use Lucy::Analysis::PolyAnalyzer;
use Lucy::Plan::FullTextType;
use Lucy::Plan::Int64Type;

use Ilbot::Config;

sub indexer {
    my ($self, %opt) = @_;
    die 'Missing argument "channel"' unless $opt{channel};
    my $channel = $opt{channel};
    $channel =~ tr/a-zA-Z0-9_-//cd;
    # Create a Schema which defines index fields.
    my $schema = Lucy::Plan::Schema->new;
    my $polyanalyzer = Lucy::Analysis::PolyAnalyzer->new(
        language => config(search => 'language'),
    );
    my $type = Lucy::Plan::FullTextType->new(
        analyzer => $polyanalyzer,
    );
    $schema->spec_field( name => 'id',      type =>  Lucy::Plan::Int64Type->new() );
    $schema->spec_field( name => 'nick',    type => $type );
    $schema->spec_field( name => 'line',    type => $type );

    my $indexer = Lucy::Index::Indexer->new(
        schema => $schema,
        index  => join '/', config('config_root'), 'search-idx', $channel,
        create => 1,
    );
    return $indexer;
}
