#!/usr/bin/perl
use warnings;
use strict;
use CGI::Carp qw(fatalsToBrowser);
use IrcLog qw(get_dbh gmt_today my_encode message_line);
use Date::Simple qw(date);
use Encode::Guess;
use CGI;
use Encode;
use HTML::Template;
use Config::File;
#use Data::Dumper;


# Configuration
# $base_url is the absoulte URL to the directoy where index.pl and out.pl live
# If they live in the root of their own virtual host, set it to "/".
my $conf = Config::File::read_config_file("cgi.conf");
my $base_url = $conf->{BASE_URL} || "/";

# I'm to lazy right to move this to  a config file, because Config::File seems
# unable to handle arrays, just hashes.
 
# map nicks to CSS classes.
my @colors = (
        ['TimToady',	'nick1'],
        ['audreyt',     'nick2'],
        ['evalbot',     'bots'],
        ['lambdabot',   'bots'],
        ['svnbot6',     'bots'],
        ['specbot',     'bots'],
        ['pasteling',   'bots'],
         );
# additional classes for nicks, sorted by frequency of speech:
my @nick_classes = qw(nick3 nick4 nick5 nick6 nick7 nick8);
# Default channel: this channel will be shown if no channel=... arg is given
my $default_channel = "perl6";

# End of config

my $q = new CGI;
my $dbh = get_dbh();
my $channel = $q->param("channel") || $default_channel;
my $full_channel = "#" . $channel;
my $date = $q->param("date") || gmt_today();
my $t = HTML::Template->new(
        filename => "day.tmpl",
        loop_context_vars => 1,
		global_vars => 1,
        );

$t->param(BASE_URL => $base_url);
$t->param(SEARCH_URL => $base_url . "search.pl?channel=$full_channel");
my $self_url = $base_url . "out.pl?channel=$channel;date=$date";
my $db = $dbh->prepare("SELECT nick, timestamp, line FROM irclog WHERE day = ? AND channel = ? ORDER BY id");
$db->execute($date, $full_channel);

# charset has to be utf-8, since we encode everything in utf-8
print "Content-Type: text/html; charset=UTF-8\n\n";

# determine which colors to use for which nick:
{
    my $count = scalar @nick_classes + scalar @colors + 1;
    my $q1 = $dbh->prepare("SELECT nick, COUNT(nick) AS c FROM irclog" .
            " WHERE day = ? " .
            " GROUP BY nick ORDER BY c DESC LIMIT $count");
    $q1->execute($date);
    while (my @row = $q1->fetchrow_array and @nick_classes){
        next if ($row[0] eq "");
        my $n = quotemeta $row[0];
        unless (grep { $_->[0] =~ m/^$n/ } @colors){
            push @colors, [$row[0], shift @nick_classes];
        }
    }
#    $t->param(DEBUG => Dumper(\@colors));
    
}

my @msg;

my $line = 1;
my $prev_nick ="";
my $c = 0;

# populate the template
my $line_number = 0;
while (my @row = $db->fetchrow_array){
    my $nick = my_encode($row[0]);
	my $timestamp = $row[1];
	my $message = $row[2];

	push @msg, message_line($nick, 
			$timestamp, 
			$message, 
			++$line_number,
			\$c,
			$prev_nick,
			\@colors,
			$self_url,
			);
	$prev_nick = $nick;
}

$t->param(
        CHANNEL		=> $full_channel,
        MESSAGES    => \@msg,
        DATE        => $date,
        INDEX_URL    => $base_url,
     );

# check if previous/next date exists in database
{
    my $q1 = $dbh->prepare("SELECT COUNT(*) FROM irclog WHERE channel = ? AND day = ?");
    # Date::Simple magic ;)
    my $tomorrow = date($date) + 1;
    $q1->execute($full_channel, $tomorrow);
    my ($res) = $q1->fetchrow_array();
    if ($res){
        $t->param(NEXT_URL => $base_url . "out.pl?channel=$channel;date=$tomorrow");
    }

    my $yesterday = date($date) - 1;
    $q1->execute($full_channel, $yesterday);
    ($res) = $q1->fetchrow_array();
    if ($res){
        $t->param(PREV_URL => $base_url . "out.pl?channel=$channel;date=$yesterday");
    }

}
    
print encode("utf-8", $t->output);


