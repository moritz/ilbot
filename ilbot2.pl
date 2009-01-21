#!/usr/bin/perl
use warnings;
use strict;
use Config::File;
use Bot::BasicBot;
use Carp qw(confess);

# this is a cleaner reimplementation of ilbot, with Bot::BasicBot which 
# in turn is based POE::* stuff
package IrcLogBot;
use IrcLog qw(get_dbh gmt_today);
use Data::Dumper;

{

    # XXX since Bot::BasicBot doesn't provide an action for the
    # quit message yet, we monkey-patch it in...
    use POE::Kernel;
    use POE::Session;
    sub run {
        my $self = shift;

        # create the callbacks to the object states
        POE::Session->create(
            object_states => [
                $self => {
                    _start => "start_state",
                    _stop  => "stop_state",

                    irc_001          => "irc_001_state",
                    irc_msg          => "irc_said_state",
                    irc_public       => "irc_said_state",
                    irc_ctcp_action  => "irc_emoted_state",
                    irc_ping         => "irc_ping_state",
                    reconnect        => "reconnect",

                    irc_disconnected => "irc_disconnected_state",
                    irc_error        => "irc_error_state",

                    irc_join         => "irc_chanjoin_state",
                    irc_part         => "irc_chanpart_state",
                    irc_kick         => "irc_kicked_state",
                    irc_nick         => "irc_nick_state",
                    irc_mode         => "irc_mode_state",
                    irc_quit         => "irc_quit_state",

                    fork_close       => "fork_close_state",
                    fork_error       => "fork_error_state",

                    irc_353          => "names_state",
                    irc_366          => "names_done_state",

                    irc_332          => "topic_raw_state",
                    irc_topic        => "topic_state",

                    irc_391          => "_time_state",
                    _get_time        => "_get_time_state",
                    
                    tick => "tick_state",
                }
            ]
        );

        # and say that we want to recive said messages
        $poe_kernel->post( $self->{IRCNAME} => register => 'all' );

        # run
        $poe_kernel->run() unless $self->{no_run};
    }

    sub irc_quit_state {
        my ($self, $kernel, $nick, $message) = @_[OBJECT, KERNEL, ARG0, ARG1];
        $nick = $_[OBJECT]->nick_strip($nick);
        if ($self->nick eq $nick) {
            $kernel->delay('reconnect', 1 );
            return;
        }
        for my $channel (keys( %{ $self->{channel_data} } )) {
            if (defined($self->{channel_data}{$channel}{$nick})) {
                $_[OBJECT]->_remove_from_channel( $channel, $nick );
                @_[ARG1, ARG2] = ($channel, $message);
                irc_chan_received_state( 'chanpart', 'say', @_ );
            }
        }
    }
    # end of monkeypatching


    my $dbh = get_dbh();

    sub prepare {
        my $dbh = shift;
        return $dbh->prepare("INSERT INTO irclog (channel, day, nick, timestamp, line) VALUES(?, ?, ?, ?, ?)");
    }
    my $q = prepare($dbh);
    sub dbwrite {
        my ($channel, $who, $line) = @_;
        # mncharity aka putter has an IRC client that prepends some lines with
        # a BOM. Remove that:
        $line =~ s/\A\x{ffef}//;
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

    sub topic {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, "", 'Topic for ' . $e->{channel} . 'is now ' . $e->{topic});
        return undef;
    }

    sub nick_change {
        my $self = shift;
        print Dumper(\@_);
        # XXX TODO
        return undef;
    }

    sub kicked {
        my $self = shift;
        my $e = shift;
        dbwrite($e->{channel}, "", $e->{nick} . ' was kicked by ' . $e->{who} . ': ' . $e->{reason});
        return undef;
    }

    sub help {
        my $self = shift;
        return "This is a passive irc logging bot. Homepage: http://moritz.faui2k3.org/en/ilbot";
    }
}


package main;
my $conf = Config::File::read_config_file(shift @ARGV || "bot.conf");
my $nick = shift @ARGV || $conf->{NICK} || "ilbot6";
my $server = $conf->{SERVER} || "irc.freenode.net";
my $port = $conf->{PORT} || 6667;
my $channels = [ split m/\s+/, $conf->{CHANNEL}];

my $bot = IrcLogBot->new(
        server    => $server,
        port      => $port,
        channels  => $channels,
        nick      => $nick,
        alt_nicks => ["irclogbot", "logbot"],
        username  => "bot",
        name      => "irc log bot, http://moritz.faui2k3.org/en/ilbot",
        charset   => "utf-8", 
        );
$bot->run();

# vim: ts=4 sw=4 expandtab
