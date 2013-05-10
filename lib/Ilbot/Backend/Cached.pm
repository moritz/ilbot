package Ilbot::Backend::Cached;

use strict;
use warnings;
use 5.010;

use Ilbot::Date qw/gmt_today/;
use Ilbot::Cache qw/cache/;
use CHI;

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend'" unless $opt{backend};
    return bless { backend => $opt{backend} }, $class;
}

sub channels {
    my $self = shift;
    cache(namespace => 'backend')->compute('channels', '2 hours', sub {
        $self->backend->channels;
    });
}

sub channel {
    my ($self, %opt) = @_;
    die "Missing option 'channel'" unless defined $opt{channel};
    Ilbot::Backend::Cached::Channel->new(
        backend => $self->backend->channel(channel => $opt{channel}),
        channel => $opt{channel}
    );
}

sub backend { $_[0]{backend} }


package Ilbot::Backend::Cached::Channel;

use Ilbot::Cache qw/cache/;

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend'" unless $opt{backend};
    die "Missing option 'channel'" unless defined $opt{channel};
    return bless { backend => $opt{backend}, channel => $opt{channel} }, $class;
}
sub backend { $_[0]{backend} }
sub channel { $_[0]{channel} }

sub day_has_activity {
    my ($self, %opt) = @_;
    my $day = $opt{day};
    my $cache_key = join '|', 'day_has_activity', $self->channel, $day;
    die "Missing option 'day'" unless defined $day;
    my $cache = cache(namespace => 'backend');
    if ($day eq gmt_today()) {
        my $res = $cache->get($cache_key);
        return $res if $res;
        $res = $self->backend->day_has_activity(day => $day);
        $cache->set($cache_key, $res) if $res;
        return $res;
    }
    $cache->compute($cache_key, undef, sub {
        $self->backend->day_has_activity(%opt);
    });
}

sub days_and_activity_counts {
    my $self = shift;
    my $cache_key = join '|', 'days_and_activity_counts', $self->channel, gmt_today();
    cache(namespace => 'backend')->compute($cache_key, '1 hour', sub {
        $self->backend->days_and_activity_counts;
    });
}

sub lines {
    my ($self, %opt) = @_;
    $opt{day}           //= die "Missing option 'day'";
    $opt{exclude_spam}  //= 1;
    $opt{summary_only}  //= 0;

    # for now, don't cache for today at all:
    return $self->backend->lines(%opt) if $opt{day} eq gmt_today();

    my $cache_key = join '|', 'lines', @opt{qw/day exclude_spam summary_only/};
    cache(namespace => 'backend')->compute($cache_key, undef, sub { $self->backend->lines(%opt) });
}

sub activity_average {
    my $self = shift;
    my $cache_key = join '|', 'activity_average', $self->channel;
    cache(namespace => 'backend')->compute($cache_key, '1 day', sub { $self->backend->activity_average } );
}


1;
