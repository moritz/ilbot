package Ilbot::Frontend;
use strict;
use warnings;
use 5.010;
use HTML::Template;

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend" unless $opt{backend};
    return bless {backend => $opt{backend} }, $class;
}

sub config {
    my ($self, %opt) = @_;
    my $key = $opt{key};
    die "Missing option 'key'" unless $key;
    my %defaults = (
        base_url        => '/',
        activity_images => 0,
    );
    return $self->{config}{uc $key}
            // $defaults{lc $key}
            // die "No config found for '$key'";
}

sub index {
    my ($self, %opt) = @_;
    die "Missing option 'out_fh'" unless $opt{out_fh};
    my $template = HTML::Template->new(
        filename            => 'template/index.tmpl',
        loop_context_vars   => 1,
        global_vars         => 1,
        die_on_bad_params   => 0,
    );
    my @channels;
    my $has_images = 0;
    for my $channel (@{ $self->backend->channels }) {
        next unless $channel =~ s/^\#+//;
        my %data = (channel => $channel);
        if ($self->config(key => 'activity_images')) {
            my $filename = $channel;
            $filename =~ s/[^\w-]+//g;
            $filename = "images/index/$filename.png";
            if (-e $filename) {
                $data{image_path}   = $filename;
                $has_images         = 1;
            }
        }
        push @channels, \%data;
    }

    $template->param(has_images => $has_images);
    $template->param(base_url   => $self->config(key => 'base_url'));
    $template->param(channels   => \@channels);
    $template->output(print_to => $opt{out_fh});
}

sub channel_index {
    my ($self, %opt) = @_;
    die "Missing option 'out_fh'"  unless $opt{out_fh};
    die "Missing option 'channel'" unless $opt{channel};
    my $t = HTML::Template->new(
        filename            => 'template/channel-index.tmpl',
        die_on_bad_params   => 0,
    );
    my $b = $self->backend->channel(channel => $opt{channel});
    $t->param(channel   => $opt{channel});
    $t->param(base_url  => $self->config(key => 'base_url'));
    $t->param(calendar  => $self->calendar(
                channel             => $opt{channel},
                dates_and_counts    => $b->dates_and_counts,
                base_url            => $self->config(key => 'base_url'),
                average             => $b->activity_average(),
            ),
    );
}

sub calendar {
    my ($self, %opt) = @_;
    my $channel = $opt{channel} // die 'Missing Option "channel"';
    my $average = $opt{average} // die 'Missing Option "average"';
    my $base_url= $opt{base_url} // die 'Missing option "base_url"';
    my $dates_and_counts = $opt{dates_and_counts} // die "Missing Option 'dates_and_counts'";
    $channel =~ s/\A\#//smx;
    my (%months, %link, %count);
    for my $e (@$dates_and_counts) {
        my ($date, $count) = @$e;
        my ($Y, $M, $D) = split '-', $date;
        $link{$date}    = "$base_url$channel/$date";
        $count{$date}   = $count;
        $months{"$Y-$M"}++;
    }

    my @months  = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
    my @days    = qw( S M T W T F S );
    my $dayhead = join '' => map "<th>$_</th>" => @days;
    my $html    = qq{<div class="calendars">\n};

    require Calendar::Simple;

    my %cals;
    for my $month (reverse sort keys %months) {
        my  ($Y, $M) = split '-', $month;
        my   $title  = $months[$M - 1] . ' ' . $Y;
        my   @weeks  = Calendar::Simple::calendar($M, $Y);
        push @weeks, [] while @weeks < 6;

        $html .= qq{<table class="calendar">\n<thead>\n<tr class="calendar_title"><th colspan="7">$title</th></tr>\n<tr class="day_names">$dayhead</tr>\n</thead>\n<tbody>\n};

        for my $week (@weeks) {
            $html .= qq{<tr>};

            for my $day_num (0 .. 6) {
                my $day     = $week->[$day_num];
                my $content = '';
                my $style = '';

                if ($day) {
                    my $D       = sprintf '%02d', $day;
                    my $link = $link{"$Y-$M-$D"};
                    $content = $link ? qq{<a href="$link">$day</a>}
                                     : $day;
                    if ($link) {
                        use constant W => 74;
                        my $rel_count = W / 2 * $count{"$Y-$M-$D"} / $average;
                        $rel_count    = W if $rel_count > W;
                        my $c         = sprintf '%x', 255 - $rel_count;
                        $style = qq[ style="background-color: #$c$c$c;"];
                    }
                }

                $html .= qq{<td$style>$content</td>};
            }

            $html .= qq{</tr>\n};
        }

        $html .= qq{</tbody>\n</table>\n};
    }

    $html .= qq{</div>\n};

    return $html;
}

