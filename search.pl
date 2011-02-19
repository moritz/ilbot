use strict;
use warnings;
use 5.010;
use lib 'lib';
use IrcLog qw(get_dbh);

use List::MoreUtils qw/uniq/;

use KinoSearch::Search::IndexSearcher;
use KinoSearch::Search::SortSpec;


my $query = shift(@ARGV) // 'channel:#perl6 AND nick:moritz_ p4';
my $index_dir = '/home/moritz/src/irclog/stemmed/';
die "No such dir: $index_dir" unless -d $index_dir;

my $s = KinoSearch::Search::IndexSearcher->new(
    index => $index_dir,
);
my $sort_spec = KinoSearch::Search::SortSpec->new(
    rules => [
        KinoSearch::Search::SortRule->new( field => 'day', reverse => 1),
        KinoSearch::Search::SortRule->new( field => 'channel'),
        KinoSearch::Search::SortRule->new( field => 'timestamp'),
        KinoSearch::Search::SortRule->new( field => 'id'),
    ],
);

my $query_parser = KinoSearch::Search::QueryParser->new(
    schema          => $s->get_schema,
    default_boolop  => 'AND',
);
$query_parser->set_heed_colons(1);

my $hits = $s->hits(
    query       => $query_parser->parse($query),
    sort_spec   => $sort_spec,
    offset      => 0,
    num_wanted  => 100,
);

my $context = 3;
my $q_context = get_dbh()->prepare(qq[
    (SELECT id, nick, line, day, channel, timestamp FROM irclog WHERE channel = ? AND day = ? AND id < ? AND nick <> '' ORDER BY id DESC LIMIT $context)
    UNION
    (SELECT id, nick, line, day, channel, timestamp FROM irclog WHERE channel = ? AND day = ? AND id >= ? AND nick <> '' ORDER BY id ASC LIMIT $context)
]);


my @lines;
my %search_for;
while (my $hit = $hits->next) {
    $search_for{ $hit->{id} } = 1;
    $q_context->execute(@$hit{<channel day id channel day id>});
    push @lines, $_ while $_ = $q_context->fetchrow_hashref;
}

my %seen;
@lines = grep {!$seen{$_->{id}}++ } sort { $a->{id} <=> $b->{id} } @lines;

my @blocks;

{
    my $prev_channel = '';
    my $prev_day = '';
    my @prev;
    for (@lines) {
        if ($_->{day} eq $prev_day && $_->{channel} eq $prev_channel) {
            push @prev, $_;
        } else {
            push @blocks, [@prev] if @prev;
            @prev = $_;
            $prev_channel = $_->{channel};
            $prev_day     = $_->{day};
        }
    }
    push @blocks, \@prev if @prev;
}

for my $block (@blocks) {
    say $block->[0]{channel}, ' ', $block->[0]{day};
    for (@$block) {
        print '<*> ' if $search_for{ $_->{id} };
        say join('  ', @$_{<id nick line>});
    }
}
