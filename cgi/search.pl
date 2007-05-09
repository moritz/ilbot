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
use IrcLog qw(get_dbh my_encode message_line);
use Config::File;

my $conf = Config::File::read_config_file("cgi.conf");
my $base_url = $conf->{BASE_URL} || "/";
 
my $q = new CGI;
print "Content-Type: text/html; charset=UTF-8\n\n";
my $t = HTML::Template->new(filename => "search.tmpl");

my $dbh = get_dbh();
{
    # populate the select box with possible channel names to search in
    my @channels; 
    my $q1 = $dbh->prepare("SELECT DISTINCT channel FROM irclog ORDER BY channel");
    $q1->execute();
    my $ch = $q->param('channel') || '';
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
    # search for a nick, populate 'DAYS'
    $nick = my_encode($nick);

    my $channel = my_encode($q->param('channel')) || die "No channel provided";

    my $q1 = $dbh->prepare("SELECT DISTINCT day FROM irclog WHERE channel = ? AND ( nick = ? OR nick = ?) ORDER BY day DESC");
    my $q2 = $dbh->prepare("SELECT timestamp, line FROM irclog WHERE day = ? AND channel = ? AND (nick = ? OR nick = ?)");

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
            push @lines, message_line($nick, 
                    $r2[0],  #timestamp
                    $r2[1],  # message
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
            channel = ? AND day = ? and timestamp < ?');
    $q1->execute(@_);
    my ($count) = $q1->fetchrow_array();
#    warn $count, $/;
    return $count;
}
