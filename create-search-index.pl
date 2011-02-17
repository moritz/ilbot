#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use autodie;
use File::Spec;
use KinoSearch::Plan::Schema;
use KinoSearch::Plan::FullTextType;
use KinoSearch::Plan::StringType;
use KinoSearch::Analysis::PolyAnalyzer;
use KinoSearch::Index::Indexer;

my $schema      = KinoSearch::Plan::Schema->new;
my $poly_an     = KinoSearch::Analysis::PolyAnalyzer->new(language => 'en');
my $full_text   = KinoSearch::Plan::FullTextType->new(
                    analyzer => $poly_an,
                    stored   => 0,
                  );
my $string      = KinoSearch::Plan::StringType->new( stored => 0);
my $kept_string = KinoSearch::Plan::StringType->new( stored => 1, sortable => 1);
my $sort_string = KinoSearch::Plan::StringType->new( stored => 0, sortable => 1);

$schema->spec_field(name => 'line',     type => $full_text);
$schema->spec_field(name => 'nick',     type => $string);
$schema->spec_field(name => 'channel',  type => $kept_string);
$schema->spec_field(name => 'day',      type => $kept_string);
$schema->spec_field(name => 'timestamp',type => $sort_string);
$schema->spec_field(name => 'id',       type => $kept_string);

my $idx_path = 'stemmed';
my $last_id_file = File::Spec->catfile($idx_path, 'last_id.txt');

my ($create, @last_id);
{
    if (-d $idx_path) {
        open my $last_fh, '<', File::Spec->catfile($last_id_file);
        my $last_id = <$last_fh>;
        close $last_fh;
        chomp $last_id;
        push @last_id, $last_id;
    } else {
        print "No previous index found, generating a new one\n";
        print "This might take some time; please be patient\n";
        $create = 1;
    }
}

my $indexer = KinoSearch::Index::Indexer->new(
    schema  => $schema,
    index   => 'stemmed',
    create  => $create,
);

use IrcLog qw(get_dbh);

my $dbh = get_dbh;
my $where = '';

unless ($create) {
    $where = 'WHERE id > ?'
}

my $sth = $dbh->prepare("SELECT channel, day, nick, timestamp, line, id FROM irclog $where ORDER BY id ASC");
$sth->execute(@last_id);
$sth->bind_columns(\my ($channel, $day, $nick, $timestamp, $line, $id));
my $last = -9e99;
while ($sth->fetch) {
    $nick =~ s/^\* //;
    $indexer->add_doc({
            channel     => $channel,
            day         => $day,
            nick        => $nick,
            timestamp   => $timestamp,
            line        => $line,
            id          => $id,
    });
    $last = $id if $id > $last;

}
$indexer->commit;
open my $h, '>', $last_id_file;
print { $h } "$last\n" or die "can't write to file '$last_id_file': $!";
close $h;
