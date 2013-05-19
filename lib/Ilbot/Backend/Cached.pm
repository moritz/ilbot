package Ilbot::Backend::Cached;

use strict;
use warnings;
use 5.010;

use Ilbot::Date qw/today/;
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

# XXX this might be abused for DoS-attacks, because it allows flushing
# most caches with little effort. If this proves to be a problem in
# practise, the cache flushing should be removed, and out-of-dateness of
# summaries accepted
sub update_summary {
    my ($self, %opt) = @_;
    $self->backend->update_summary(%opt);
    my %seen;
    my @all_ids = grep !$seen{$_}++, @{ $opt{check} // [] }, @{ $opt{uncheck} // [] };
    my $c_d = $self->backend->channels_and_days_for_ids(ids => \@all_ids);
    my $cache = cache(namespace => 'backend');
    for my $cd (@$c_d) {
        my ($channel, $day) = @$cd;
        for my $summary (0, 1) {
            for my $spam (0, 1) {
                my $key = join '|', 'lines', $channel, $day, $spam, $summary;
                $cache->remove($key);
            }
        }
    }

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
use Ilbot::Date qw/today/;

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
    if ($day eq today()) {
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
    my $cache_key = join '|', 'days_and_activity_counts', $self->channel, today();
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
    return $self->backend->lines(%opt) if $opt{day} eq today();

    my $cache_key = join '|', 'lines', $self->channel, @opt{qw/day exclude_spam summary_only/};
    cache(namespace => 'backend')->compute($cache_key, undef, sub { $self->backend->lines(%opt) });
}

sub activity_average {
    my $self = shift;
    my $cache_key = join '|', 'activity_average', $self->channel;
    cache(namespace => 'backend')->compute($cache_key, '1 day', sub { $self->backend->activity_average } );
}

sub search_count {
    my $self = shift;
    $self->backend->search_count(@_);
}
sub search_results {
    my $self = shift;
    $self->backend->search_results(@_);
}


1;
