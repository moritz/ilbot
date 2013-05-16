package IrcLog::WWW;
use strict;
use warnings;
use Encode qw(encode decode);
use Encode::Guess;
use HTML::Entities;
use POSIX qw(ceil);
use Config::File;
use Carp qw(confess cluck);
use Ilbot::Config qw/config/;
use utf8;

use base 'Exporter';
our @EXPORT_OK = qw(
        my_decode
        message_line
        my_encode
        );

use constant NBSP => decode_entities("&nbsp;");
use constant ENTITIES => qq{<>"&};



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

# turns a timestap into a (GMT) or LOCAL time string
sub format_time {
    my $d = shift;
	my $timezone = config(backend => 'timezone') || 'gmt';

    my @times;

    if($timezone eq 'gmt') { @times = gmtime($d); }
    elsif($timezone eq 'local') { @times = localtime($d); }

    return sprintf("%02d:%02d", $times[2], $times[1]);
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

sub message_line {
    my ($args_ref, $c) = @_;
    my $nick = $args_ref->{nick};
    my %h = (
        ID          => $args_ref->{id},
        TIME        => format_time($args_ref->{timestamp}),
        MESSAGE     => output_process(my_decode(
                            $args_ref->{message}), 
                            "irc_color_codes",
                            $args_ref->{channel},
                            $args_ref->{nick},
                            ),
        LINE_NUMBER => ++$args_ref->{line_number},
        IN_SUMMARY  => $args_ref->{in_summary},
    );
    $h{DATE}         = $args_ref->{date} if $args_ref->{date}; 
    $h{SEARCH_FOUND} = 'search_found' if ($args_ref->{search_found});

    my @classes;
    my @msg_classes;
    my $display_nick = $nick;
    $display_nick =~ s/\A\*\ /'*' . NBSP/exms;
    $h{NICK} = encode_entities($display_nick, ENTITIES);
    if ($nick ne $args_ref->{prev_nick}){
        # $c++ is used to alternate the background color
        $$c++;
        push @classes, 'new';
    } else {
        # omit nick in successive lines from the same nick
        push @classes, 'cont';
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
    $h{NICK_COLOR} = $args_ref->{color};

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
