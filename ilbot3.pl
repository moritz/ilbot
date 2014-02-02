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
use Time::HiRes qw/sleep/;
use Getopt::Long;
use Encode qw/decode_utf8 encode_utf8/;

GetOptions('debug+' => \(my $Debug = 0));
say "Debug level: $Debug";

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

my $con = new AnyEvent::IRC::Client;

sub gen_cb {
    my $action = shift;
    sub {
        shift;
        print $action, ' ', Dumper \@_;
    }
}

sub my_decode {
    decode_utf8 $_[0], sub { encode_utf8 chr $_[0] };
}

sub ilog {
    my ($channel, $who, $what) = @_;
    say join '|', map $_ // '(undef)', @_ if $Debug >= 2;
    return if $what =~ /^\s*\[off\]/i;
    return if !$log_joins && !defined($who);
    $channel =~ s{^##}{#};
    $channel = lc $channel;
    $what = my_decode($what);
    $backend->log_line(
        channel => $channel,
        nick    => $who,
        line    => $what,
    );
}

my $conf = read_config();

$con->enable_ssl() if $conf->{use_ssl};
my %info = (
    nick => $conf->{nick},
);
for my $attr (qw/user password/) {
    $info{$attr} = $conf->{$attr} if defined $conf->{attr};
}

sub my_connect {
    $con->connect ($conf->{server}, $conf->{port}, \%info);
};

my %current_channels;
my @channels_to_join = @{ $conf->{channels} };

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
    error => sub {
        my ($self, $code, $message) = @_;
        if ($message =~ /closing link/i) {
            my_connect();
            %current_channels = ();
            @channels_to_join = @{ $conf->{channels} };
        }
    },
    debug_recv => sub {
        if ($Debug >= 3) {
            print "DEBUG ", Dumper $_[1];
        }
    },
);

my_connect();


my $timer = AnyEvent->timer(
    interval    => 2,
    cb          => sub {
        if (my $channel = shift @channels_to_join) {
            return if $current_channels{$channel};
            say "Joining $channel";
            $con->send_srv(
                JOIN    => $channel,
            );
            $current_channels{$channel} = 1;
        }
    },
);

my $signal_handler = AnyEvent->signal(
    signal  => 'HUP',
    cb      => sub {
        $conf = read_config();
        say "In SIGHUP handler";
        for my $channel ( @{ $conf->{channels} } ) {
            unless ( $current_channels{$channel} ) {
                push @channels_to_join, $channel;
            }
        }
        # TODO: leave channels that have been removed
    },
);

$c->wait;
$con->disconnect;
