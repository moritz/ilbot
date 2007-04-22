#!/usr/bin/perl
use warnings;
use strict;

use Net::IRC;
use Data::Dumper;
use IrcLog qw(get_dbh gmt_today);

my $irc = new Net::IRC;

my $nick = shift @ARGV || "ilbot6";

my $conn = $irc->newconn(
        Nick    => $nick,
        Server  => 'irc.freenode.net'
        );
my $dbh = get_dbh();

my $channel = "#perl6";
my $q = $dbh->prepare("INSERT INTO irclog VALUES(?, ?, ?, ?, ?)");
$conn->add_global_handler('376', \&on_connect);
$conn->add_handler("public", \&on_public);
$conn->add_handler("notice", \&on_public);
for (qw(caction msg chat join umode part topic notopic leaving error nick)){
    $conn->add_handler($_, \&on_other);
}


$irc->start;

sub on_public {
    my $self = shift;
    my $event = shift;
    return if (is_ignored($event->args));    
#    print $event->nick, ": ", $event->args, "\n";
    $q->execute($channel, gmt_today(), $event->nick, time, $event->args);
    
}


sub on_connect {
    my $self = shift;
    $self->join($channel);
}

sub is_ignored {
    my $str = shift;
    return 1 unless ($str);
    return 1 if ($str =~ m/^\[off\]/i);
    return undef;
}

sub on_other {
    my $self = shift;
    my $event = shift;
    # Empty strings stands for something "special" (join, leave, topic
    # etc.)
    return if ($event->nick and $event->nick eq $nick);
    my $str = join ":|:", $event->args;
    my ($e_nick, $e_type) = ($event->nick, $event->type);
    if ($e_type eq "topic"){
        $q->execute($channel, gmt_today(), "", time, "topic for $channel is: " . ($event->args)[2]);
    } elsif ($e_type eq "join"){
        $q->execute($channel, gmt_today(), "", time, "$e_nick joined $channel");
    } elsif ($e_type eq "part" || $e_type eq "leaving"){
        $q->execute($channel, gmt_today(), "", time, "$e_nick left $channel");
    } elsif ($e_type eq "nick") {
        $q->execute($channel, gmt_today(), "", time, "$str changed the nick to $e_nick");
    } elsif ($e_type eq "caction"){
        $q->execute($channel, gmt_today(), "* $e_nick", time , $str);
    } else {
        print "nick: '$e_nick', type: '$e_type', rest:' $str';\n";
    }

#    print STDERR $event->nick, ":", $str,  $/;
#    print STDERR Dumper([$event]), $/;

#    $q->execute($channel, gmt_today(), "", time, $str);

}

