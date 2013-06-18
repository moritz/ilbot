package Ilbot::Backend::Search;
use strict;
use warnings;

use Lucy::Index::Indexer;
use Lucy::Plan::Schema;
use Lucy::Analysis::PolyAnalyzer;
use Lucy::Plan::FullTextType;
use Lucy::Plan::Int64Type;

use Ilbot::Config;

sub new {
    my ($class, %opt) = @_;
    my %self;
    for my $arg (qw/backend/) {
        die "Missing argument $arg" unless defined $opt{$arg};
        $self{$arg} = $opt{$arg};
    }
    return bless \%self, $class;
}

sub backend { $_[0]->{backend} };

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
    $schema->spec_field( name => 'id',      type => Lucy::Plan::Int64Type->new() );
    $schema->spec_field( name => 'day',     type => Lucy::Plan::StringType->new);
    $schema->spec_field( name => 'nick',    type => $type );
    $schema->spec_field( name => 'line',    type => $type );

    my $indexer = Lucy::Index::Indexer->new(
        schema => $schema,
        index  => join('/', config('config_root'), '../search-idx', $channel),
        create => 1,
    );
    return $indexer;
}

sub index_all {
    my $self = shift;
    for my $channel (@{ $self->backend->channels }) {
        my $b = $self->backend->channel(channel => $channel);
        my $i = $self->indexer(channel => $channel);
        for my $d (@{ $b->days_and_activity_counts }) {
            my $day = $d->[0];
            for my $line (@{ $b->lines(day => $day) }) {
                $i->add_doc({
                    day     => $day,
                    id      => $line->[0],
                    nick    => $line->[1],
                    line    => $line->[3],
                });
            }
        }
        $i->commit;
    }

}

1;
