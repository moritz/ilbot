#!/usr/bin/perl
use warnings;
use strict;
use lib "/home/moritz/sg/online/";
use IrcLog qw(get_dbh gmt_today);
use Date::Simple qw(date);
use CGI::Carp qw(fatalsToBrowser);
use Encode::Guess;
use CGI;
use Encode;
use HTML::Entities;
use HTML::Template;
use POSIX qw(ceil);
use Regexp::Common qw(URI);
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
        );

$t->param(BASE_URL => $base_url);
my $db = $dbh->prepare("SELECT nick, timestamp, line FROM irclog WHERE day = ? AND channel = ?");
$db->execute($date, $full_channel);

# charset has to be utf-8, since we encode everything in utf-8
print "Content-Type: text/html; charset=UTF-8\n\n";

# determine which colors to use for which nick:
{
    my $count = scalar @nick_classes + scalar @colors + 1;
    my $q = $dbh->prepare("SELECT nick, COUNT(nick) AS c FROM irclog" .
            " WHERE day = ? " .
            " GROUP BY nick ORDER BY c DESC LIMIT $count");
    $q->execute($date);
    while (my @row = $q->fetchrow_array and @nick_classes){
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
while (my @row = $db->fetchrow_array){
    my $nick = my_encode($row[0]);
    my %h = (
        TIME     => format_time($row[1]),
        MESSAGE => my_encode($row[2]),
    );
    if ($nick ne $prev_nick){
        # $c++ is used to alternate the background color
        $c++;
        $h{NICK} = $nick;
    } else {
        # omit nick in successive lines from the same nick
        $h{NICK} = "";
    }

    my @classes;

    if ($row[0] eq ""){
        # empty nick column means that nobody said anything, but 
        # it's a join, leave, topic etc.
        push @classes, "special";
        $h{SPECIAL} = 1;
    }
    if ($c % 2){
        push @classes, "dark";
    }
    if (@classes){
        $h{CLASS} = join " ", @classes;
    }
    # determine nick color:
    # perhaps do something more fancy, like count the number of lines per
    # nick, and give special colors to the $n most active nicks
NICK:    foreach (@colors){
        my $n = quotemeta $_->[0];
        if ($nick =~ m/^$n/ or $nick =~ m/^\* $n/){
            $h{NICK_CLASS} = $_->[1];
            last NICK;
        }
    }
#    print STDERR "No color found for $nick\n" unless ($h{NICK_CLASS});    
    push @msg, \%h;
    $prev_nick = $nick;
}

$t->param(
        CHANNEL     => $full_channel,
        MESSAGES     => \@msg,
        DATE         => $date,
        INDEX_URL     => $base_url,
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
    
print $t->output;


# my_encode takes a string, encodes it in utf-8, and calls all output
# processing
sub my_encode {
    my $str = shift;
    $str =~ s/[\x02\x16]//g;
    my $enc = guess_encoding($str, qw(utf-8 latin1));
    if (ref($enc)){
        $str =  $enc->decode($str);
    } else {
        $str = decode("utf-8", $str);
    }
    # break long words to avoid weird html layout
    $str =~ s/(\w{60,})/ break_apart($1, 60) /eg;
    return linkify($str);
}

# turns a timestap into a (GMT) time string
sub format_time {
    my $d = shift;
    my @times = gmtime($d);
    return sprintf("%02d:%02d", $times[2], $times[1]);
}

# expects a string consisting of a single long word, and returns the same
# string with spaces after each 50 bytes at least
sub break_apart {
    my $str = shift;
    my $max_chunk_size = shift || 50;
    my $l = length $str;
    my $chunk_size = ceil( $l / ceil($l/$max_chunk_size));

    my $result = substr $str, 0, $chunk_size;
    for (my $i = $chunk_size; $i < $l; $i += $chunk_size){
        $result .= " " . substr $str, $i, $chunk_size;
    }
    return $result;
}

# takes a valid UTF-8 string, turns URLs into links, and encodes unsafe
# characters
# nb there is no need to encode characters with high bits (encode_entities
# does that by default, but we're using utf-8 as output, so who cares...)
sub linkify {
    my $str = shift;
    my $result = "";
    while ($str =~ m/$RE{URI}{HTTP}/){
        $result .= revision_linkify($`);
        $result .= qq{<a href="$&">} . encode_entities($&, '<>&"') . '</a>';
        $str = $';
    }
    return $result . revision_linkify($str);
}

#turns r\d+ into a link to the appropriate changeset.
# this is #perl6-specific and therefore not very nice
sub revision_linkify {
    my $str = shift;
    my $result = "";
    while ($str =~ m/\br(\d+)\b/){
        $result .= encode_entities($`, '<>&"');
        $result .= qq{<a href="http://dev.pugscode.org/changeset/$1">} . encode_entities($&) . '</a>';
        $str = $';
    }
    return $result . encode_entities($str, '<>&"');

}
