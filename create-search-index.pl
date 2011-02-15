#!/usr/bin/env perl
use strict;
use warnings;
use KinoSearch::Plan::Schema;
use KinoSearch::Plan::FullTextType;
use KinoSearch::Plan::StringType;
use KinoSearch::Analysis::PolyAnalyzer;
use KinoSearch::Index::Indexer;

my $schema      = KinoSearch::Plan::Schema->new;
my $poly_an     = KinoSearch::Analysis::PolyAnalyzer->new(language => 'en');
my $full_text   = KinoSearch::Plan::FullTextType->new(
                    analyzer => $poly_an,
                  );
my $string      = KinoSearch::Plan::StringType->new( stored => 0);
my $kept_string = KinoSearch::Plan::StringType->new( stored => 1, sortable => 1);
my $sort_string = KinoSearch::Plan::StringType->new( stored => 0, sortable => 1);

$schema->spec_field(name => 'line',     type => $full_text);
$schema->spec_field(name => 'nick',     type => $string);
$schema->spec_field(name => 'channel',  type => $kept_string);
$schema->spec_field(name => 'day',      type => $sort_string);
$schema->spec_field(name => 'timestamp',type => $sort_string);
$schema->spec_field(name => 'id',       type => $kept_string);

my $indexer = KinoSearch::Index::Indexer->new(
    schema  => $schema,
    index   => 'stemmed',
    create  => 1,
);

use lib '../lib';
use IrcLog qw(get_dbh);

my $dbh = get_dbh;

my $sth = $dbh->prepare('SELECT channel, day, nick, timestamp, line, id FROM irclog');
$sth->execute();
$sth->bind_columns(\my ($channel, $day, $nick, $timestamp, $line, $id));
while ($sth->fetch) {
    $indexer->add_doc({
            channel     => $channel,
            day         => $day,
            nick        => $nick,
            timestamp   => $timestamp,
            line        => $line,
            id          => $id,
    });

}
$indexer->commit;
