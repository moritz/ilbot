#!/usr/bin/perl
use warnings;
use strict;
use lib 'lib';
use Ilbot::Date qw/today/;
use Ilbot::Config;
use Date::Simple qw/date/;
use Getopt::Long;
use 5.010;

my $dir = config(www => 'static_path') . '/s/images/index/';
my $no_steps = 100;
use File::Temp qw/tempfile/;

GetOptions(
    'output-dir=s'  => \$dir,
    'steps=i'       => \$no_steps,
) or die "Usage: $0 [--out-dir=where/to/put/the/files/] [--steps=100]\n";

die "No directory '$dir'\n" unless -d $dir;

my $backend = backend();

my $min_date = date($backend->first_day());
my $max_date = date(today());

my $interval = int( 0.5 + ($max_date - $min_date) / $no_steps);

my $template = do {
    open my $IN, '<', 'lines.plot'
        or die "Cannot read file 'lines.plot': $!";
    local $/;
    <$IN>;
};

for my $channel ($backend->channels) {
    my $b = $backend->channel(channel => $channel);
    my @counts;
    say $channel;
    for (my $d = $min_date; $d < $max_date; $d += $interval) {
        push @counts, $b->activity_count(from => $d, to => $d + $interval);
    }

    # the last data point is probably wrong due to rounding:
    pop @counts;

    (my $filename = $channel) =~ s/[^\w-]//g;
    $filename = "$dir/$filename.png";
    my ($TMP, $tmp_file) = tempfile();

    for (@counts) {
        say $TMP $_;
    }
    close $TMP or die "Error while writing to $tmp_file: $!";
    my ($GNU, $gnu_file) = tempfile();
    say $GNU $template;
    say $GNU qq[set output '$filename';];
    say $GNU qq[plot '$tmp_file' with lines lt rgb "gray"];
    close $GNU or die "Error while writing to $gnu_file: $!";

    system('gnuplot', $gnu_file);
}
