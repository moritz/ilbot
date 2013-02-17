#!/usr/bin/env perl
use warnings;
use strict;
use Carp qw(confess);
use lib '..';
use Config::File;
use Data::Dumper;
use HTML::Template;
use lib 'lib';
use IrcLog qw(get_dbh);
use IrcLog::WWW 'http_header_obj';

use Plack::Request;
use Plack::Response;

return sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    my @range =  sort $req->param("range");
    my @single =  $req->param("single");

    my $dbh = get_dbh();

    my $range_count = scalar @range;

    my $d1 = $dbh->prepare("UPDATE irclog SET spam = 1 WHERE id >= ? AND id <= ?");
    my $d2 = $dbh->prepare("UPDATE irclog SET spam = 1 WHERE id = ?");

    my $count = 0;

    if ($range_count == 2){
        $count += $d1->execute($range[0], $range[1]);
    }
    elsif ($range_count == 0){
        # do nothing
    }
    else {
        confess "Select $range_count 'range' checkboxes, for security reasons only "
            . "two (or zero) are allowed";
    }

    for my $id (@single){
        $count += $d2->execute($id);
    }

    my $t = HTML::Template->new(
            filename => 'www/template/spam.tmpl',
            die_on_bad_params => 0,
    );

    my $conf = Config::File::read_config_file("www/www.conf");
    my $base_url = $conf->{BASE_URL} || "/";
    my $channel = $req->query_parameters->get('channel');
    $channel =~ s/^\#//x;

    $t->param(DATE      => $req->query_parameters->get('date'));
    $t->param(COUNT     => $count);
    $t->param(BASE_URL  => $base_url);
    $t->param(CHANNEL   => $channel);


    my $response = Plack::Response->new(200);
    $response->headers( http_header_obj({no_xhtml => 1}) );
    $response->body($t->output);

    return $response->finalize;
};

# vim: expandtab sw=4 ts=4
