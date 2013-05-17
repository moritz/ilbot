package Ilbot::Date;
use strict;
use warnings;
use 5.010;
use Ilbot::Config qw/config/;

use Exporter qw/import/;

our @EXPORT_OK = qw/today/;

# returns current date in gmt or local timezone in the form YYYY-MM-DD
sub today {
	my $timezone = config(backend => 'timezone') || 'gmt';

    my @d;

    if($timezone eq 'gmt') { @d = gmtime(time); }
    elsif($timezone eq 'local') { @d = localtime(time); }

    return sprintf("%04d-%02d-%02d", $d[5]+1900, $d[4] + 1, $d[3]);
}


1;
