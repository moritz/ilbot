#!/usr/bin/perl
use lib 'lib';
use 5.010;

use Ilbot::Frontend;
use Ilbot::Backend::SQL;
use Ilbot::Date qw/gmt_today/;

use Config::File qw/read_config_file/;
use Data::Dumper;

my $app = sub {
    my $env = shift;
#    print Dumper $env;
    my $backend = Ilbot::Backend::SQL->new(
        config      => read_config_file('database.conf'),
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
            warn "CHANNEL_INDEX: $1";
            $frontend->channel_index(channel => $1, out_fh => $OUT);
        }
        when ( qr{ ^/ ([^./]+) /today $}x ) {
            my $url = join '', $env->{'psgi.url_scheme'},
                               $env->{HTTP_HOST},
                               "/$1/",
                               gmt_today();
            return [302, [Location => $url ], []];
        }
        when ( qr! ^/ ([^./]+) / (\d{4}-\d{2}-\d{2}) $!x ) {
            $frontend->day(channel => $1, day => $2, out_fh => $OUT);
        }

    }

    return [200, [ 'Content-Type' => 'text/html; charset=utf-8' ], [$s]];
}
