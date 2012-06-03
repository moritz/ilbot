#!/usr/bin/env perl
use strict;
use warnings;
use Calendar::Simple;
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use Config::File;
use HTML::Template;
use Cache::FileCache;
use lib 'lib';
use IrcLog qw(get_dbh gmt_today);
use File::Slurp qw/read_file/;
use Plack::Request;
use Plack::Response;

my $conf     = Config::File::read_config_file('www/www.conf');


sub test_calendar {
    my $channel  = '#parrotsketch';
    my $base_url = '/irclog/';
    my $dates    = [qw( 2009-09-28 2009-09-30
                        2009-10-01 2009-10-02 2009-10-05 2009-10-12 )];

    print calendar_for_channel($channel, $dates, $base_url);
}

sub get_channel_index {
    my $channel  = shift;
    my $base_url = $conf->{BASE_URL} || q{/};

    my $t = HTML::Template->new(
            filename            => 'www/template/channel-index.tmpl',
            die_on_bad_params   => 0,
    );

    # we are evil and create a calendar entry for month between the first
    # and last date
    my $dbh       = get_dbh();
    my $get_dates = 'SELECT DISTINCT day FROM irclog WHERE channel = ? ORDER BY day';
    my $dates     = $dbh->selectcol_arrayref($get_dates, undef, '#' . $channel);

    $t->param(CHANNEL  => $channel);
    $t->param(BASE_URL => $base_url);
    $t->param(CALENDAR => calendar_for_channel($channel, $dates, $base_url));

    my $clf = "channels/$channel.tmpl";
    if (-e $clf) {
        $t->param(CHANNEL_LINKS => q{} . read_file($clf));
    }

    return $t->output;
}

sub calendar_for_channel {
    my ($channel, $dates, $base_url)  = @_;
    $channel =~ s/\A\#//smx;

    my (%months, %link);
    for my $date (@$dates) {
        my ($Y, $M, $D) = split '-', $date;
        $link{$date}    = "$base_url$channel/$date";
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

                if ($day) {
                    my $D    = sprintf '%02d', $day;
                    my $link = $link{"$Y-$M-$D"};
                    $content = $link ? qq{<a href="$link">$day</a>}
                                     : $day;
                }

                $html .= qq{<td>$content</td>};
            }

            $html .= qq{</tr>\n};
        }

        $html .= qq{</tbody>\n</table>\n};
    }

    $html .= qq{</div>\n};

    return $html;
}

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $channel = $req->path;
    $channel =~ s{^/}{};
    $channel =~ s{/$}{};

    my $response = Plack::Response->new(200);
    $response->headers([ 'Content-Type' => 'text/html; charset=utf-8' ]);

    if ($conf->{NO_CACHE}) {
        $response->body( get_channel_index($channel) );
    } else {
        my $cache_name = $channel . '|' . gmt_today();
        my $cache      = new Cache::FileCache({ namespace => 'irclog' });
        my $data       = $cache->get($cache_name);

        if (! defined $data) {
            $data = get_channel_index($channel);
            $cache->set($data, '2 hours');
        }

        $response->body($data);
    }
    return $response->finalize;
};

# vim: syn=perl sw=4 ts=4 expandtab
