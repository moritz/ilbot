#!/usr/bin/perl
use warnings;
use strict;

use Net::IRC;
use Data::Dumper;
use Encode qw(encode);
use IrcLog qw(get_dbh gmt_today);
use IrcLog::WWW qw(my_decode);
use Config::File;

my $irc = new Net::IRC;

my $config_filename = shift @ARGV || "bot.conf";
my $conf = Config::File::read_config_file($config_filename);
my $nick = shift @ARGV || $conf->{NICK} || "ilbot6";

my $conn = $irc->newconn(
        Nick    => $nick,
        Server  => $conf->{SERVER} || 'irc.freenode.net',
        );
my $dbh = get_dbh();

my $channel = $conf->{CHANNEL} || "#perl6";
my $q = $dbh->prepare("INSERT INTO irclog (channel, day, nick, timestamp, line) VALUES(?, ?, ?, ?, ?)");
$conn->add_global_handler('376', \&on_connect);
$conn->add_handler("public", \&on_public);
$conn->add_handler("notice", \&on_public);
for (qw(caction msg chat join umode part topic notopic leaving error nick)){
    $conn->add_handler($_, \&on_other);
}

sub dbwrite {
	my @args = @_;
	$args[-1] = encode('utf8', my_decode($args[-1]));
#	my $line = $args[-1];
#	$line = encode('utf8', my_decode($line));
#	print "$args[2]: $line\n";
#	$args[-1] = $line;
	if ($dbh->ping){
		$q->execute(@args);
	} else {
		$dbh = get_dbh();
		$q = $dbh->prepare("INSERT INTO irclog (channel, day, nick, timestamp, line) VALUES(?, ?, ?, ?, ?)");
		$q->execute(@args);
	}
}

$irc->start;

sub on_public {
    my $self = shift;
    my $event = shift;
    return if (is_ignored($event->args));    
#    print $event->nick, ": ", $event->args, "\n";
    dbwrite($channel, gmt_today(), $event->nick, time, $event->args);
    
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
#        print Dumper([$event]);
        my @a = @{ $event->{args} };
#        print Dumper(\@a);
        dbwrite($channel, gmt_today(), "", time, "topic for $channel is: " . $a[$#a]);
    } elsif ($e_type eq "join"){
        dbwrite($channel, gmt_today(), "", time, "$e_nick joined $channel");
    } elsif ($e_type eq "part" || $e_type eq "leaving"){
        dbwrite($channel, gmt_today(), "", time, "$e_nick left $channel");
    } elsif ($e_type eq "nick") {
        dbwrite($channel, gmt_today(), "", time, "$e_nick changed the nick to $str");
    } elsif ($e_type eq "caction"){
        dbwrite($channel, gmt_today(), "* $e_nick", time , $str);
    } else {
        print "nick: '$e_nick', type: '$e_type', rest:' $str';\n";
    }

#    print STDERR $event->nick, ":", $str,  $/;
#    print STDERR Dumper([$event]), $/;

#    $q->execute($channel, gmt_today(), "", time, $str);

}

