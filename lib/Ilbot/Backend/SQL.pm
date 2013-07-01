package Ilbot::Backend::SQL;

use strict;
use warnings;
use 5.010;
use DBI;
use Ilbot::Date qw/today/;

our %SQL = (
    STANDARD    => {
        channels                 => 'SELECT channel FROM ilbot_channel ORDER BY channel',
        channel_id               => 'SELECT id FROM ilbot_channel WHERE channel = ?',
        day_id                   => 'SELECT ilbot_day.id FROM ilbot_day JOIN ilbot_channel ON ilbot_channel.id = ilbot_day.channel WHERE ilbot_channel.channel = ? AND ilbot_day.day = ?',
        first_day                => 'SELECT MIN(day) FROM ilbot_day',
        first_day_channel        => 'SELECT MIN(day) FROM ilbot_day WHERE channel = ?',
        activity_count           => q[SELECT SUM(cache_number_lines) FROM ilbot_day WHERE channel = ?  AND day BETWEEN ? AND ? AND nick <> ''],
        days_and_activity_counts => q[SELECT day, cache_number_lines FROM ilbot_day WHERE channel = ?  ORDER BY day],
        activity_average         => q[SELECT COUNT(*), MAX(day) - MIN(day) FROM ilbot_lines WHERE channel = ? AND nick IS NOT NULL],
        lines_after_id           => q[SELECT id, nick, timestamp, line FROM ilbot_lines WHERE day = ? AND id > ? AND NOT spam ORDER BY id],
        lines_nosummary_nospam   => q[SELECT id, nick, timestamp, line FROM ilbot_lines WHERE day = ? AND NOT spam ORDER BY id],
        lines_summary_nospam     => q[SELECT id, nick, timestamp, line FROM ilbot_lines WHERE day = ? AND NOT spam AND in_summary ORDER BY id],
        lines_nosummary_spam     => q[SELECT id, nick, timestamp, line FROM ilbot_lines WHERE day = ? ORDER BY id],
        lines_summary_spam       => q[SELECT id, nick, timestamp, line FROM ilbot_lines WHERE day = ? AND in_summary ORDER BY id],
        summary_ids              => q[SELECT id FROM ilbot_lines WHERE day = ? AND in_summary = 1 ORDER BY id],
    },
    mysql       => {
        activity_average         => q[SELECT SUM(cache_number_lines), DATEDIFF(DATE(MAX(day)), DATE(MIN(day))) FROM ilbot_day WHERE channel = ?],
        log_line                 => q[CALL ilbot_log_line (?, ?, ?)],
    },
);

my %post_connect = (
    mysql   => sub {
        $_[0]{mysql_enable_utf8} = 1;
        $_[0]{mysql_auto_reconnect} = 1;
    },
    Pg      => sub { $_[0]{pg_enable_utf8}    = 1 },
);

sub new {
    my ($class, %opt) = @_;

    die "Missing option 'config'" unless $opt{config};
    my $self = bless {}, $class;

    {
        my $conf    = $opt{config};
        my $dbs     = $conf->{dsn}      || "mysql";
        $self->{db} = $dbs;
        my $db_name = $conf->{database} || "irclog";
        my $host    = $conf->{host}     || "localhost";
        my $user    = $conf->{user}     || "irclog";
        my $passwd  = $conf->{password} || "";

        my $db_dsn  = "DBI:$dbs:database=$db_name;host=$host";
        $self->{dbh} = DBI->connect($db_dsn, $user, $passwd,
                {RaiseError=>1, AutoCommit => 1});
        if (my $post = $post_connect{$self->{db}}) {
            $post->($self->{dbh});
        }
    }
    return $self;
}

sub dbh { $_[0]{dbh} };

sub _single_value {
    my ($self, $sql, @bind) = @_;
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@bind);
    my ($v) = $sth->fetchrow_array();
    $sth->finish;
    return $v;
}

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

sub first_day {
    my $self = shift;
    return $self->_single_value($self->sql_for(query => 'first_day'));
}

sub channels_and_days_for_ids {
    my ($self, %opts) = @_;
    die "Missing argument 'ids'" unless $opts{ids};
    my @ids = @{ $opts{ids} };
    return [] unless @ids;
    # SQL depends on the number of elements, so
    # can't simply be obtained with sql_for
    my $sql = q[
        SELECT ilbot_channel.channel, ilbot_day.day
        FROM   ilbot_channel
        JOIN   ilbot_day ON ilbot_day.channel = ilbot_channel.id
        JOIN   ilbot_lines ON ilbot_lines.day = ilbot_day.id
        WHERE ilbot_lines.id IN (
        ]
                . join(', ', ('?') x @ids)
        . ') GROUP BY ilbot_channel.channel, ilbot_day.day';
    return $self->dbh->selectall_arrayref($sql, undef, @ids);
}

sub update_summary {
    my ($self, %opt) = @_;

    # SQL depends on the number of elements, so
    # can't simply be obtained with sql_for
    my @check = @{ $opt{check} // [] };
    if (@check) {
        my $sql = 'UPDATE ilbot_lines SET in_summary = TRUE WHERE id IN ('
                    . join(', ', ('?') x @check)
                    . ')';
        my $sth = $self->dbh->prepare($sql);
        $sth->execute(@check);
        $sth->finish;
    }

    my @uncheck = @{ $opt{uncheck} // [] };
    if (@uncheck) {
        my $sql = 'UPDATE ilbot_lines SET in_summary = FALSE WHERE id IN ('
                    . join(', ', ('?') x @uncheck)
                    . ')';
        my $sth = $self->dbh->prepare($sql);
        $sth->execute(@uncheck);
        $sth->finish;
    }
    return;
}

sub log_line {
    my ($self, %opt) = @_;
    for my $o (qw/channel line nick/) {
        die "Missing option '$o'" unless defined $opt{$o};
    }
    my $sql = $self->sql_for(query => 'log_line');
    my $sth = $self->dbh->prepare_cached($sql);
    my @ph = (@opt{qw/channel nick line/});
    $sth->execute(@ph);
    $sth->finish;
}

sub channel {
    my ($self, %opt) = @_;
    die "Missing option 'channel'" unless defined $opt{channel};
    return Ilbot::Backend::SQL::Channel->new(
        dbh     => $self->dbh,
        channel => $opt{channel},
        db      => $self->{db},
    );
}

package Ilbot::Backend::SQL::Channel;
use Ilbot::Config qw/config/;

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

sub _channel_id {
    my $self = shift;
    $self->_single_value($self->sql_for(query => 'channel_id'), $self->channel);
}

sub _day_id {
    my ($self, %opt) = @_;
    die 'Missing argument "day"' unless $opt{day};
    $self->_single_value($self->sql_for(query => 'day_id'), $self->channel, $opt{day});
}

sub summary_ids {
    my ($self, %opt) = @_;
    die "Missing argument 'day'" unless $opt{day};

    $self->dbh->selectcol_arrayref($self->sql_for(query => 'summary_ids'), undef, $self->_day_id(day => $opt{day}));
}

sub day_has_actitivity {
    my ($self, %opt) = @_;
    die "Missing option 'day'" unless $opt{day};
    return !! $self->_day_id(day => $opt{day});
}

sub activity_average {
    my $self = shift;
    my $sth = $self->dbh->prepare($self->sql_for(query => 'activity_average'));
    $sth->execute($self->_channel_id);
    my ($count, $days) = $sth->fetchrow;
    $sth->finish;
    return ($count || 1) / ($days || 1);
}

sub days_and_activity_counts {
    my $self = shift;
    my $r = $self->dbh->selectall_arrayref(
        $self->sql_for(query => 'days_and_activity_counts'),
        undef,
        $self->_channel_id,
    );

    return $r;
}

sub lines {
    my ($self, %opt) = @_;
    die "Missing option 'day'" unless $opt{day};
    my $di = $self->_day_id(day => $opt{day});
    return [] unless $di;
    if ($opt{after_id}) {
        return $self->dbh->selectall_arrayref(
            $self->sql_for(query => 'lines_after_id'),
            undef, $di, $opt{after_id}
        );
    }
    my $key = join '_', 'lines',
                ($opt{summary_only} ? 'summary' : 'nosummary'),
                ($opt{exclude_spam} // 1 ? 'spam' : 'nospam');
    my $r = $self->dbh->selectall_arrayref(
        $self->sql_for(query => $key), undef, $di,
    );

    return $r;
}

# XXX search_results doesn't really belong here, 
# but I'm too lazy to write yet anothe wrapper class around Backend::Search
# and Backend::SQL
sub search_results {
    my ($self, %opt) = @_;
    die "Missing argument 'q'" unless defined $opt{q};
    $opt{offset} //= 0;
    unless ($opt{offset} =~ /^[0-9]+\z/) {
        die "Invalid value for 'offset'";
    }
    return _search_backend()->channel(channel => $self->channel)->search_results(
        q       => $opt{q},
        nick    => $opt{nick},
        offset  => $opt{offset},
    );
}

sub activity_count {
    my ($self, %opt) = @_;
    for my $o (qw/from to/) {
        die "Missing option '$o'" unless $opt{$o};
    }
    $self->_single_value($self->sql_for(query => 'activity_count'),
            $self->_channel_id,
            @opt{qw/from to/});
}

sub first_day {
    my $self = shift;
    return $self->_single_value($self->sql_for(query => 'first_day_channel'), $self->_channel_id);
}

sub exists {
    my $self = shift;
    return !! $self->_channel_id;
}

1;
