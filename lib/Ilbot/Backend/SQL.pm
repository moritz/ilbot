package Ilbot::Backend::SQL;

use strict;
use warnings;
use 5.010;

our %SQL = (
    STANDARD    => {
        channels            => 'SELECT DISTINCT(channel) FROM irclog ORDER BY channel',
        day_has_actitivity  => 'SELECT 1 FROM irclog WHERE channel = ? AND day = ? AND not spam LIMIT 1',
        days_and_activity_counts => q[SELECT day, count(*) FROM irclog WHERE channel = ? AND nick <> '' GROUP BY day ORDER BY day],
        activity_average    => q[SELECT COUNT(*), MAX(day) - MIN(day) FROM irclog WHERE channel = ? AND nick <> ''],
    },
    mysql       => {
        activity_average    => q[SELECT COUNT(*), DATEDIFF(DATE(MAX(day)), DATE(MIN(day))) FROM irclog WHERE channel = ? AND nick <> ''],
    },
);

sub new {
    my ($class, %opt) = @_;

    die "Missing option 'config'" unless $opt{config};
    my $self = bless {}, $class;
    
    {
        my $conf    = $opt{config};
        my $dbs     = $conf->{DSN} || "mysql";
        $self->{db} = $dbs;
        my $db_name = $conf->{DATABASE} || "irclog";
        my $host    = $conf->{HOST} || "localhost";
        my $user    = $conf->{USER} || "irclog";
        my $passwd  = $conf->{PASSWORD} || "";

        my $db_dsn  = "DBI:$dbs:database=$db_name;host=$host";
        $self->{dbh} = DBI->connect($db_dsn, $user, $passwd,
                {RaiseError=>1, AutoCommit => 1});
    }
    return $self;
}

sub dbh { $_[0]{dbh} };

sub sql_for {
    my ($self, %opt) = @_;
    die 'Missing option "query"' unless $opt{query};
    for (lc($self->{db}), 'STANDARD') {
        my $sql = $SQL{$_}{$opt{query}};
        return $sql if defined $sql;
    }
    die "Found no SQL for '$opt{query}'";
}

sub channels {
    my $self = shift;
    $self->dbh->selectcol_arrayref($self->sql_for(query => 'channels'));
}

package Ilbot::Backend::SQL::Channel;

# it's a hack, but works for now
our @ISA = qw/Ilbot::Backend::SQL/;

sub new {
    my ($class, %opt) = @_;
    my $self = bless {}, $class;
    for my $attr (qw(dbh channel db)) {
        die "Missing option '$attr'" unless defined $opt{$attr};
        $self->{$attr} = $opt{$attr};
    }

    return $self;
}

sub dbh     { $_[0]{dbh}     };
sub channel { $_[0]{channel} };

sub day_has_actitivity {
    my ($self, %opt) = @_;
    die "Missing option 'day'" unless $opt{day};
    my $sth = $self->prepare($self->sql_for(query => 'day_has_actitivity'));
    $sth->execute($self->chanenl, $opt{day});
    my ($res) = $sth->fetchrow;
    $sth->finish;
}

sub activity_average {
    my $self = shift;
    my $sth = $self->dbh->prepare($self->sql_for(query => 'activity_average'));
    $sth->execute($self->channel);
    my ($count, $days) = $sth->fetchrow;
    $sth->finish;
    return $count / ($day || 1);
}

sub days_and_activity_counts {
    my $self = shift;
    return $self->dbh->selectall_arrayref(
        $self->sql_for(query => 'days_and_activity_counts'),
        undef,
        $self->channel,
    );
}

1;
