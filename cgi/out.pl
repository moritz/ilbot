#!/usr/bin/perl
use warnings;
use strict;
use CGI::Carp qw(fatalsToBrowser);
use IrcLog qw(get_dbh gmt_today);
use IrcLog::WWW qw(http_header message_line my_encode);
use Date::Simple qw(date);
use Encode::Guess;
use CGI;
use Encode;
use HTML::Template;
use Config::File;
use File::Slurp;
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
        ['TimToady',    'nick_timtoady'],
        ['audreyt',     'nick_audreyt'],
        ['evalbot',     'bots'],
        ['lambdabot',   'bots'],
        ['pugs_svnbot', 'bots'],
        ['specbot',     'bots'],
        ['pasteling',   'bots'],
        ['moritz',      'nick_moritz'],
        ['agentzh',     'nick_agentzh'],
        ['Aankhen``',   'nick_aankhen'],
        ['dduncan',     'nick_dduncan'],
        ['fglock',      'nick_fglock'],
         );
# additional classes for nicks, sorted by frequency of speech:
my @nick_classes = qw(nick1 nick2 nick3 nick4);
# Default channel: this channel will be shown if no channel=... arg is given
my $default_channel = "perl6";

# End of config

my $q = new CGI;
my $dbh = get_dbh();
my $channel = $q->param("channel") || $default_channel;


unless ($channel =~ m/^\w+$/){
	# guard againt channel=../../../etc/passwd or so
	die "Invalid channel name";
}
my $full_channel = "#" . $channel;
my $date = $q->param("date") || gmt_today();
my $t = HTML::Template->new(
        filename => "day.tmpl",
        loop_context_vars => 1,
		global_vars => 1,
        );

$t->param(ADMIN => 1) if ($q->param("admin"));

{
	my $clf = "channels/$channel.tmpl";
	if (-e $clf) {
		$t->param(CHANNEL_LINKS =>"" .  read_file($clf));
	}
}
$t->param(BASE_URL => $base_url);
$t->param(SEARCH_URL => $base_url . "search.pl?channel=$full_channel");
my $self_url = $base_url . "out.pl?channel=$channel;date=$date";
my $db = $dbh->prepare("SELECT id, nick, timestamp, line FROM irclog "
		. "WHERE day = ? AND channel = ? AND NOT spam ORDER BY id");
$db->execute($date, $full_channel);

print http_header();

# determine which colors to use for which nick:
{
    my $count = scalar @nick_classes + scalar @colors + 1;
    my $q1 = $dbh->prepare("SELECT nick, COUNT(nick) AS c FROM irclog"
             . " WHERE day = ? AND not spam"
             . " GROUP BY nick ORDER BY c DESC LIMIT $count");
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
	my $id = $row[0];
    my $nick = decode('utf8', ($row[1]));
	my $timestamp = $row[2];
	my $message = $row[3];

	push @msg, message_line( {
            id           => $id,
            nick        => $nick, 
            timestamp   => $timestamp, 
            message     => $message, 
            line_number =>  ++$line_number,
            prev_nick   => $prev_nick,
            colors      => \@colors,
            self_url    => $self_url,
            channel     => $channel,
            },
			\$c,
			);
	$prev_nick = $nick;
}

$t->param(
        CHANNEL		=> $full_channel,
        STRIPPED_CHANNEL => $channel,
        MESSAGES    => \@msg,
        DATE        => $date,
        INDEX_URL   => $base_url,
     );

# check if previous/next date exists in database
{
    my $q1 = $dbh->prepare("SELECT COUNT(*) FROM irclog "
			. "WHERE channel = ? AND day = ? AND NOT spam");
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
    
print my_encode($t->output);


# vim: sw=4 ts=4 expandtab
