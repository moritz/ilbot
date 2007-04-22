package IrcLog;
use warnings;
use strict;
use DBI;
use Config::File;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
        get_dbh 
        gmt_today
        );

# get a database handle.
# you will have to modify that routine to fit your needs
sub get_dbh() {
    my $conf = Config::File::read_config_file("database.conf");
    my $dbs = $conf->{DSN} || "mysql";
    my $db_name = $conf->{DATABASE} || "irclog";
    my $host = $conf->{HOST} || "localhost";
    my $user = $conf->{USER} || "irclog";
    my $passwd = $conf->{PASSWORD} || "";

    my $db_dsn = "DBI:$dbs:database=$db_name;host=$host";
    my $dbh = DBI->connect($db_dsn, $user, $passwd, 
            {RaiseError=>1, AutoCommit => 1});
    return $dbh;
}

# returns current date in GMT in the form YYYY-MM-DD
sub gmt_today {
    my @d = gmtime(time);
    return sprintf("%04d-%02d-%02d", $d[5]+1900, $d[4] + 1, $d[3]);
}

1;
