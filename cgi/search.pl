#!/usr/bin/perl
use warnings;
use strict;
use Date::Simple qw(today);
use CGI::Carp qw(fatalsToBrowser);
use Encode::Guess;
use CGI;
use Encode;
use HTML::Entities;
use HTML::Template;
use IrcLog qw(get_dbh my_decode message_line);
use IrcLog::WWW 'http_header';
use Config::File;
use List::Util qw(min);

my $conf = Config::File::read_config_file("cgi.conf");
my $base_url = $conf->{BASE_URL} || "/";
my $days_per_page = 10;
my $lines_per_day = 50; # not yet used
 
my $q = new CGI;
print http_header();
my $t = HTML::Template->new(filename => "search.tmpl",
		global_vars => 1);
$t->param(BASE_URL => $base_url);
my $start = $q->param("start") || 0;

my $offset = $q->param("offset") || 0;
die unless $offset =~ m/^\d+$/;

my $dbh = get_dbh();
{
    # populate the select box with possible channel names to search in
    my @channels; 
    my $q1 = $dbh->prepare("SELECT DISTINCT channel FROM irclog ORDER BY channel");
    $q1->execute();
    my $ch = $q->param('channel') || '';
    $t->param(CURRENT_CHANNEL => $ch);
    while (my @row = $q1->fetchrow_array){
        if ($ch eq $row[0]){
            push @channels, {CHANNEL => $row[0], SELECTED => 1};
        } else {
            push @channels, {CHANNEL => $row[0]};
        }
    }

    # populate the size of the select box with channel names
    $t->param(CHANNELS => \@channels);
    if (@channels >= 5 ){
        $t->param(CH_COUNT => 5);
    } else {
        $t->param(CH_COUNT => scalar @channels);
    }
}

$t->param(NICK => $q->param('nick'));


if (my $nick = $t->param('nick')){
    # search for a nick, populate 'DAYS' and result page links
    $nick = my_decode($nick);

    my $channel = my_decode($q->param('channel')) || die "No channel provided";

    my $q0 = $dbh->prepare("SELECT COUNT(DISTINCT day) FROM irclog "
			. "WHERE channel = ? AND (nick = ? OR nick = ?) AND NOT spam");
    my $q1 = $dbh->prepare("SELECT DISTINCT day FROM irclog "
			. "WHERE channel = ? AND ( nick = ? OR nick = ?) AND NOT spam "
			. "ORDER BY day DESC LIMIT $days_per_page OFFSET $offset");
    my $q2 = $dbh->prepare("SELECT id, timestamp, line FROM irclog "
			. "WHERE day = ? AND channel = ? AND (nick = ? OR nick = ?) "
			. "AND NOT spam ORDER BY id");

    $q0->execute($channel, $nick, "* $nick");
    my $result_count = ($q0->fetchrow_array);
    $t->param(DAYS_COUNT => $result_count);
    $t->param(DAYS_LOWER => $offset + 1);
    $t->param(DAYS_UPPER => min($offset + $days_per_page, $result_count));

    my @result_pages;
    my $p = 1;
    for (my $o = 0; $o <= $result_count; $o += $days_per_page){
	    push @result_pages, { OFFSET => $o, PAGE => $p++ };
    }
    $t->param(RESULT_PAGES => \@result_pages);

    $q1->execute($channel, $nick, "* $nick");
    my $short_channel = $channel;
    $short_channel =~ s/^#//;
    my @days;
    my $c = 0;
    while (my @row = $q1->fetchrow_array){
        my $prev_nick = "";
        my @lines;
        $q2->execute($row[0], $channel, $nick, "* $nick");
        while (my @r2 = $q2->fetchrow_array){
            my $line_number = get_line_number($channel, $row[0], $r2[0]);
            push @lines, message_line(
					$r2[0],  # id 
					$nick, 
                    $r2[1],  # timestamp
                    $r2[2],  # message
                    $line_number, 
                    \$c, $prev_nick, 
                    [], 
                    $base_url . "out.pl?channel=$short_channel;date=$row[0]",
                    );   
        }
        push @days, { 
            URL     => $base_url . "out.pl?channel=$short_channel;date=$row[0]",
            DAY     => $row[0],
            LINES   => \@lines,
        };
    }
    $t->param(DAYS => \@days);

}

print encode('utf-8', $t->output);

sub get_line_number {
#    my ($channel, $day, $timestamp) = @_;
    my $q1 = $dbh->prepare('SELECT COUNT(*) FROM irclog WHERE 
            channel = ? AND day = ? AND timestamp < ? AND NOT spam');
    $q1->execute(@_);
    my ($count) = $q1->fetchrow_array();
#    warn $count, $/;
    return $count + 1;
}
