# vim: ft=perl
use strict;
use warnings;

use Plack::Builder;
use Plack::Util;
use Plack::App::Directory;
use Plack::Request;
use URI;

my $index_app = Plack::Util::load_psgi('www/index.pl');
my $channel_index_app = Plack::Util::load_psgi('www/channel-index.pl');
my $out_app = Plack::Util::load_psgi('www/out.pl');
my $spam_app = Plack::Util::load_psgi('www/spam.pl');
my $save_summary_app = Plack::Util::load_psgi('www/save_summary.pl');
my $text_app = Plack::Util::load_psgi('www/text.pl');
my $search_app = Plack::Util::load_psgi('www/search.pl');
my $static_app = Plack::App::Directory->new({ root => "www/static" })->to_app;

# TODO - some routing middleware would be better than manual dispatching
my $app = sub {
    my $env = shift;

    my $req = Plack::Request->new($env);
    local $_ = $req->path_info;

    return $static_app->($env) if m{\.(js|css|png|ico)$};

    warn $_;

    # these routes are deprecated and should be removed eventually
    {
        # /out.pl?channel=foo&date=today
        if (m{^/out\.pl$}) {
            warn "QUERY_STRING: $env->{QUERY_STRING}";
            my $uri = URI->new("/?$env->{QUERY_STRING}");
            my %params = $uri->query_form;
            use Data::Dumper; warn Dumper \%params;
            return [301, [ Location => $req->base."$params{channel}/$params{date}" ], []];
        }
    }

    if (m{^/search}) {
        if (m{^/search/(\d+)/(.+)$}) {
            $env->{QUERY_STRING} = "offset=$1&q=$2";
        }
        elsif (m{^/search/(.*)$}) {
            $env->{QUERY_STRING} = "offset=0&q=$2";
        }
        return $search_app->($env);
    }
    return $text_app->($env) if m{^/text\.pl$}; # /text.pl?channel=foo&date=today
    return $spam_app->($env) if m{^/spam\.pl$}; # /spam.pl
    return $save_summary_app->($env) if m{^/save_summary\.pl$}; # /save_summary.pl
    return $out_app->($env) if m{^/([^/]+/.+)};     # /channel/date
    return $channel_index_app->($env) if m{^/([^/]+/?)$};    # /channel
    return $index_app->($env) if m{^/$};    # /

    return [404, [], ['Not found']];
};

return $app;
