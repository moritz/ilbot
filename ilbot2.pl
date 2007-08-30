#!/usr/bin/perl
use warnings;
use strict;

# this is a cleaner reimplementation of ilbot, with Bot::BasicBot which 
# in turn is based POE::* stuff
package IrcLogBot;
use IrcLog qw(get_dbh gmt_today);
{

    my $dbh = get_dbh();

    sub prepare {
        my $dbh = shift;
        return $dbh->prepare("INSERT INTO irclog (channel, day, nick, timestamp, line) VALUES(?, ?, ?, ?, ?)");
    }
    my $q = prepare($dbh);
    sub dbwrite {
        my ($channel, $who, $line) = @_;
        my @sql_args = ($channel, gmt_today(), $who, time, $line);
        if ($dbh->ping){
            $q->execute(@sql_args);
        } else {
            $q = prepare(get_dbh());
            $q->execute(@sql_args);
        }
        return;
    }

    use base 'Bot::BasicBot';

    sub said {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, $e->{who}, $e->{body});
        return undef;
    }

    sub emoted {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, '* ' . $e->{who}, $e->{body});
        return undef;

    }

    sub chanjoin {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, '',  $e->{who} . ' joined ' . $e->{channel});
        return undef;
    }

    sub chanpart {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, '',  $e->{who} . ' left ' . $e->{channel});
        return undef;
    }

    sub topic {
        my $self = shift;
        my $e = shift;
        $q->execute($e->{channel}, gmt_today(), "", time, 'Topic for ' . $e->{channel} . 'is now ' . $e->{topic});
        dbwrite($e->{channel}, "", 'Topic for ' . $e->{channel} . 'is now ' . $e->{topic});
        return undef;
    }

    sub nick_change {
        my ($self, $e) = @_;
        print Dumper($e);
        # XXX TODO
        return undef;
    }

    sub kicked {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, "", $e->{nick} . ' was kicked by ' . $e->{who} . ': ' . $e->{reason});
        return undef;
    }
}

use Config::File;
use Bot::BasicBot;
use Carp qw(confess);


package main;
my $conf = Config::File::read_config_file($ARGV[0] || "bot.conf");
my $nick = shift @ARGV || $conf->{NICK} || "ilbot6";
my $server = $conf->{SERVER} || "irc.freenode.org";
my $port = $conf->{PORT} || 6667;
my $channels = [ split m/\s+/, $conf->{CHANNEL}];

my $bot = IrcLogBot->new(
        server    => $server,
        port      => $port,
        channels  => [$channel],
        nick      => $nick,
        alt_nicks => ["irclogbot", "logbot"],
        username  => "bot",
        name      => "irc log bot, http://moritz.faui2k3.org/en/ilbot",
        charset   => "utf-8", 
        );
$bot->run();

# vim: ts=4 sw=4 expandtab
