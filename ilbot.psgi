#!/usr/bin/env plackup
use lib 'lib';
use 5.010;

use Ilbot::Config '/home/moritz/src/ilbot/config/';
use Ilbot::Frontend;
use Ilbot::Backend::SQL;
use Ilbot::Backend::Cached;
use Ilbot::Date qw/today/;
use Ilbot::Config;
use Date::Simple qw/date/;
use Encode qw/encode_utf8/;

use Config::File qw/read_config_file/;
use Data::Dumper;

use Plack::Builder;
use Plack::Request;

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $channel_re = qr{[^./]+};
    my $sql      = Ilbot::Backend::SQL->new(
        config      => config('backend'),
    );
    my $backend  = Ilbot::Backend::Cached->new(
        backend     => $sql,
    );
    my $frontend = Ilbot::Frontend->new(
        backend     => $backend,
    );
    open my $OUT, '>', \my $s;

    given ($req->path_info) {
        when ( qr{ ^/$ }x ) {
            $frontend->index(out_fh => $OUT);
        }
        when ( qr{ ^/e/summary }x ) {
            my $p = $req->body_parameters;
            my %actions;
            for my $a (qw(check uncheck)) {
                if ($p->{$a} =~ /^([0-9]+(?:\.[0-9]+)*)\z/) {
                    $actions{$a} = [ split /\./, $1 ];
                }
            }
            if ($req->method eq 'POST' && keys(%actions)) {
                $frontend->update_summary(%actions);
                return [201, [], []];
            }
        }
        when ( qr{ ^/ ($channel_re) /?$}x ) {
            $frontend->channel_index(channel => $1, out_fh => $OUT);
        }
        when ( qr{ ^/ ($channel_re) /search/?$}x ) {
            my $p = $req->query_parameters;
            $frontend->search(
                channel => $1,
                out_fh  => $OUT,
                q       => scalar($p->{q}),
                nick    => scalar($p->{nick}),
                offset  => scalar($p->{offset}),
            );
        }
        when ( qr{ ^/ ($channel_re) /today $}x ) {
            my $url = join '', 'http://',
                               $env->{HTTP_HOST},
                               "/$1/",
                               today();
            return [302, [Location => $url ], []];
        }
        when ( qr{ ^/ ([^./]+) /yesterday $}x ) {
            my $url = join '', 'http://',
                               $env->{HTTP_HOST},
                               "/$1/",
                               date(today()) - 1;
            return [302, [Location => $url ], []];
        }
        when ( qr! ^/ ([^./]+) / (\d{4}-\d{2}-\d{2}) ( (?: /summary)? ) $!x ) {
            $frontend->day(
                channel => $1,
                day     => $2,
                out_fh  => $OUT,
                summary => !! $3,
            );
        }
        when ( qr! ^/ ([^./]+) / (\d{4}-\d{2}-\d{2}) ( (?: /text)? ) $!x ) {
            $s = $frontend->day_text(
                channel => $1,
                day     => $2,
            );
            return [200, ["Content-Type" => "text/plain; charset=UTF-8"], [$s]];
        }
        default {
            return [404, [], []];
        }

    }
    my $h = $frontend->http_header( accept => $env->{HTTP_ACCEPT} );
    close $out_fh;

    return [200, $h, [encode_utf8 $s]];
};

my $c = \&config;

$app = builder {
    enable "Plack::Middleware::Static",
            path => qr{^/(?:robots\.txt|s/)},
            root => $c->(www => 'static_path');
    $app;
};
