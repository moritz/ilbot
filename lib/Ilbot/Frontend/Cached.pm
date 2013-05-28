package Ilbot::Frontend::Cached;
use strict;
use warnings;
use 5.010;

use Ilbot::Config;
use Ilbot::Cache qw/cache/;
use Ilbot::Date qw/today/;

my $cache = cache('namespace' => 'frontend');

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend"  unless $opt{backend};
    die "Missing option 'frontend" unless $opt{frontend};
    return bless {backend => $opt{backend}, frontend => $opt{frontend} }, $class;
}

sub backend  { $_[0]{backend}  }
sub frontend { $_[0]{frontend} }

sub index {
    my $self = shift;
    $cache->compute("index", undef, sub {
            $self->frontend->index;
    });
}

sub channel_index {
    my ($self, %opt) = @_;
    die "Missing option 'channel'" unless $opt{channel};
    my $cache_key = join '|', 'channel_index', $self->backend->channels;
    $cache->compute($cache_key, '3 days', sub { $self->frontend->channel_index(%opt) });
}

sub day {
    my ($self, %opt) = @_;
    die 'Missing attribute "channel"' unless defined $opt{channel};
    die 'Missing attribute "day"'     unless defined $opt{day};
    # TODO: cache if number of lines stayed the same
    return $self->frontend->day(%opt) if $opt{day} eq today();
    # TODO: this messes up the summary :/
    my $cache_key = join '|', 'day', $opt{channel}, $opt{day};
    $cache->compute($cache_key, '3 days', sub { $self->frontend->day(%opt) });
}

sub day_text {
    my ($self, %opt) = @_;
    die 'Missing attribute "channel"' unless defined $opt{channel};
    die 'Missing attribute "day"'     unless defined $opt{day};
    # TODO: cache if number of lines stayed the same
    return $self->frontend->day(%opt) if $opt{day} eq today();
    my $cache_key = join '|', 'day', $opt{channel}, $opt{day};
    $cache->compute($cache_key, '1 year', sub { $self->frontend->day(%opt) });
}

sub update_summary {
    my ($self, %opt) = @_;
    $self->backend->update_summary(%opt);
}

sub search { shift->frontend->search(@_) }
sub http_header { shift->frontend->http_header(@_) }

1;
