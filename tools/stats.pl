#!/usr/bin/env perl
use strict;
use warnings;
use Date::Simple qw/date today/;
use 5.010;

my $channel  = shift // '#perl6';
$channel =~ s/^(?!#)/#/;

use FindBin;
use lib "$FindBin::Bin/../lib";
use IrcLog qw/get_dbh/;
my $dbh = get_dbh;
my $from_month;
my $prev_count = 0;
{
    my $sth = $dbh->prepare('SELECT MIN(day) FROM irclog');
    $sth->execute;
    my ($month) = $sth->fetchrow_array;
    $sth->finish;
    ($from_month) = $month =~ /(\d{4}-\d{2})/;
    $from_month = date("$from_month-01");
}
my $to_month =  next_month($from_month);
my $sth = $dbh->prepare('SELECT COUNT(*) FROM irclog WHERE day >= ? AND day < ? AND channel = ?');
while ($from_month < today()) {
    $sth->execute($from_month, $to_month, $channel);
    my ($count) = $sth->fetchrow_array;
    say $from_month->format('%Y-%m'), '    ', $count;
} continue {
    ($from_month, $to_month) = ($to_month, next_month($to_month));
}


sub next_month {
    my $d = shift;
    my $next = $d + 31;
    date($next->year, $next->month, 1);
}
