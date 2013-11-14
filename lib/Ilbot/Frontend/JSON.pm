package Ilbot::Frontend::JSON;
use 5.010;
use strict;
use warnings;

use Ilbot::Config;
use Ilbot::Date qw/today/;

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend" unless $opt{backend};
    return bless {backend => $opt{backend} }, $class;
}

sub backend { $_[0]{backend} }

sub index {
    my $self = shift;
    my %channels;
    for my $channel (@{ $self->backend->channels }) {
        (my $stripped = $channel) =~ s/^#+//;
        $channels{$channel} = config(www => 'base_url') . "$stripped/";
    }
    return \%channels;
}

sub channel_index {
    my ($self, %opt) = @_;
    die "Missing option 'channel'" unless $opt{channel};
    my $b = $self->backend->channel(channel => '#' . $opt{channel});
    my %links;
    my $prefix = config(www => 'base_url') . "$opt{channel}/";
    for my $c (@{ $b->days_and_activity_counts }) {
        $links{ $c->[0] } = $prefix . $c->[0];
    }
    return \%links;
}

sub day {
    my ($self, %opt) = @_;
    $opt{day} //= today();
    for my $attr (qw/channel/) {
        die "Missing argument '$attr'" unless defined $opt{$attr};
    }
    my $channel = $opt{channel};
    $channel =~ s/^\#+//;

    my $b         = $self->backend->channel(channel => '#' . $channel);
    return unless $b->exists;
    return if $opt{day} gt today();
    return if $opt{day} lt $b->first_day;

    my $rows      = $b->lines(
        day          => $opt{day},
        summary_only => 0,
    );

    my %response = (
        channel     => $opt{channel},
        day         => $opt{day},
        header      => [qw/id nick timestamp line/],
        rows        => $rows,
    );
    return \%response;
}

1;
