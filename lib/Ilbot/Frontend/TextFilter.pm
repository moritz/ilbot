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
    irc_color_codes => {
        re      => qr/\03\d{2}/,
        match   => '',
    },
    ansi_color_codes => {
        re      => qr{$color_start.*?(?:$color_reset|(?=$color_start)\z)}s,
        match   => \&ansi_color_codes,
    },
    nonprint_clean => {
        re      => qr/[^\x{90}\x{0A}\x{0D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+/,
        match   => '',
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
    github_links     => {
        re     => qr{(?i:\b(?:GH|pull request)\s*)#\d{2,6}\b},
        match  => \&github_links,
        chain  => 'encode_entities',
    },
    rt_links     => {
        re      => qr{(?i:\brt\s*)?#\d{2,6}\b},
        match   => \&rt_links,
        chain   => 'encode_entities',
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
        else {
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


sub github_links {
    my ($key, $state, $channel, $nick) = @_;
    if ($key =~ m/^GH/i) {
        $key =~ m/(\d+)/;
        if ($channel eq "parrot") {
            return [qq{<a href="https://github.com/parrot/parrot/issues/$1">}, $key, qq{</a>}];
        }
        elsif ($channel eq "moe") {
            return [qq{<a href="https://github.com/MoeOrganization/moe/issues/$1">}, $key, qq{</a>}];
        }
    }
    elsif ($key =~ m/^pull request #(\d+)/i) {
        if ($channel eq "moe") {
            return [qq{<a href="https://github.com/MoeOrganization/moe/pull/$1">}, $key, qq{</a>}];
        }
    }
    return $key;
}

sub rt_links {
    my $key = shift;
    $key =~ s/^#//;
    return [qq{<a href="http://rt.perl.org/rt3/Ticket/Display.html?id=$key">},
        "$key",
        qq{</a>},
    ];
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
