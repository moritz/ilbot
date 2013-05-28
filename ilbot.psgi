#!/usr/bin/perl
use lib 'lib'; # just for local testing
# TO BE REPLACED BY THE INSTALLER
use 5.010;

use Ilbot::Config '/home/moritz/src/ilbot/config/';
use Ilbot::Frontend;
use Ilbot::Backend::SQL;
use Ilbot::Backend::Cached;
use Ilbot::Date qw/today/;
use Date::Simple qw/date/;
use Encode qw/encode_utf8/;

# I don't know what the p5 porters where thinking
# when they enabled this warning by default
no if $] >= 5.018, 'warnings', "experimental::smartmatch";

use Config::File qw/read_config_file/;
use Data::Dumper;

use Plack::Request;

use Ilbot::Config;
my $frontend = _frontend();

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $channel_re = qr{[^./]+};
    my $s;
    given ($req->path_info) {
        when ( qr{ ^/$ }x ) {
            $s = $frontend->index;
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
            $s = $frontend->channel_index(channel => $1, out_fh => $OUT)
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel']];
        }
        when ( qr{ ^/ ($channel_re) /search/?$}x ) {
            my $p = $req->query_parameters;
            $s = $frontend->search(
                channel => $1,
                q       => scalar($p->{q}),
                nick    => scalar($p->{nick}),
                offset  => scalar($p->{offset}),
            )
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel']];
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
            $s = $frontend->day(
                channel => $1,
                day     => $2,
                summary => !! $3,
            )
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel/day']];
        }
        when ( qr! ^/ ([^./]+) / (\d{4}-\d{2}-\d{2}) ( (?: /text)? ) $!x ) {
            $s = $frontend->day_text(
                channel => $1,
                day     => $2,
            )
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel/day']];
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
my $rate = config('www' => 'throttle');
use Plack::Builder;
if ($rate) {
    $app = builder {
        enable 'Throttle::Lite',
            limits  => "$rate req/hour",
            backend => 'Simple',
            routes  => qr{.},
            ;
        $app;
    };
}

$app = builder {
    enable "Plack::Middleware::Static",
            path => qr{^/(?:robots\.txt|s/)},
            root => $c->(www => 'static_path');
    $app;
};
# vim: ft=perl
