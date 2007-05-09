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
use Config::File;
use IrcLog qw(get_dbh);

my $conf = Config::File::read_config_file("cgi.conf");
my $base_url = $conf->{BASE_URL} || "/";
 
my $q = new CGI;
print "Content-Type: text/html; charset=UTF-8\n\n";
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
my $q2 = $dbh->prepare("SELECT DISTINCT day FROM irclog WHERE channel = ? ORDER BY day DESC");

my @t_channels;

foreach my $ch (@channels){
    my @dates;
    my $short_channel = substr $ch, 1;
    $q2->execute($ch);
    while (my ($day) = $q2->fetchrow_array){
        push @dates, {
            DATE     => $day,
            URL     => $base_url . "out.pl?channel=$short_channel;date=$day",

        };
    }
    push @t_channels, {CHANNEL => $ch, DATES => \@dates};
}
$t->param(CHANNELS => \@t_channels);
print $t->output;
