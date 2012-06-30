#!/usr/bin/env perl
use warnings;
use strict;
use Carp qw(confess);
use Date::Simple qw(date);
use Encode::Guess;
use Encode;
use HTML::Template;
use Config::File;
use File::Slurp;
use lib 'lib';
use IrcLog qw(get_dbh gmt_today);
use IrcLog::WWW qw(http_header_obj message_line my_encode);
use Cache::SizeAwareFileCache;

use Plack::Request;
use Plack::Response;
#use Data::Dumper;


# Configuration
# $base_url is the absoulte URL to the directoy where index.pl and out.pl live
# If they live in the root of their own virtual host, set it to "/".
my $conf = Config::File::read_config_file('www/www.conf');
my $base_url = $conf->{BASE_URL} || q{/};

# I'm too lazy right to move this to  a config file, because Config::File seems
# unable to handle arrays, just hashes.

# map nicks to CSS classes.
my @colors = (
        ['TimToady',    'nick_timtoady'],
        ['audreyt',     'nick_audreyt'],
        ['evalbot',     'bots'],
        ['exp_evalbot', 'bots'],
        ['p6eval',      'bots'],
        ['lambdabot',   'bots'],
        ['pugs_svnbot', 'bots'],
        ['pugs_svn',    'bots'],
        ['specbot',     'bots'],
        ['speckbot',    'bots'],
        ['pasteling',   'bots'],
        ['rakudo_svn',  'bots'],
        ['purl',        'bots'],
        ['svnbotlt',    'bots'],
        ['dalek',       'bots'],
        ['hugme',       'bots'],
        ['garfield',    'bots'],
    );
# additional classes for nicks, sorted by frequency of speech:
my @nick_classes = map { "nick$_" } (1 .. 9);

# Default channel: this channel will be shown if no channel=... arg is given
my $default_channel = 'perl6';

# End of config

sub irclog_output {
    my ($date, $channel, $dbh, $admin, $summary) = @_;

    my $full_channel = q{#} . $channel;
    my $t = HTML::Template->new(
            filename            => 'www/template/day.tmpl',
            loop_context_vars   => 1,
            global_vars         => 1,
            die_on_bad_params   => 0,
            );

    $t->param(ADMIN => 1) if $admin;

    {
        my $clf = "channels/$channel.tmpl";
        if (-e $clf) {
            $t->param(CHANNEL_LINKS => q{} . read_file($clf));
        }
    }
    $t->param(BASE_URL  => $base_url);
    my $self_url = $base_url . "/$channel/$date";
    my $db;
    
    if ($summary) {
        $db = $dbh->prepare('SELECT id, nick, timestamp, line, in_summary FROM '
            . 'irclog WHERE day = ? AND channel = ? AND NOT spam AND in_summary = 1 ORDER BY id');
    }
    else {
        $db = $dbh->prepare('SELECT id, nick, timestamp, line, in_summary FROM '
            . 'irclog WHERE day = ? AND channel = ? AND NOT spam ORDER BY id');
    }
    $db->execute($date, $full_channel);


    # determine which colors to use for which nick:
    {
        my $count = scalar @nick_classes + scalar @colors + 1;
        my $q1 = $dbh->prepare('SELECT nick, COUNT(nick) AS c FROM irclog'
                . ' WHERE day = ? AND channel = ? AND not spam'
                . " GROUP BY nick ORDER BY c DESC LIMIT $count");
        $q1->execute($date, $full_channel);
        while (my @row = $q1->fetchrow_array and @nick_classes){
            next unless length $row[0];
            my $n = quotemeta $row[0];
            unless (grep { $_->[0] =~ m/\A$n/smx } @colors){
                push @colors, [$row[0], shift @nick_classes];
            }
        }
#    $t->param(DEBUG => Dumper(\@colors));
    }

    my @msg;

    my $line = 1;
    my $prev_nick = q{};
    my $c = 0;

# populate the template
    my $line_number = 0;
    while (my @row = $db->fetchrow_array){
        my $id = $row[0];
        my $nick = decode('utf8', ($row[1]));
        my $timestamp = $row[2];
        my $message = $row[3];
        my $in_summary = $row[4];
        next if $message =~ m/^\s*\[off\]/i;

        push @msg, message_line( {
                id           => $id,
                nick        => $nick,
                timestamp   => $timestamp,
                message     => $message,
                line_number =>  ++$line_number,
                prev_nick   => $prev_nick,
                colors      => \@colors,
                self_url    => $self_url,
                channel     => $channel,
                in_summary  => $in_summary,
                },
                \$c,
                );
        $prev_nick = $nick;
    }

    $t->param(
            CHANNEL     => $channel,
            MESSAGES    => \@msg,
            DATE        => $date,
            IS_SUMMARY  => $summary,
        );

# check if previous/next date exists in database
    {
        my $q1 = $dbh->prepare('SELECT COUNT(*) FROM irclog '
                . 'WHERE channel = ? AND day = ? AND NOT spam');
        # Date::Simple magic ;)
        my $tomorrow = date($date) + 1;
        $q1->execute($full_channel, $tomorrow);
        my ($res) = $q1->fetchrow_array();
        if ($res || $tomorrow eq gmt_today()){
            my $next_url = $base_url . "$channel/$tomorrow";
            # where the hell does the leading double slash come from?
            $next_url =~ s{^//+}{/};
            $t->param(NEXT_URL => $next_url);
        }

        my $yesterday = date($date) - 1;
        $q1->execute($full_channel, $yesterday);
        ($res) = $q1->fetchrow_array();
        if ($res){
            my $prev_url = $base_url . "$channel/$yesterday";
            $prev_url =~ s{^//+}{/};
            $t->param(PREV_URL => $prev_url);
        }

    }

    return my_encode($t->output);
}


return sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $response = Plack::Response->new(200);

    my $dbh = get_dbh();
    my $admin_flag = $req->param('admin');
    my $channel = $req->param('channel') || $default_channel;
    my $date = $req->param('date');
    my $summary = $req->param('summary');

    {
        my $path = $req->path;
        $path =~ s{^/*}{};
        if ($path =~ m{^([^/]+)/yesterday/?$}) {
            $channel = $1;
            $date = 'yesterday';
        }
        elsif ($path =~ m{^([^/]+)/today/?$}) {
            $channel = $1;
            $date = 'today';
        }
        elsif ($path =~ m{^([^/]+)$}) {
            $channel = $1;
        }
        elsif ($path =~ m{^([^/]+)/(\d\d\d\d-\d\d-\d\d)}) {
            $channel = $1;
            $date = $2;
        }
        elsif ($path eq '' or $path eq 'out.pl') {
            # ok
        }
        else {
            return [404, [], ["$path Not found"]];
        }
    }

    {
        my $redirect;
        if (!$date || $date eq 'today') {
            $date = gmt_today();
            $redirect = 1;
        } elsif ($date eq 'yesterday') {
            $date = date(gmt_today()) - 1;
            $redirect = 1;
        }

        if ($redirect && !$summary) {
            my $url = $req->base . "/$channel/$date";
            $response->redirect($url);
            my $body = "<html><head><title>Redirect to $url</title></head>\n";
            $body .= "<body><p>If your browser doesn't like you, please follow\n";
            $body .= qq[<a href="$url">this link</a> manually.</body></html>\n];
            $response->body($body);
            return $response->finalize;
        }
    }

    if ($date eq gmt_today()) {
        $response->headers( http_header_obj({ nocache => 1}) );
    } else {
        $response->headers( http_header_obj() );
    }


    if ($channel !~ m/\A[.\w-]+\z/smx){
        # guard against channel=../../../etc/passwd or so
        confess 'Invalid channel name';
    }

    my $count;
    {
        my $sth = $dbh->prepare_cached('SELECT COUNT(*) FROM irclog WHERE day = ?');
        $sth->execute($date);
        $sth->bind_columns(\$count);
        $sth->fetch();
        $sth->finish();
    }


    if ($conf->{NO_CACHE} || $summary) {
        $response->body( irclog_output($date, $channel, $dbh, $admin_flag, $summary) );
    } else {
        my $cache_key = $channel . '|' . $date . '|' . $count;
        # the current date is different from all other pages,
        # because it doesn't have a 'next day' link, so make
        # sure that the first time it is called when it's not today
        # anymore it cannot be retrieved from the cache, but rather
        # is created anew
        if ($date eq gmt_today) {
            $cache_key .= '-TODAY';
        }
        # the average #perl6 day produces 100k to 400k of HTML, so with
        # 50MB we have about 150 pages in the cache. Since most hits are
        # the "today" page and those of the last 7 days, we still get a very
        # decent speedup
        # btw a cache hit is about 10 times faster than generating the page anew
        my $cache = new Cache::SizeAwareFileCache( {
                namespace       => 'irclog',
                max_size        => 150 * 1048576,
                } );
        # my $data = $cache->get($cache_key);
        my $data;
        if (defined $data){
            $response->body( $data );
        } else {
            $data = irclog_output($date, $channel, $dbh, $admin_flag);
            $cache->set($cache_key, $data);
            $response->body( $data );
        }
    }
    return $response->finalize;
};

# vim: sw=4 ts=4 expandtab
