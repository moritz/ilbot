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
use JSON;

# I don't know what the p5 porters where thinking
# when they enabled this warning by default
no if $] >= 5.018, 'warnings', "experimental::smartmatch";

use Config::File qw/read_config_file/;
use Data::Dumper;

use Plack::Request;

use Ilbot::Config;
my $frontend = _frontend();

# some channels like #perl.pl contain dots,
# be we can't generally allow dots in channel names,
# because then robots.txt etc. would be handled that way.
my $channel_re = join '|', '[^./]+',
    map quotemeta,
    grep /\W/,
    map { s/^#+//; $_ }
    @{ $frontend->backend->channels };
$channel_re    = qr{(?:$channel_re)};

my $handle_json = sub {
    my $req = shift;
    state $json_fe  = _json_frontend();
    my $error;

    given ($req->path_info) {
        when ( qr{ ^/$ }x ) {
            $s = $json_fe->index;
        }
        when ( qr{ ^/ ($channel_re) /? $ }x ) {
            $s = $json_fe->channel_index(channel => $1, out_fh => $OUT)
                or $error = 'No such channel';
        }
        when ( qr! ^/ ($channel_re) / (\d{4}-\d{2}-\d{2}) $ !x ) {
            $s = $json_fe->day(
                channel => $1,
                day     => $2,
            ) or $error = 'No such channel or day';
        }
    };
    return ($s, $error);

};


my $app = sub {
    my $env = shift;
    $frontend->ping();
    my $req = Plack::Request->new($env);
    my $want_json = $req->headers->header('Accept') eq 'application/json';
    if ($want_json) {
        state $json_headers = ['Content-Type', 'application/json; charset=UTF-8'];
        my ($res, $error) = $handle_json->($req);
        if ($res) {
            # TODO: Content-Type header
            return [200, $json_headers, [encode_json $res]];
        }
        else {
            return [404, $json_headers, [encode_json { error => $error || 'URL not known' }]];
        }
    }
    my $s;
    given ($req->path_info) {
        when ( qr{ ^/$ }x ) {
            $s = $frontend->index;
        }
        when (qr!^/e/($channel_re)/(\d{4}-\d{2}-\d{2})/summary\z!) {
            $s = $frontend->summary_ids(channel => "#$1", day => $2);
            return [200, ['Content-Type', 'application/json'], [$s]];
        }
        when (qr!^/e/($channel_re)/(\d{4}-\d{2}-\d{2})/ajax/(\d+)\z!) {
            $s = $frontend->day(
                channel     => $1,
                day         => $2,
                after_id    => $3,
            );
            return [200, ['Content-Type', 'application/json'], [
                    encode_json({
                            text         => $s,
                            still_today  => $2 eq today() ? JSON::true : JSON::false,
                    }),
            ]];
            # TODO: return value!
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
        when ( qr! ^/ ($channel_re) / (\d{4}-\d{2}-\d{2}) ( (?: /summary)? ) $!x ) {
            $s = $frontend->day(
                channel => $1,
                day     => $2,
                summary => !! $3,
            )
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel/day']];
        }
        when ( qr! ^/ ($channel_re) / (\d{4}-\d{2}-\d{2}) /text $!x ) {
            $s = $frontend->day_text(
                channel => $1,
                day     => $2,
            )
                or return [404, ['Content-Type' => 'text/plain'], ['No such channel/day']];
            return [200, ["Content-Type" => "text/plain; charset=UTF-8"], [encode_utf8 $s]];
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
    if ( -d $c->('config_root') . '/d' ) {
        enable "Plack::Middleware::Static",
                path => qr[^/($channel_re)/\d{4}-\d{2}-\d{2}/?],
                pass_through => 1,
                content_type => 'text/html; charset=UTF-8',
                root => $c->('config_root') . '/d';
    }
    $app;
};
# vim: ft=perl
