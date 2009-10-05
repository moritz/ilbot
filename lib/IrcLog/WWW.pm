package IrcLog::WWW;
use strict;
use warnings;
use HTTP::Headers;
use Encode qw(encode decode);
use Encode::Guess;
use Regexp::Common qw(URI);
use HTML::Entities;
use POSIX qw(ceil);
use Config::File;
use Carp qw(confess cluck);
use utf8;

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

use base 'Exporter';
our @EXPORT_OK = qw(
        http_header
        my_decode
        message_line
        my_encode
        );

use constant TAB_WIDTH => 4;
use constant NBSP => decode_entities("&nbsp;");
use constant ENTITIES => qq{<>"&};


sub http_header {
    my $config = shift || {};
    my $h = HTTP::Headers->new;
    
    $h->header(Status => '200 OK');
    $h->header(Vary => 'Accept');
    $h->header('Cache-Control' => 'no-cache') if $config->{nocache};
    
    my $accept = $ENV{HTTP_ACCEPT} || 'text/html';
    
    my %qs = (html => 1, xhtml => 0);
    
    if ($accept =~ m{ application/xhtml\+xml (; q= ([\d.]+) )? }x && !$config->{no_xhtml}) {
        $qs{xhtml} = ($2) ? $2 : 1;
    }

    if ($accept =~ m{ text/html (; q= ([\d.]+) )? }x) {
        $qs{html} = ($2) ? $2 : 1;
    }
    
    my $type = ($qs{xhtml} >= $qs{html}) ? 'application/xhtml+xml' : 'text/html';
    $h->header(
            'Content-Type'     => "$type; charset=utf-8",
            'Content-Language' => 'en',
            );
    
    return $h->as_string . "\n";
}

# my_decode takes a string and encodes it in utf-8
sub my_decode {
    my $str = shift;
    return '' if (!defined $str or $str eq qq{});

    my @encodings = qw(ascii utf-8 iso-8859-15 gb2312);
    my $encoder = guess_encoding($str, @encodings);
    if (ref $encoder){
        return $encoder->decode($str);
    } else {
        return decode("utf-8", $str);
    }

    # XXX never reached, reenable when the code below is fixed


    no utf8;
#  $str =~ s/[\x02\x16]//g;
    my @enc;
    if ($str =~ m/\A
            (?:
             [[:print:]]* [A-Za-z]+ [^[:print:]]{1,5} 
             [A-Za-z]+
             [[:print:]]*
             )+
            \z/smx 
            or $str =~ m/\A
                [[:print:]]*
                [^[:print:]]{1,5}
                [A-Za-z]+
                [[:print:]]*
                \z/smxg ) {
        @enc = qw(latin1 fr euc-cn big5-eten);
    } else {
        @enc = qw(euc-cn big5 latin1 fr);
    }
    my $saved_str = $str;
    my $utf8 = decode_by_guessing(
        $str,
        qw/ascii utf-8/, @enc,
    );
    if (! defined($utf8)) {
        warn "Warning: malformed data: \"$str\"\n";
        $str = $saved_str;
        #$str =~ s/[^[:print:]]+/?/gs;
    }     ### $str
    return $str;
}

sub decode_by_guessing {
    my $s = shift;
    my @enc = @_;
    for my $enc (@enc) {
        my $decoder = guess_encoding($s, $enc);
        if (ref $decoder) {
#            if ($enc ne 'ascii') {
#                print "line $.: $enc message found: ", $decoder->decode($s), "\n";
#            }
            return $decoder->decode($s);
        }
    }
    return;
}

# turns a timestap into a (GMT) time string
sub format_time {
    my $d = shift;
    my @times = gmtime($d);
    return sprintf("%02d:%02d", $times[2], $times[1]);
}

sub revision_links {
    my ($r, $state, $channel, $botname) = @_;
    $channel = 'parrot' if $botname =~ /^rakudo/;
    $channel = 'specs'  if $botname =~ /^speck?bot/;
    my %prefixes = (
             'perl6'    =>  'http://perlcabal.org/svn/pugs/revision/?rev=',
             'parrot'    => 'https://trac.parrot.org/parrot/changeset/',
             'bioclipse' => 'http://bioclipse.svn.sourceforge.net/viewvc/bioclipse?view=rev;revision=',
             'specs'     => 'http://www.perlcabal.org/svn/p6spec/revision?rev=',
            );
    my $url_prefix = $prefixes{$channel};
    return $r unless $url_prefix;
    $r =~ s/[^\d]//smxg;
    return qq{<a href="$url_prefix$r" title="Changeset for r$r">r$r</a>};
}

sub synopsis_links {
    my $s = shift;
    if ($s =~ m/^S(\d\d)$/i){
        return qq{<a href="http://perlcabal.org/syn/S$1.html">$s</a>};
    } elsif ($s =~ m/^S(\d\d):(\d+)(?:-\d+)?$/smi){
        return qq{<a href="http://perlcabal.org/syn/S$1.html#line_$2">$s</a>};
    } elsif ( $s =~ m{^S(\d\d)/\"([^"]+)\"$}msi ) {
        my ($syn, $anchor) = ($1, $2);
        $s = encode_entities($s, ENTITIES);
        $anchor =~ s{[^A-Za-z1-9_-]}{_}g;
        return qq{<a href="http://perlcabal.org/syn/S$syn.html#$anchor">$s</a>};
    } else {
        warn "Internal error in synopsis link handling (string: $s)";
        return encode_entities($s, ENTITIES);
    }
}

my %pdd_filenames = (
    '00' => 'pdd00_pdd',
    '01' => 'pdd01_overview',
    '03' => 'pdd03_calling_conventions',
    '04' => 'pdd04_datatypes',
    '05' => 'pdd05_opfunc',
    '06' => 'pdd06_pasm',
    '07' => 'pdd07_codingstd',
    '08' => 'pdd08_keys',
    '09' => 'pdd09_gc',
    '10' => 'pdd10_embedding',
    '11' => 'pdd11_extending',
    '13' => 'pdd13_bytecode',
    '14' => 'pdd14_bignum',
    '15' => 'pdd15_objects',
    '16' => 'pdd16_native_call',
    '17' => 'pdd17_pmc',
    '18' => 'pdd18_security',
    '19' => 'pdd19_pir',
    '20' => 'pdd20_lexical_vars',
    '21' => 'pdd21_namespaces',
    '22' => 'pdd22_io',
    '23' => 'pdd23_exceptions',
    '24' => 'pdd24_events',
    '25' => 'pdd25_concurrency',
    '26' => 'pdd26_ast',
    '27' => 'pdd27_multiple_dispatch',
    '28' => 'pdd28_strings',
    '29' => 'pdd29_compiler_tools',
    '30' => 'pdd30_install',
);

sub pdd_links {
    my $s = shift;
    $s =~ m/(\d\d)/;
    my $pdd_num = $1;
    if ($pdd_filenames{$pdd_num}){
        return qq{<a href="http://www.parrotcode.org/docs/pdd/$pdd_filenames{$pdd_num}.html">} . encode_entities($s, ENTITIES) . qq{</a>};
        # " # un-freak-out vim syntax hilighting
    } else {
        return encode_entities($s, ENTITIES); 
    }
}

sub ansi_color_codes {
    my ($str, @args) = @_;
    my @chunks = split /($color_start|$color_reset)/, $str;
    my $color;
    my $res = '';
    for (@chunks) {
        next unless length $_;
        next if /$color_reset/;
        if (/$color_start/) {
            $color = $color_codes{$_};
        } else {
            $res .=  qq{<span style="color: $color">}
                    . encode_entities($_, ENTITIES)
                    . qq{</span>};
        }
    }
    return $res;
}

sub linkify {
    my $url = shift;
    my $display_url = $url;
    if (length($display_url) >= 50){
        $display_url
            = substr( $display_url, 0, 30 )
            . '[…]'
            . substr( $display_url, -17 )
            ;
    }
    $url = encode_entities( $url, ENTITIES );
    return qq{<a href="$url" title="$url">}
           . encode_entities( $display_url, ENTITIES )
           . '</a>';
}

my $re_abbr = qr/(?!)/;

# read abbreviations from abbr.dat, store a regex in $re_abbr and create 
# a closure named expand_abbrs 
{
    my %abbrs;

    if (open(my $abbr_file, '<:utf8', 'abbr.dat')) {
        my @patterns;

        while (<$abbr_file>) {
            chomp;
            next unless length;
            next if /^#/;
            my ($pattern, $def, $key) = split(m/\s*---\s*/, $_, 3);
            next unless length $pattern && length $def;
            $key ||= $pattern;
            $abbrs{uc $key} = [ $pattern, $def ];
            push @patterns, $pattern;
        }

        close($abbr_file);

        if (@patterns){
            $re_abbr = join '|', map { "(?:$_)" } @patterns;
            $re_abbr = qr/\b(?:$re_abbr)\b/;
        }
    }
    sub expand_abbrs {
        my ($abbr, $state) = @_;
        my $abbr_n = uc $abbr;
        confess("Abbreviation '$abbr_n' not found") unless ($abbrs{$abbr_n});
        if ($state->{$abbr_n}++) { return encode_entities($abbr, ENTITIES); };
        return qq{<abbr title="} . encode_entities($abbrs{$abbr_n}[1], ENTITIES) . qq{">} . encode_entities($abbr, ENTITIES). qq{</abbr>};
    }
}

my $re_links = qr/(?!)/;

# read links.dat, store a regex to recognize them in $re_links, and create a
# closure named expand_links to do the actual linkification
# this looks like a lot of duplicated code, d'oh

{
    my %links;
    my @patterns;
    if (open(my $links_file, '<:utf8', 'links.dat')) {
        while (<$links_file>){
            chomp;
            next if m/^\s*$/smx;
            my ($key, $url) = split m/\s*---\s*/, $_, 2;
            # XXX do a quotemeta or not?
            push @patterns, quotemeta $key;
            $links{$key} = encode_entities($url, ENTITIES);
        }
        if (@patterns){
            $re_links = join '|', map { "(?:$_)" } @patterns;
            $re_links = qr/\b(?:$re_links)\b/;
        }
    }     

    sub expand_links {
        my ($key, $state) = @_;
        if ($state->{$key}++) { return encode_entities($key, ENTITIES); };
        return qq{<a href="$links{$key}">} 
             . encode_entities($key, ENTITIES) 
             . qq{</a>};
    }

}

sub rt_links {
    my ($key, $state) = @_;
    if ($key =~ m/^tt/i) {
        $key =~ m/(\d+)/;
        return qq{<a href="https://trac.parrot.org/parrot/ticket/$1">}
            . encode_entities($key, ENTITIES)
            . qq{</a> };
    } 
    $key =~ s/^#//;
    return qq{<a href="http://rt.perl.org/rt3/Ticket/Display.html?id=$key">}
            . encode_entities("#$key", ENTITIES) 
            . qq{</a>};
}

sub irc_channel_links {
    my ($key, $state) = @_;
    $key =~ s/^#//;
    return qq{<a href="/$key/today">}
            . encode_entities("#$key", ENTITIES) 
            . qq{</a>};
}

my %output_chain = (
        ansi_color_codes => {
            re      => qr{$color_start.*?(?:$color_reset|\z)}s,
            match   => \&ansi_color_codes,
            rest    => 'nonprint_clean',
        },
        nonprint_clean => {
            re      => qr/[^\x{90}\x{0A}\x{0D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]+/,
            match   => q{},
            rest    => 'links',
        },
        links => {
            # the negative lookbehind at the end ensures that 
            # trailing punctuation like http://foo.com/, is not included 
            # in the link. This means that not all valid URLs are recognized
            # in full, but that's an acceptable tradeoff
            re      => qr{$uri_regexp(?:#[\w_%:/!*+?;&=-]+)?(?<![.,])},
            match   => \&linkify,
            rest    => 'synopsis_links',
        },
        synopsis_links => {
            re      => qr{
                \bS\d\d             # S05
                (?: (?: : \d+       # S05:123
                    (?:-\d+)? )     # S05:123-456
                | /"[^"]+"          # S05/"Nothing is illegal"
                )?
                }xmsi,

            match   => \&synopsis_links,
            rest    => 'pdd_links',
        },
        pdd_links => {
            re      => qr{(?i)\bpdd(\d\d)(?:_\w+)?\b},
            match   => \&pdd_links,
            rest    => 'static_links',
        },
        static_links => {
             re     => $re_links,
             match  => \&expand_links,
             rest   => 'rt_links'
        },
        rt_links     => {
             re     => qr{(?i:\btt\s*)?#\d{2,5}\b}, 
             match  => \&rt_links,
             rest   => 'irc_channel_links',
        },
        irc_channel_links => {
            re      => qr{#(?:perl6-soc|perl6|parrot|cdk|bioclipse|parrotsketch)\b},
            match   => \&irc_channel_links,
            rest    => 'abbrs',
        },
        abbrs => {
            re      => $re_abbr,
            match   => \&expand_abbrs,
            rest    => 'revision_links',
        },
        revision_links => {
            # regex cludge: on #bioclipse the revision numbers by some
            # weird bot contain non-printable characters for formating
            # purposes
            re      => qr/\br\x{02}?[1-9]\d*\b/,
            match   => \&revision_links,
            rest    => 'email_obfuscate',
        },
        email_obfuscate => {
            re      => qr/(?<=\w)\@(?=\w)/,
            # XXX: this should really be $base_url . 'at.png'
            match   => '<img src="/at.png" alt="@" />',
            rest    => 'break_words',
        },
        break_words => {
            re      => qr/\S{50,}/,
            match   => \&break_apart,
            rest    => 'expand_tabs',
        },
        expand_tabs => {
            re          => qr/\t/,
            match       => sub { " " x TAB_WIDTH },
            rest        => 'preserve_spaces',
        },
        preserve_spaces => {
            re       => qr/  /,
            match    => sub { " " . NBSP },
            rest     => 'encode',
        },
);

# does all the output processing of ordinary output lines
sub output_process {
    my ($str, $rule, $channel, $nick) = @_;
    return qq{} unless length $str;
    my $res = "";
    if ($rule eq 'encode'){
        return encode_entities( $str, ENTITIES );
    } else {
        my $re = $output_chain{$rule}{re};
        my $state = {};
        while ($str =~ m/$re/){
            my ($pre, $match, $post) = ($`, $&, $');
            $res .= output_process($pre, $output_chain{$rule}{rest}, $channel, $nick);
            my $m = $output_chain{$rule}{match};
            if (ref $m && ref $m eq 'CODE'){
                $res .= &$m($match, $state, $channel, $nick);
            } else {
                $res .= $m;
            }
            $str = $post;
        }
        $res .= output_process($str, $output_chain{$rule}{rest}, $channel, $nick);
    }
    return $res;
}

sub break_words {
    my $str = shift;
    $str =~ s/(\S{50,})/break_apart($1)/ge;
    return $str;
}

# expects a string consisting of a single long word, and returns the same
# string with spaces after each 50 bytes at least
sub break_apart {
    my $str = shift;
    my $max_chunk_size = 50;
    my $l = length $str;
    my $chunk_size = ceil( $l / ceil($l/$max_chunk_size));

    my $result = substr $str, 0, $chunk_size;
    for (my $i = $chunk_size; $i < $l; $i += $chunk_size){
        my $delim = chr(8203);
        $result .= $delim . substr $str, $i, $chunk_size;
    }
    return encode_entities($result, ENTITIES);
}


sub message_line {
    my ($args_ref, $c) = @_;
    my $nick = $args_ref->{nick};
    my $colors = $args_ref->{colors};
    my %h = (
        ID          => $args_ref->{id},
        TIME        => format_time($args_ref->{timestamp}),
        MESSAGE     => output_process(my_decode(
                            $args_ref->{message}), 
                            "ansi_color_codes", 
                            $args_ref->{channel},
                            $args_ref->{nick},
                            ),
        LINE_NUMBER => ++$args_ref->{line_number},
    );
    $h{DATE}         = $args_ref->{date} if $args_ref->{date}; 
    $h{SEARCH_FOUND} = 'search_found' if ($args_ref->{search_found});

    my @classes;
    my @msg_classes;

    if ($nick ne $args_ref->{prev_nick}){
        # $c++ is used to alternate the background color
        $$c++;
        my $display_nick = $nick;
        $display_nick =~ s/\A\*\ /'*' . NBSP/exms;
        $h{NICK} = encode_entities($display_nick, ENTITIES);
        push @classes, 'new';
    } else {
        # omit nick in successive lines from the same nick
        $h{NICK} = "";
        push @classes, 'cont';
    }
    # determine nick color:
    # Now that we give each <tr> (with a non-special message) classes of 
    #  'nick' and "nick_$nick", this is probably better done with CSS:
    #  
    #    tr.nick_TimToady td.nick { color: green; font-weight: bold; }
    #    tr.nick_KyleHa   td.nick { color: #005500; }
    #    tr.nick_tann_    td.nick { color: #ff0077; }
    
NICK:    foreach (@$colors){
        my $n = quotemeta $_->[0];
        if ($nick =~ m/^$n/ or $nick =~ m/^\* $n/){
            $h{NICK_CLASS} = $_->[1];
            last NICK;
        }
    }

    if ($nick =~ /\A\*\ /smx) {
        push @msg_classes, 'act';
    }

    if ($nick eq ""){
        # empty nick column means that nobody said anything, but
        # it's a join, part, topic change etc.
        push @classes, "special";
                $h{SPECIAL} = 1;
    }
    else {
        # To ensure successive lines from same nick are displayed, we want
        # both these classes on every non-special <tr>
        push @classes, ( "nick", "nick_".sanitize_nick($nick) );
    }

    if ($$c % 2){
        push @classes, "dark";
    }
    if (@classes){
        $h{CLASS} = join " ", @classes;
    }
    if (@msg_classes) {
        $h{MSG_CLASS} = join " ", @msg_classes;
    }

    return \%h;
}

# encode the argument (that has to be in perl's internal string format) as
# utf-8 and remove non-SGML characters
sub my_encode {
    my $s = shift;
    $s = encode("utf-8", $s);
    # valid xml characters: http://www.w3.org/TR/REC-xml/#charsets
    $s =~ s/[^\x{90}\x{0A}\x{0D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
    return $s;
}

# Filter out characters so we can put nick into a CSS class name
sub sanitize_nick {
    my $nick = shift;
    $nick =~ s/[^-a-zA-Z0-9_]//g;
    return $nick;
}

=head1 NAME

IrcLog::WWW

=head1 SYNOPSIS

   use IrcLog::WWW qw(http_header);
   # print header
   print http_header();

=head1 METHODS

* http_header

This methods takes no argument, and returns a HTTP header. The settings are:

    Content-Type:     application/xhtml+xml if the browser accepts it, 
                      otherwise text/html
    Charset:          UTF-8
    Content-Language: en

* my_decode 

takes a single string as its argument, and tries to guess the string's 
encoding/charset, converts it into perl's internal format (which is close to 
Unicode), and returns that converted string.

* message_line

this sub takes a whole bunch of mandatory arguments (and should therefore 
be refactored).
It takes the database entries for one line of the irc log and returns 
a hash ref that is suitable to be used with the C<line.tmpl> HTML::Template 
file.

The arguments are:
    - id
    - nick
    - timestamp (in GMT)
    - message
    - line number (for the id_l1234-anchors)
    - a pointer to a counter to determine which background color to use.
    - nick of the previous line (set to "" if none)
    - a ref to an array of the form
      [ ['nick1]', 'css_class_for_nick1'],
        ['nick2], 'css_class_for_nick2'],
        ...
      ]
    - The URL of the current page

* my_encode

takes a single string as its argument (in perl's internal Unicode format),
decodes it into UTF-8, and strips all characters that may no appear in 
valid XML

=cut

# vim: sw=4 ts=4 expandtab
1;
