package Ilbot::Frontend;
use strict;
use warnings;
use 5.010;

use Ilbot::Config;
use Ilbot::Date qw/today mytime/;
use Ilbot::Frontend::NickColor qw/nick_to_color/;
use Ilbot::Frontend::TextFilter qw/text_filter/;

use Config::File;
use Date::Simple qw/date/;
use HTML::Entities qw(encode_entities);
use Encode qw/encode_utf8/;

use Data::Dumper;

use constant ENTITIES => qq{<>"&};
use constant NBSP => "\xa0";


sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend" unless $opt{backend};
    return bless {backend => $opt{backend} }, $class;
}

sub backend { $_[0]{backend} }

sub index {
    my ($self, %opt) = @_;
    my $template = Ilbot::Config::_template('index');
    my @channels;
    my $has_images = 0;
    my $path = config(www => 'static_path') . '/';
    for my $channel (@{ $self->backend->channels }) {
        next unless $channel =~ s/^\#+//;
        my %data = (channel => $channel);

        my $filename = $channel;
        $filename =~ s/[^\w-]+//g;
        $filename = "s/images/index/$filename.png";
        if (-e "$path/$filename") {
            $data{image_path}   = $filename;
            $has_images         = 1;
        }
        push @channels, \%data;
    }

    $template->param(has_images => $has_images);
    $template->param(base_url   => config(www => 'base_url'));
    $template->param(channels   => \@channels);
    return $template->output();
}

sub channel_index {
    my ($self, %opt) = @_;
    die "Missing option 'channel'" unless $opt{channel};
    my $b = $self->backend->channel(channel => '#' . $opt{channel});
    return unless $b->exists;
    my $t = Ilbot::Config::_template('channel-index');
    $t->param(channel   => $opt{channel});
    $t->param(base_url  => config(www => 'base_url'));
    $t->param(calendar  => $self->calendar(
                channel             => $opt{channel},
                dates_and_counts    => $b->days_and_activity_counts,
                base_url            => config(www => 'base_url'),
                average             => $b->activity_average(),
            ),
    );
    return $t->output();
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

sub day {
    my ($self, %opt) = @_;
    $opt{day} //= today();
    for my $attr (qw/channel/) {
        die "Missing argument '$attr'" unless defined $opt{$attr};
    }
    my $channel = $opt{channel};
    $channel =~ s/^\#+//;
    my $full_channel = q{#} . $channel;
    my $b         = $self->backend->channel(channel => $full_channel);
    return unless $b->exists;
    return if $opt{day} gt today();
    return if $opt{day} lt $b->first_day;

    my $t = Ilbot::Config::_template('day');
    {
        my $clf = "channels/$channel.tmpl";
        if (-e $clf) {
            open my $IN, '<', $clf;
            my $contents = do { local $/; <$clf> };
            close $IN;
            $t->param(CHANNEL_LINKS => $contents);
        }
    }
    my $base_url = config(www => 'base_url');
    $t->param(base_url  => $base_url);
    my $rows      = $b->lines(day => $opt{day}, summary_only => $opt{summary});
    my $line_no   = 0;
    my $prev_nick = q{!!!};
    my $c         = 0;
    my @msg;
    my $self_url  = $base_url . join '/',  $channel, $opt{day};
    for my $row (@$rows) {
        my $id          = $row->[0];
        my $nick        = $row->[1];
        my $timestamp   = $row->[2];
        my $message     = $row->[3];
        next if $message =~ m/^\s*\[off\]/i;
        push @msg, $self->message_line( {
                id           => $id,
                nick        => $nick,
                timestamp   => $timestamp,
                message     => $message,
                line_number =>  ++$line_no,
                prev_nick   => $prev_nick,
                color       => nick_to_color($nick),
                self_url    => $self_url,
                channel     => $channel,
            },
            \$c,
        );
        $prev_nick = $nick;
    }
    $t->param(
        CHANNEL     => $channel,
        MESSAGES    => \@msg,
        DATE        => $opt{day},
        IS_SUMMARY  => $opt{summary},
    );
    my $prev = date($opt{day}) - 1;
    $t->param(PREV_DATE => $prev, PREV_URL => "$base_url$opt{channel}/$prev");
    my $next = date($opt{day}) + 1;
    $t->param(NEXT_DATE => $next, NEXT_URL => "$base_url$opt{channel}/$next");
    return $t->output;
}

sub day_text {
    my ($self, %opt) = @_;
    $opt{day} //= today();
    for my $attr (qw/channel/) {
        die "Missing argument '$attr'" unless defined $opt{$attr};
    }
    my $channel = $opt{channel};
    $channel =~ s/^\#+//;
    my $b = $self->backend->channel(channel => "#$channel");
    return unless $b->exists;
    return if $opt{day} gt today();
    return if $opt{day} lt $b->first_day;
    require Text::Table;
    my $table = Text::Table->new(qw/Time Nick Message/);
    for my $row (@{ $b->lines(day => $opt{day}) }) {
        my ($nick, $ts, $line) = ($row->[1], $row->[2], $row->[3]);

		my ($hour, $minute) = (mytime $ts)[2, 1];

        $table->add(sprintf("%02d:%02d", $hour, $minute), $nick, $line);
    }
    my $text = "$table";
    $text =~ s/\h+$//gm;
    return $text;
}

sub update_summary {
    my ($self, %opt) = @_;
    $self->backend->update_summary(%opt);
}

sub message_line {
    my ($self, $args_ref, $c) = @_;
    my $nick = $args_ref->{nick} // '';
    my %h = (
        ID          => $args_ref->{id},
        TIME        => format_time($args_ref->{timestamp}),
        MESSAGE     => text_filter($args_ref->{message},
                            {
                                channel => $args_ref->{channel},
                                nick    => $args_ref->{nick},
                            }
                        ),
        LINE_NUMBER => ++$args_ref->{line_number},
    );
    $h{DATE}         = $args_ref->{date} if $args_ref->{date};
    $h{SEARCH_FOUND} = 'search_found' if ($args_ref->{search_found});

    my @classes;
    my @msg_classes;
    my $display_nick = $nick;
    $display_nick =~ s/\A\*\ /'*' . NBSP/exms;
    $h{NICK} = encode_entities($display_nick, ENTITIES);
    if ($nick ne ($args_ref->{prev_nick} // '')) {
        # $c++ is used to alternate the background color
        $$c++;
        push @classes, 'new';
    } else {
        # omit nick in successive lines from the same nick
        push @classes, 'cont';
    }

    if ($nick =~ /\A\*\ /smx) {
        push @msg_classes, 'act';
    }

    if ($nick eq ""){
        # empty nick column means that nobody said anything, but
        # it's a join, part, topic change etc.
        push @classes, "special";
        $h{SPECIAL} = 1;
    }
    else {
        # To ensure successive lines from same nick are displayed, we want
        # both these classes on every non-special <tr>
        push @classes, ( "nick", "nick_".sanitize_nick($nick) );
    }

    if ($$c % 2){
        push @classes, "dark";
    }
    if (@classes){
        $h{CLASS} = join " ", @classes;
    }
    if (@msg_classes) {
        $h{MSG_CLASS} = join " ", @msg_classes;
    }
    $h{NICK_COLOR} = $args_ref->{color};

    return \%h;
}

sub search {
    my ($self, %opt) = @_;
    die "Missing parameter 'channel'" unless defined $opt{channel};
    my $b = $self->backend->channel(channel => '#' . $opt{channel});
    return unless $b->exists;
    $opt{offset} //= 0;
    my $t = Ilbot::Config::_template('search');
    $t->param(channel  => $opt{channel});
    $t->param(base_url => config(www => 'base_url'));
    $t->param(nick     => $opt{nick});
    $t->param(q        => $opt{q});
    my $c = 0;
    my $prev_nick = q[!!!];
    my $line_number = 0;
    if (defined $opt{q} && length $opt{q}) {
        my $res = $b->search_results(
            nick    => $opt{nick},
            q       => $opt{q},
            offset  => $opt{offset} // 0,
        );
        my $count = $res->{total};
        if ($count == 0) {
            $t->param(no_results => 1);
        }
        else {
            $t->param(result_count => $count);
            my @pages;
            for (0..int(($count - 1) / 100)) {
                push @pages, {
                    offset  => $_ * 100,
                    page    => $_ + 1,
                    is_this => ($_ * 100 == $opt{offset}),
                };
            }
            $t->param(result_pages => \@pages);
            my @t;
            while (my ($day, $lines) = splice @{ $res->{days} }, 0, 2) {
                my %h = (day => $day);
                my @lines;
                for (@$lines) {
                    push @lines, $self->message_line({
                        id          => $_->[0],
                        nick        => $_->[1],
                        timestamp   => $_->[2],
                        message     => $_->[3],
                        search_found => $_->[4],
                        prev_nick   => $prev_nick,
                        date        => $day,
                        channel     => $opt{channel},
                        line_number => ++$line_number,
                    }, \$c);
                    $prev_nick = $_->[1];
                }
                $h{lines} = \@lines;
                push @t, \%h;
            }
            $t->param(results => \@t);
        }
    }
    return $t->output;
}

sub summary_ids {
    my ($self, %opt) = @_;
    for (qw/channel day/) {
        die "Missing argument '$_'" unless defined $opt{$_};
    }
    my $b   = $self->backend->channel(channel => $opt{channel});
    my $ids = $b->summary_ids(day => $opt{day});
    # crude way to generate JSON, I know
    return '['
        . join(',', @$ids)
        . ']';
}


sub http_header {
    my ($self, %opt) = @_;

    my $type   = ($opt{accept} // '') =~ m{\Qapplication/xhtml+xml\E}
                    ? 'application/xhtml+xml'
                    : 'text/html';
    my @h = (
        'Vary'              => 'Accept',
        'Content-Language'  => 'en',
        'Content-Type'      => "$type; charset=utf-8",
    );

    if (config(www => 'no_cache')) {
        push @h, 'Cache-Control' => 'no-cache';
    }

    return \@h;
}

sub format_time {
    my $d = shift;
    my @times = mytime($d);
    return sprintf("%02d:%02d", $times[2], $times[1]);
}

sub sanitize_nick {
    my $nick = shift;
    $nick =~ s/[^-a-zA-Z0-9_]//g;
    return $nick;
}


1;
