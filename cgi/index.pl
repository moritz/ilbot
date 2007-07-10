#!/usr/bin/perl
use warnings;
use strict;
use Date::Simple qw(date);
use CGI::Carp qw(fatalsToBrowser);
use Encode::Guess;
use CGI;
use Encode;
use HTML::Entities;
use HTML::Template;
use Config::File;
use IrcLog qw(get_dbh);
use IrcLog::WWW 'http_header';
use HTML::Calendar::Simple;

my $conf = Config::File::read_config_file("cgi.conf");
my $base_url = $conf->{BASE_URL} || "/";
 
my $q = new CGI;
print http_header();
my $t = HTML::Template->new(filename => "index.tmpl");

my $dbh = get_dbh();
my @channels; 
{
    my $q1 = $dbh->prepare("SELECT DISTINCT channel FROM irclog ORDER BY channel");
    $q1->execute();
    while (my @row = $q1->fetchrow_array){
        push @channels, $row[0];
    }
}

# we are evil and create a calendar entry for month between the first and last
# date
my $q2 = $dbh->prepare("SELECT MIN(day), MAX(day) FROM irclog WHERE channel = ?");

my $q3 = $dbh->prepare("SELECT COUNT(day) FROM irclog WHERE day = ?");
sub date_exists_in_db {
    my $date = shift;
    $q3->execute($date);
    my ($count) = $q3->fetchrow_array();
    return scalar $count;
}

my @t_channels;

foreach my $ch (@channels){
    my @dates;
    my $short_channel = substr $ch, 1;
    $q2->execute($ch);
    my ($min_day, $max_day) = $q2->fetchrow_array;
    push @t_channels, {
        CHANNEL  => $ch, 
        CALENDAR => calendar_for_range($min_day, $max_day, $ch),
    }
}
$t->param(CHANNELS => \@t_channels);
print $t->output;

sub calendar_for_range {
    my ($min_day, $max_day, $channel) = @_;
    $channel =~ s/^#//;

    my ($current_year, $current_month) = split /-/, $min_day;
    my ($max_year, $max_month) = split /-/, $max_day;

    my $cal_str = qq{};

    my $current_day = date($min_day);
    while ($current_year + 12 * $current_month <= $max_year + 12 * $max_month){
        # generate calendar for this month;
        my $cal = HTML::Calendar::Simple->new({
                year  => $current_year,
                month => $current_month,
                });

        while ($current_day->month == $current_month){
            if (date_exists_in_db($current_day)){
                $cal->daily_info({
                        day      => $current_day->day,
                        day_link => $base_url . "out.pl?channel=$channel;date=$current_day",
                        });

            }
            $current_day++;
        }

        $cal_str = qq{<div class="calendar">} 
                  . $cal->calendar_month
                  . qq{</div>\n}
                  . $cal_str;

        # move on to next month
        $current_month++;
        if ($current_month == 13){
            $current_month = 1;
            $current_year++;
        }
    }

    return $cal_str;
}

#vim: syn=perl;sw=4;ts=4;expandtab
