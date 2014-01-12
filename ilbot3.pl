#!/usr/bin/env perl
use lib 'lib';
# TO BE REPLACED BY THE INSTALLER
use 5.010;
use strict;
use warnings;

say "Warning! This bot is considered experimental and not ready for production!";

use AnyEvent;
use AnyEvent::IRC::Client;
use Data::Dumper;
use AnyEvent::IRC::Util qw/prefix_nick/;
use Config::File;
use Ilbot::Config;

my $backend = _backend();
my $log_joins = config(backend => 'log_joins');


$Data::Dumper::Terse = 1;
$Data::Dumper::Useqq = 1;

my $config_file = shift(@ARGV) // 'bot.conf';

sub read_config {
    my $conf = Config::File::read_config_file($config_file);
    $conf->{nick}     ||= $ARGV[0] || 'ilbot3';
    $conf->{port}     ||= 6667;
    $conf->{server}   ||= 'irc.freenode.net';
    $conf->{channels} ||= [ split ' ', $conf->{channel} ];
    return $conf;
}

my $c = AnyEvent->condvar;

my $timer;
my $con = new AnyEvent::IRC::Client;

sub gen_cb {
    my $action = shift;
    sub {
        shift;
        print $action, ' ', Dumper \@_;
    }
}

sub ilog {
    my ($channel, $who, $what) = @_;
    say join '|', map $_ // '(undef)', @_;
    return if !$log_joins && !defined($who);
    $backend->log_line(
        channel => $channel,
        nick    => $who,
        line    => $what,
    );
}

# TODO: for tracking nick_change, find out which channels she is in
$con->reg_cb (
    publicmsg => sub {
        ilog($_[1], prefix_nick($_[2]->{prefix}), $_[2]->{params}[1]);
    },
    ctcp => sub {
        if ($_[3] eq 'ACTION') {
            ilog($_[2], "* $_[1]", $_[4]);
        }
    },
    join => sub {
        ilog($_[2], undef, "$_[1] joined $_[2]");
    },
    part => sub {
        ilog($_[2], undef, "$_[1] left $_[2]");
    },
    channel_topic => sub {
        my @a = @_;
        if ($_[3]) {
            ilog($_[1], undef, "$_[3] changed the topic to $_[2]");
        }
        else {
            ilog($_[1], undef, "topic for $_[1] is now $_[2]");
        }
    },
    kick => sub {
        ilog($_[2], undef, "$_[5] has kicked $_[1]: $_[4]");
    },
);

my $conf = read_config();

$con->connect ($conf->{server}, $conf->{port}, { nick => $conf->{nick} });

my %current_channels;
for my $channel ( @{ $conf->{channels} } ) {
    say "Joining $channel";
    $con->send_srv(
        JOIN    => $channel,
    );
    $current_channels{$channel} = 1;
}

my $signal_handler = AnyEvent->signal(
    signal  => 'HUP',
    cb      => sub {
        $conf = read_config();
        say "In SIGHUP handler";
        for my $channel ( @{ $conf->{channels} } ) {
            unless ( $current_channels{$channel} ) {
                say "Joining $channel";
                $con->send_srv(
                    JOIN    => $channel,
                );
                $current_channels{$channel} = 1;
            }
        }
        # TODO: leave channels that have been removed
    },
);

$c->wait;
$con->disconnect;
