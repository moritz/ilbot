package Ilbot::Backend::SQL;

use strict;
use warnings;
use 5.010;
use DBI;

our %SQL = (
    STANDARD    => {
        channels                 => 'SELECT DISTINCT(channel) FROM irclog ORDER BY channel',
        first_day                => 'SELECT MIN(day) FROM irclog',
        day_has_actitivity       => 'SELECT 1 FROM irclog WHERE channel = ? AND day = ? AND not spam LIMIT 1',
        activity_count           => q[SELECT COUNT(id) FROM irclog WHERE channel = ?
    AND day BETWEEN ? AND ? AND nick <> ''],
        days_and_activity_counts => q[SELECT day, count(*) FROM irclog WHERE channel = ? AND nick <> '' GROUP BY day ORDER BY day],
        activity_average         => q[SELECT COUNT(*), MAX(day) - MIN(day) FROM irclog WHERE channel = ? AND nick <> ''],
        lines_nosummary_nospam   => q[SELECT id, nick, timestamp, line, in_summary FROM irclog WHERE day = ? AND channel = ? AND NOT spam ORDER BY id],
        lines_summary_nospam     => q[SELECT id, nick, timestamp, line, in_summary FROM irclog WHERE day = ? AND channel = ? AND NOT spam AND in_summary ORDER BY id],
        lines_nosummary_spam     => q[SELECT id, nick, timestamp, line, in_summary FROM irclog WHERE day = ? AND channel = ? ORDER BY id],
        lines_summary_spam       => q[SELECT id, nick, timestamp, line, in_summary FROM irclog WHERE day = ? AND channel = ? AND in_summary ORDER BY id],
    },
    mysql       => {
        activity_average         => q[SELECT COUNT(*), DATEDIFF(DATE(MAX(day)), DATE(MIN(day))) FROM irclog WHERE channel = ? AND nick <> ''],
        search_count             => q[SELECT COUNT(id) FROM irclog WHERE channel = ? AND MATCH(line) AGAINST(?)],
        search_count_nick        => q[SELECT COUNT(id) FROM irclog WHERE channel = ? AND MATCH(line) AGAINST(?) AND (nick IN (?, ?))],
        search_result_days       => q[SELECT DISTINCT(day) line FROM irclog WHERE channel = ? AND MATCH(line) AGAINST (?) ORDER BY id DESC LIMIT 10 OFFSET ?],
        search_result_nick_days  => q[SELECT DISTINCT(day) line FROM irclog WHERE channel = ? AND MATCH(line) AGAINST (?) AND nick IN (?, ?) LIMIT 10 OFFSET ?],
        search_result            => q[SELECT id, nick, timestamp, line, in_summary, IF(MATCH(line) AGAINST(?), 1, 0) FROM irclog WHERE channel = ? AND day = ? AND nick <> ''],
        search_result_nick       => q[SELECT id, nick, timestamp, line, in_summary, IF(MATCH(line) AGAINST(?) AND nick IN (?, ?), 1, 0) FROM irclog WHERE channel = ? AND day = ? AND nick <> ''],
    },
);

my %post_connect = (
    mysql   => sub { $_[0]{mysql_enable_utf8} = 1 },
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
    my $sql = 'SELECT channel, day FROM  irclog WHERE id IN ('
                . join(', ', ('?') x @ids)
                . ') GROUP BY channel, day';
    return $self->dbh->selectall_arrayref($sql, undef, @ids);
}

sub update_summary {
    my ($self, %opt) = @_;

    # SQL depends on the number of elements, so
    # can't simply be obtained with sql_for
    my @check = @{ $opt{check} // [] };
    if (@check) {
        my $sql = 'UPDATE irclog SET in_summary = TRUE WHERE id IN ('
                    . join(', ', ('?') x @check)
                    . ')';
        my $sth = $self->dbh->prepare($sql);
        $sth->execute(@check);
        $sth->finish;
    }

    my @uncheck = @{ $opt{uncheck} // [] };
    if (@uncheck) {
        my $sql = 'UPDATE irclog SET in_summary = FALSE WHERE id IN ('
                    . join(', ', ('?') x @uncheck)
                    . ')';
        my $sth = $self->dbh->prepare($sql);
        $sth->execute(@uncheck);
        $sth->finish;
    }
    return;
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
use List::Util qw/max min/;
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
    return ($count || 1) / ($days || 1);
}

sub days_and_activity_counts {
    my $self = shift;
    my $r = $self->dbh->selectall_arrayref(
        $self->sql_for(query => 'days_and_activity_counts'),
        undef,
        $self->channel,
    );

    return $r;
}

sub lines {
    my ($self, %opt) = @_;
    die "Missing option 'day'" unless $opt{day};
    my $key = join '_', 'lines',
                ($opt{summary_only} ? 'summary' : 'nosummary'),
                ($opt{exclude_spam} // 0 ? 'spam' : 'nospam');
    my $r = $self->dbh->selectall_arrayref(
        $self->sql_for(query => $key),
        undef,
        $opt{day},
        $self->channel,
    );

    return $r;
}

sub search_count {
    my ($self, %opt) = @_;
    die "Missing argument 'q'" unless defined $opt{q};
    my @bind_param = ($self->channel, $opt{q});
    my $sql;
    if (defined $opt{nick} && length $opt{nick}) {
        $sql = $self->sql_for(query => 'search_count_nick');
        push @bind_param, $opt{nick}, "* $opt{nick}";
    }
    else {
        $sql = $self->sql_for(query => 'search_count');
    }
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@bind_param);
    my ($count) = $sth->fetchrow_array;
    $sth->finish;
    return $count;
}

sub search_results {
    my ($self, %opt) = @_;
    die "Missing argument 'q'" unless defined $opt{q};
    $opt{offset} //= 0;
    unless ($opt{offset} =~ /^[0-9]+\z/) {
        die "Invalid value for 'offset'";
    }
    my @bind_param = ($self->channel, $opt{q});
    my $nick     = $opt{nick};
    my $has_nick = defined($nick) && length($nick);
    my $sql;
    if ($has_nick) {
        $sql = $self->sql_for(query => 'search_result_nick_days');
        push @bind_param, $nick, "* $nick";
    }
    else {
        $sql = $self->sql_for(query => 'search_result_days');
    }
    # mysql doesn't seem to allow bind parameters for the offset, so
    # needs a bit of special care
    if (lc $self->{db} eq 'mysql') {
        $sql =~ s/.*\K\?/$opt{offset}/;
    }
    else {
        push @bind_param, $opt{offset};
    }
    my $days = $self->dbh->selectcol_arrayref($sql, undef, @bind_param);
    my @res;
    my $context = config(backend => 'search_context');
    for my $d (@$days) {
        my $sql = $has_nick
                    ? $self->sql_for(query => 'search_result_nick')
                    : $self->sql_for(query => 'search_result');
        @bind_param = ($opt{q}, ($has_nick ? ($nick, "* $nick") : ()), $self->channel, $d);
        my @d_res;
        my $lines = $self->dbh->selectall_arrayref($sql, undef, @bind_param);
        # $lines now contains all the lines for that day.
        # filter out only those lines that matched, plus a bit of context
        # before and after. Since the context can overlap, simply
        # mark all to-be-returned indexes, and then later get the desired
        # lines with a slice
        my @return_idx = (0) x @$lines;
        my @idx = 0..$#$lines;
        for my $idx (@idx) {
            if ($lines->[$idx][5]) {
                for (max($idx - $context, 0) .. min($#$lines, $idx + $context)) {
                    $return_idx[$_] = 1;
                }
            }
        }
        @idx = grep $return_idx[$_], @idx;
        $lines = [ @{$lines}[@idx] ];
        push @res, $d => $lines;
    }
    return \@res;
}

sub activity_count {
    my ($self, %opt) = @_;
    for my $o (qw/from to/) {
        die "Missing option '$o'" unless $opt{$o};
    }
    $self->_single_value($self->sql_for(query => 'activity_count'),
            $self->channel,
            @opt{qw/from to/});
}

1;
