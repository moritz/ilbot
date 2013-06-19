package Ilbot::Backend::Search;
use strict;
use warnings;
use 5.010;

use Lucy::Index::Indexer;
use Lucy::Plan::Schema;
use Lucy::Analysis::PolyAnalyzer;
use Lucy::Plan::FullTextType;

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

    $| = 1;
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
    $schema->spec_field( name => 'ids',     type => Lucy::Plan::StringType->new( indexed => 0, sortable => 0) );
    $schema->spec_field( name => 'day',     type => Lucy::Plan::StringType->new( indexed => 0, sortable => 1));
    $schema->spec_field( name => 'nick',    type => $type );
    $schema->spec_field( name => 'line',    type => $type );

    my $indexer = Lucy::Index::Indexer->new(
        schema => $schema,
        index  => join('/', config('search_idx_root'), $channel),
        create => 1,
    );
    return $indexer;
}

sub index_all {
    my $self = shift;
    my $count++;
    for my $channel (@{ $self->backend->channels }) {
        my $b = $self->backend->channel(channel => $channel);
        my $i = $self->indexer(channel => $channel);
        say '';
        say $channel;
        for my $d (@{ $b->days_and_activity_counts }) {
            my $day = $d->[0];
            print "\r$day";
            my $prev;
            for my $line (@{ $b->lines(day => $day) }) {
                my ($id, undef, $nick, $line) = @$line;
                next unless defined $nick;
                $nick =~ s/^\*\s*//;
                if ($prev && $prev->{nick} eq $nick) {
                    $prev->{ids} .= ",$id";
                    $prev->{line} .= "\n$line";
                }
                else {
                    ++$count, $i->add_doc($prev) if $prev;
                    $prev = {
                        ids     => $id,
                        nick    => $nick,
                        line    => $line,
                        day     => $day,
                    };
                }
            }
            ++$count, $i->add_doc($prev) if $prev;
        }
        print "\rcommitting ...";
        $i->commit;
        print "\roptimizing ...";
        $i->optimize;
        print "\rdone optimizing";
    }
    return $count;
}

1;
