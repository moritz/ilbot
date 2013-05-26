#!/usr/bin/env perl
use lib 'lib';
# TO BE REPLACED BY THE INSTALLER
use warnings;
use strict;
use Bot::BasicBot 0.81;

use Ilbot::Config;
my $backend = _backend();

# this is a cleaner reimplementation of ilbot, with Bot::BasicBot which 
# in turn is based POE::* stuff
package Ilbot::Logger;
use Ilbot::Date qw/today/;


{

    sub dbwrite {
        my ($channel, $who, $line) = @_;
        return unless $channel =~ /\A#\S+\z/;
        $channel =~ s/\A##/#/;
        # remove leading BOMs. Some clients seem to send them.
        $line =~ s/\A\x{ffef}//;
        $backend->log_line(
            channel => $channel,
            nick    => $who,
            line    => $line,
        );
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

    sub chanquit {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, '', $e->{who} . ' left ' . $e->{channel});
        return undef;
    }

    sub chanpart {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, '',  $e->{who} . ' left ' . $e->{channel});
        return undef;
    }

    sub _channels_for_nick {
        my $self = shift;
        my $nick = shift;

        return grep { $self->{channel_data}{$_}{$nick} } keys( %{ $self->{channel_data} } );
    }

    sub userquit {
        my $self = shift;
        my $e = shift;
        my $nick = $e->{who};

        foreach my $channel ($self->_channels_for_nick($nick)) {
            $self->chanpart({ who => $nick, channel => $channel });
        }
    }

    sub topic {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, "", 'Topic for ' . $e->{channel} . ' is now ' . $e->{topic});
        return undef;
    }

    sub nick_change {
        my $self = shift;
        my($old, $new) = @_;

        foreach my $channel ($self->_channels_for_nick($new)) {
            dbwrite($channel, "", $old . ' is now known as ' . $new);
        }
        
        return undef;
    }

    sub kicked {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, "", $e->{kicked} . ' was kicked by ' . $e->{who} . ': ' . $e->{reason});
        return undef;
    }

    sub help {
        my $self = shift;
        return "This is a passive irc logging bot. Homepage: http://moritz.faui2k3.org/en/ilbot";
    }
}


package main;
# do not use the normal config() mechanism, because there can be multiple
# bot configuration files for multiple servers
my $conf     = Config::File::read_config_file(shift @ARGV || "bot.conf");
my $nick     = shift @ARGV || $conf->{nick} || "ilbot6";
my $server   = $conf->{server}  // "irc.freenode.net";
my $port     = $conf->{port}    // 6667;
my $channels = [ split m/\s+/, $conf->{channel}];

my $bot = Ilbot::Logger->new(
        server    => $server,
        port      => $port,
        channels  => $channels,
        nick      => $nick,
        alt_nicks => ["irclogbot", "logbot"],
        username  => "bot",
        name      => "irc log bot, http://moritz.faui2k3.org/en/ilbot",
        charset   => "utf-8",
        );
say "Launching logger...";
$bot->run();

# vim: ts=4 sw=4 expandtab
