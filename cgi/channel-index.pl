#!/usr/bin/env perl
use strict;
use warnings;
use Calendar::Simple qw(calendar);
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use Config::File;
use HTML::Template;
use Cache::FileCache;
use lib 'lib';
use IrcLog qw(get_dbh gmt_today);
use File::Slurp qw/read_file/;

my $conf     = Config::File::read_config_file('cgi.conf');

# test_calendar();
go();

sub go {
    my $q = CGI->new;
    my $channel = $q->url_param('channel');
    print "Content-Type: text/html; charset=utf-8\n\n";

    if ($conf->{NO_CACHE}) {
        print get_channel_index($channel);
    } else {
        my $cache_name = $channel . '|' . gmt_today();
        my $cache      = new Cache::FileCache({ namespace => 'irclog' });
        my $data       = $cache->get($cache_name);

        if (! defined $data) {
            $data = get_channel_index($channel);
            $cache->set($data, '2 hours');
        }

        print $data;
    }
}

sub get_channel_index {
    my $channel  = shift;
    my $base_url = $conf->{BASE_URL} || q{/};

    my $t = HTML::Template->new(
            filename            => 'template/channel-index.tmpl',
            die_on_bad_params   => 0,
    );

    # we are evil and create a calendar entry for month between the first
    # and last date
    my $dbh       = get_dbh();
    my $get_dates = q[SELECT day, count(*) FROM irclog WHERE channel = ? AND nick <> '' GROUP BY day ORDER BY day];
    my $dates_and_counts = $dbh->selectall_arrayref($get_dates, undef, '#' . $channel);

    my $sth       = $dbh->prepare(q[SELECT COUNT(*), DATEDIFF(DATE(MAX(day)), DATE(MIN(day))) FROM irclog WHERE channel = ? AND nick <> '']);
    $sth->execute('#' . $channel);
    my ($count, $days) = $sth->fetchrow;
    $sth->finish;
    my $average = $count / ($days || 1);

    $t->param(CHANNEL  => $channel);
    $t->param(BASE_URL => $base_url);
    $t->param(CALENDAR => calendar_for_channel($channel, $dates_and_counts, $base_url, $average));

    my $clf = "channels/$channel.tmpl";
    if (-e $clf) {
        $t->param(CHANNEL_LINKS => q{} . read_file($clf));
    }

    return $t->output;
}

sub calendar_for_channel {
    my ($channel, $dates_and_counts, $base_url, $average)  = @_;
    $channel =~ s/\A\#//smx;
    $average ||= 1;

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

    my %cals;
    for my $month (reverse sort keys %months) {
        my  ($Y, $M) = split '-', $month;
        my   $title  = $months[$M - 1] . ' ' . $Y;
        my   @weeks  = calendar($M, $Y);
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
                        use constant W = 74;
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

# vim: syn=perl sw=4 ts=4 expandtab
