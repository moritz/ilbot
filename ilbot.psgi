#!/usr/bin/perl
use lib 'lib';
use 5.010;

use Ilbot::Frontend;
use Ilbot::Backend::SQL;
use Ilbot::Backend::Cached;
use Ilbot::Date qw/gmt_today/;
use Ilbot::Config;
use Date::Simple qw/date/;

use Config::File qw/read_config_file/;
use Data::Dumper;

use Plack::Builder;

my $app = sub {
    my $env = shift;
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

    given ($env->{PATH_INFO}) {
        when ( qr{ ^/$ }x ) {
            $frontend->index(out_fh => $OUT);
        }
        when ( qr{ ^/ ([^./]+) /?$}x ) {
            $frontend->channel_index(channel => $1, out_fh => $OUT);
        }
        when ( qr{ ^/ ([^./]+) /today $}x ) {
            my $url = join '', 'http://',
                               $env->{HTTP_HOST},
                               "/$1/",
                               gmt_today();
            return [302, [Location => $url ], []];
        }
        when ( qr{ ^/ ([^./]+) /yesterday $}x ) {
            my $url = join '', 'http://',
                               $env->{HTTP_HOST},
                               "/$1/",
                               date(gmt_today()) - 1;
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

    }
    my $h = $frontend->http_header( accept => $env->{HTTP_ACCEPT} );

    return [200, $h, [$s]];
};

my $c = \&config;

builder {
    enable "Plack::Middleware::Static",
            path => qr{^/s/},
            root => $c->(www => 'static_path');
    $app;
}
