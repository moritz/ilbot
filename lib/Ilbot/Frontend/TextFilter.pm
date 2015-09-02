package Ilbot::Frontend::TextFilter;

use 5.010;
use strict;
use warnings;

use constant ENTITIES => qq{<>"&};
use constant TAB_WIDTH => 4;
use constant NBSP => "\xa0";

use HTML::Entities qw(encode_entities);
use Regexp::Common qw(URI);
use POSIX qw/ceil/;

use Ilbot::Config;

use Exporter qw/import/;
our @EXPORT_OK = qw/text_filter/;

my $uri_regexp = $RE{URI}{HTTP};
$uri_regexp =~ s/http/https?/g;

my %color_codes = (
   "\e[32m"     => 'green',
   "\e[34m"     => 'blue',
   "\e[31m"     => 'red',
   "\e[33m"     => 'orange',
);
my $color_reset = qr{(?:\[0m|\\x1b)+};
my $color_start = join '|', map quotemeta, keys %color_codes;

my $re_abbr  = qr/(?!)/;
my $base_url = config(www => 'base_url');

my @filter = (
    ansi_color_codes => {
        re      => qr{$color_start.*?(?:$color_reset|(?=$color_start)\z)}s,
        match   => \&ansi_color_codes,
    },
    links => {
        re      => qr{$uri_regexp(?:#[\w_%:/!*+?;&=-]+)?(?<![.,])},
        match   => \&linkify,
        chain   => 'break_words',
    },
    synopsis_links => {
        re      => qr{
            \bS\d\d             # S05
            (?: \/ \w+ )?       # S05/Foo
            (?: (?: : \d+       # S05:123
                (?:-\d+)? )     # S05:123-456
            | /"[^"]+"          # S05/"Nothing is illegal"
            )?
            }xmsi,

        match   => \&synopsis_links,
        chain   => 'encode_entities',
    },
    tracker_links => {
        re => qr{(?:\b(?:GH|pull\s*request|PR|RT)\s*)?#\d{2,8}\b}i,
        match => \&tracker_links,
        chain  => 'encode_entities',
    },
    irc_channel_links => {
        re      => qr{\#(?:perl6-soc|perl6|parrot|cdk|bioclipse|parrotsketch)\b},
        match   => \&irc_channel_links,
    },
    abbrs => {
        re      => $re_abbr,
        match   => \&expand_abbrs,
    },
    email_obfuscate => {
        re      => qr/(?<=\w)\@(?=\w)/,
        match   => sub { [qq[<img src="${base_url}s/at.png" alt="@" />], '', ''] },
    },
    break_words => {
        re      => qr/\S{50,}/,
        match   => \&break_apart,
    },
    expand_tabs => {
        re          => qr/\t/,
        match       => sub { " " x TAB_WIDTH },
    },
    preserve_spaces => {
        re       => qr/  /,
        match    => sub { " " . NBSP },
    },
    encode_entities => {
        re       => qr/.+/s,
        match    => sub { encode_entities($_[0], ENTITIES) },
    }
);

my %filter = @filter;
my $first  = $filter[0];
my %next;
for (my $i = 0; $i < @filter - 2; $i += 2) {
    $next{$filter[$i]} = $filter[$i + 2];
}

sub text_filter {
    my ($str, $opt) = @_;
    # remove IRC color codes and "forbidden" characters
    $str =~ s/\03\d{2}|[^\x{90}\x{0A}\x{0D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+//g;
    process($str, {%$opt, step => $first});
}

sub process {
    my ($str, $opt) = @_;
    my @res;
    my $step = $opt->{step};
    return $str unless $step;
    return '' if $str eq '';

    my $re = $filter{$step}{re};
    my $prev_pos = 0;
    while ($str =~ /($re)/pgc) {
        my ($pre, $match) = (${^PREMATCH}, ${^MATCH});
        $pre = substr($pre, $prev_pos);
        if (length($pre)) {
            push @res, process($pre, {%$opt, step => $next{$step} });
        }
        my $replacement = $filter{$step}{match};
        my $next = $filter{$step}{chain} // $next{$step};
        if (ref $replacement) {
            my $r = $replacement->($match, $opt);
            if (ref $r) {
                my ($pre, $middle, $post) = @$r;
                push @res, $pre;
                push @res, process($middle,
                    { %$opt, step => $next }
                );
                push @res, $post;
            }
            elsif (length($r)) {
                push @res, process($r,
                    { %$opt, step => $next }
                );
            }
        }
        elsif (length $replacement) {
            push @res, process($replacement,
                { %$opt, step => $next }
            );
        }
        $prev_pos = pos($str);
    }
    my $p = pos($str) // 0;
    if ($p < length($str)) {
        my $post = substr($str, $p);
        push @res, process($post, {%$opt, step => $next{$step} });
    }
    return join '', @res;
}

sub ansi_color_codes {
    my $str = shift;
    $str =~ s/$color_reset//g;
    if ($str =~ s/^($color_start)//) {
        my $color = $color_codes{$1};
        return [ qq{<span style="color: $color">}, $str, q{</span>} ];
    }
    return $str;
}

sub linkify {
    my $url = shift;
    $url = encode_entities( $url, ENTITIES );
    return [qq{<a href="$url" title="$url">}, $url, qq{</a>}];
}

sub synopsis_links {
    my $s = shift;
    if ($s =~ m/^S(\d\d)$/i){
        return [qq{<a href="http://perlcabal.org/syn/S$1.html">}, $s, q{</a>}];
    } elsif ($s =~ m/^S(\d\d):(\d+)(?:-\d+)?$/smi){

        return [qq{<a href="http://perlcabal.org/syn/S$1.html#line_$2">}, $s, q{</a>}];
    } elsif ($s =~ m/^S(\d\d)\/(\w+)$/smi){
        return [qq{<a href="http://perlcabal.org/syn/S$1/$2.html">}, $s, q{</a>}];
    } elsif ($s =~ m/^S(\d\d)\/(\w+):(\d+)(?:-\d+)?$/smi){
        return [qq{<a href="http://perlcabal.org/syn/S$1/$2.html#line_$3">}, $s, q{</a>}];
    } elsif ( $s =~ m{^S(\d\d)/\"([^"]+)\"$}msi ) {
        my ($syn, $anchor) = ($1, $2);
        $anchor =~ s{[^A-Za-z1-9_-]}{_}g;
        return [qq{<a href="http://perlcabal.org/syn/S$syn.html#$anchor">}, $s, q{</a>}];
    } else {
        warn "Internal error in synopsis link handling (string: $s)";
        return $s;
    }
}

sub tracker_links {
    my ($key, $opt) = @_;

    my $trac = chan_conf( $opt->{channel} => 'tracker' ) || {};
    $trac->{github} and $trac->{github} =~ s{/$}{};
    $trac->{default} ||= '';

    # If we know GitHub repo address, link anything relevant to it
    # Also link plain '#\d+' to GitHub, if GH is set as the default tracker
    if ( $key !~ /RT/i and $trac->{github}
        and ( $key =~ /GH|pull\s*request|PR/i or $trac->{default} eq 'GH' )
    ) {
        $key =~ /(\d+)/;
        # Redirecting to /issues/ on GitHub works for pull requests as well
        return [ qq{<a href="$trac->{github}/issues/$1">}, $key, qq{</a>} ];
    }

    # Link RT# tickets to RT
    # Also link plain '#\d+' to RT, if RT is set as default tracker
    if ( $key =~ /RT/i
        or ( $trac->{default} eq 'RT' and $key !~ /GH|pull\s*request|PR/i )
    ) {
        $key =~ /(\d+)/;
        return [
            qq{<a href="http://rt.perl.org/rt3/Ticket/Display.html?id=$1">},
            $key,
            qq{</a>},
        ];
    }

    return $key;
}

sub irc_channel_links {
    my ($key, $state) = @_;
    $key =~ s/^#//;
    return [qq{<a href="/$key/today">}, "#$key", q{</a>}];
}

# expects a string consisting of a single long word, and returns the same
# string with spaces after each 50 bytes at least
sub break_apart {
    my $str = shift;
    my $max_chunk_size = 50;
    my $l = length $str;
    my $chunk_size = ceil( $l / ceil($l/$max_chunk_size));

    return join chr(8203), unpack "(A$chunk_size)*", $str;
}


1;
# vim: ft=perl expandtab sw=4 ts=4
