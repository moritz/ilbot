#!/usr/bin/perl
use warnings;
use strict;

# this is a cleaner reimplementation of ilbot, with Bot::BasicBot which 
# in turn is based POE::* stuff

use Config::File;
use Bot::BasicBot;

package IrcLogBot;
use IrcLog qw(get_dbh gmt_today);
{

    my $dbh = get_dbh();

    my $q = $dbh->prepare("INSERT INTO irclog VALUES(?, ?, ?, ?, ?)");

    use base 'Bot::BasicBot';

    sub said {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), $e->{who}, time, $e->{body});
        return undef;
    }

    sub emoted {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "* " . $e->{who}, time, $e->{body});
        return undef;

    }

    sub chanjoin {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, $e->{who} . " joined " . $e->{channel});
        return undef;
    }

    sub chanpart {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, $e->{who} . " left " . $e->{channel});
        return undef;
    }

    sub topic {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, 'Topic for ' . $e->{channel} . 'is now ' . $e->{topic});
        return undef;
    }

    sub nick_change {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, $e->{from} . ' is now known as ' . $e->{to});
        return undef;
    }

    sub kicked {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, $e->{nick} . ' was kicked by ' . $e->{who} . ': ' . $e->{reason});
        return undef;

    }

}

package main;
my $conf = Config::File::read_config_file("bot.conf");
my $nick = shift @ARGV || $conf->{NICK} || "ilbot6";
my $server = $conf->{SERVER} || "irc.freenode.org";
my $port = $conf->{PORT} || 6667;
my $channel = $conf->{CHANNEL} || "#perl6";

my $bot = IrcLogBot->new(
        server => $server,
        port   => $port,
        channels => [$channel],
        nick      => $nick,
        alt_nicks => ["irclogbot", "logbot"],
        username  => "bot",
        name      => "irc log bot",
        charset => "utf-8", 
        );
$bot->run();

