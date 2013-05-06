#!/usr/bin/perl
use warnings;
use strict;
use IrcLog qw(get_dbh);
use Date::Simple qw/date today/;
use List::Util qw/max/;

my $no_steps = 100;

my $dbh = get_dbh();

my $sth = $dbh->prepare('SELECT MIN(day) FROM irclog');
$sth->execute;
my ($min_date) = $sth->fetchrow;
$min_date = date($min_date);
$sth->finish;
my $max_date = today();

my $interval = int( 0.5 + ($max_date - $min_date) / $no_steps);
my $total_max = 0;

$sth = $dbh->prepare('SELECT DISTINCT(channel) FROM irclog');
$sth->execute();
my $count_sth = $dbh->prepare('SELECT COUNT(*) FROM irclog WHERE channel = ?
    AND day BETWEEN ? AND ?');

while (my ($channel) = $sth->fetchrow) {
    my @counts;
    for (my $d = $min_date; $d < $max_date; $d += $interval) {
        $count_sth->execute($channel, $d, $d + $interval);
        my ($data_point) = $count_sth->fetchrow;
        push @counts, $data_point;
        $count_sth->finish;
    }

    # the last data point is probably wrong due to rounding:
    pop @counts;

    $total_max = max $total_max, @counts;
    (my $filename = $channel) =~ s/[^\w-]//g;
    $filename = "images/gen/$filename.png";
    open my $TMP, '>', 'out.tmp'
        or die "Error while opening out.tmp: $!";
    for (@counts) {
        say $TMP $_;
    }
    close $TMP or die "Error while writing to out.tmp: $!";

    system('gnuplot', '-e', qq[set output '$filename'], 'lines.plot');

}
$sth->finish;
