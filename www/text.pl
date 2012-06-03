#!/usr/bin/env perl
use warnings;
use strict;
use Carp qw(confess);
use CGI::Carp qw(fatalsToBrowser);
use CGI;
use Encode;
use HTML::Entities;
# evil hack: Text::Table lies somewhere near /irclog/ on the server...
use lib '../lib';
use lib 'lib';
use IrcLog qw(get_dbh gmt_today);
use IrcLog::WWW qw(my_encode my_decode);
use Text::Table;

use Plack::Request;
use Plack::Response;

my $default_channel = 'perl6';

# End of config

return sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $dbh = get_dbh();
    my $channel = $req->param('channel') || $default_channel;

    my $reverse = $req->param('reverse') || 0;

    my $date = $req->param('date') || gmt_today;

    if ($channel !~ m/^\w+(?:-\w+)*\z/sx){
        # guard against channel=../../../etc/passwd or so
        confess 'Invalid channel name';
    }

#Check for reverse
    my $statement = 'SELECT nick, timestamp, line FROM irclog '
            . 'WHERE day = ? AND channel = ? AND NOT spam ORDER BY id';

    $statement .= ' DESC' if $reverse;

    my $db = $dbh->prepare($statement);
    $db->execute($date, '#' . $channel);

    my $response = Plack::Response->new(200);
    $response->headers(['Content-Type' => 'text/html;charset=utf-8']);
    my $body = <<HTML_HEADER;
<html>
<head>
<title>IRC Logs</title>
</head>
<body>
<pre>
HTML_HEADER

    my $table = Text::Table->new(qw(Time Nick Message));

    while (my $row = $db->fetchrow_hashref){
        next unless length($row->{nick});
        my ($hour, $minute) =(gmtime $row->{timestamp})[2,1];  
        $table->add(
                sprintf("%02d:%02d", $hour, $minute),
                $row->{nick},
                my_decode($row->{line}),
                );
    }
    my $text = encode_entities($table, '<>&');

# Text::Table will add trailing whitespace to pad messages to the
# longest message. I (avar) wasn't able to find out how to make it
# stop doing that so I'm hacking around it with regex! 
    $text =~ s/ +$//gm;

    $body .= encode("utf-8", $text);
    $body .= "</pre></body></html>\n";

    $response->body($body);
    return $response->finalize;
};

# vim: sw=4 ts=4 expandtab
