#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use IrcLog qw/get_dbh/;
my $sth = get_dbh()->prepare('SELECT MAX(id) FROM irclog');
$sth->execute;
my ($id) = $sth->fetchrow_array;
print $id, $/;
