#!/usr/bin/env perl
use warnings;
use strict;
# use Date::Simple qw(date);
# use Encode::Guess;
# use Encode;
# use HTML::Template;
# use Config::File;
# use File::Slurp;
use lib 'lib';
use IrcLog qw(get_dbh);
# use IrcLog::WWW qw(http_header message_line my_encode);
# use Cache::SizeAwareFileCache;

return sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my @actions = (scalar($req->param('uncheck')), scalar($req->param('check')));

    for (@actions) {
        die "Invalid parameter format" unless /^(?:[0-9]+(?:\.[0-9]+)*)?$/
    }

    my $dbh = get_dbh();

    for (0, 1) {
        if (length($actions[$_])) {
            my @ids = split /\./, $actions[$_];
            my $sth = $dbh->prepare("UPDATE irclog SET in_summary = $_ WHERE id IN (".
                                    join(', ', ('?') x @ids) . ')');
            $sth->execute(@ids);
        }
    }

    my $response = Plack::Response->new(201);
    return $response->finalize;
};
