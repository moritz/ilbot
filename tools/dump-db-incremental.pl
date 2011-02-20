#!/usr/bin/env perl
use strict;
use warnings;

my $last_id = shift @ARGV
    or die "Usage: $0 <id>\n";

use FindBin;
use lib "$FindBin::Bin/../lib";
use IrcLog qw/get_dbh/;

my $sth = get_dbh()->prepare('SELECT * FROM irclog WHERE id > ?');
$sth->execute($last_id);

sub mysql_ecape {
    for (@_) {
        $_ =~ s/([\\'])/\\$1/g;
        $_ = "'$_'";
    }
}


while (my $row = $sth->fetchrow_hashref) {
    mysql_ecape @$row{'nick', 'line'};
    print "INSERT INTO irclog(", join(', ', keys %$row),
           ") VALUES (",         join(', ', values %$row),
           ");\n";
}
