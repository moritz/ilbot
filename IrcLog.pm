use warnings;
use strict;

package IrcLog;

#use Smart::Comments;
use DBI;
use Config::File;
use Encode::Guess;
use Encode qw(encode decode);
use Regexp::Common qw(URI);
use HTML::Entities;
use POSIX qw(ceil);
use Carp;
use utf8;
use Data::Dumper;
#use Regexp::MatchContext;

use constant TAB_WIDTH => 4;
use constant NBSP => decode_entities("&nbsp;");
use constant ENTITIES => qr{<>"&};

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
        get_dbh
        gmt_today
        my_decode
        message_line
        my_encode
        );


# get a database handle.
# you will have to modify that routine to fit your needs
sub get_dbh() {
    my $conf = Config::File::read_config_file("database.conf");
    my $dbs = $conf->{DSN} || "mysql";
    my $db_name = $conf->{DATABASE} || "irclog";
    my $host = $conf->{HOST} || "localhost";
    my $user = $conf->{USER} || "irclog";
    my $passwd = $conf->{PASSWORD} || "";

    my $db_dsn = "DBI:$dbs:database=$db_name;host=$host";
    my $dbh = DBI->connect($db_dsn, $user, $passwd,
            {RaiseError=>1, AutoCommit => 1});
    return $dbh;
}

# returns current date in GMT in the form YYYY-MM-DD
sub gmt_today {
    my @d = gmtime(time);
    return sprintf("%04d-%02d-%02d", $d[5]+1900, $d[4] + 1, $d[3]);
}

# my_decode takes a string and encodes it in utf-8
sub my_decode {
    my $str = shift;

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
    if ($str =~ /^(?:[[:print:]]*[A-Za-z]+[^[:print:]]{1,5}[A-Za-z]+[[:print:]]*)+$/ or
        $str =~ /^[[:print:]]*[^[:print:]]{1,5}[A-Za-z]+[[:print:]]*$/ ) {
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
            if ($enc ne 'ascii') {
                #print "line $.: $enc message found: ", $decoder->decode($s), "\n";
            }
            return $decoder->decode($s);
        }
    }
    undef;
}

# turns a timestap into a (GMT) time string
sub format_time {
    my $d = shift;
    my @times = gmtime($d);
    return sprintf("%02d:%02d", $times[2], $times[1]);
}

sub revision_links {
    my $r = shift;
    $r =~ s/^r//;
    return qq{<a href="http://dev.pugscode.org/changeset/$r" title="Changeset for r$r">r$r</a>};
}

sub synopsis_links {
    my $s = shift;
    $s =~ m/^S(\d\d):(\d+)(?:-\d+)?$/ or confess( 'Internal Error' );
    return qq{<a href="http://perlcabal.org/syn/S$1.html#line_$2">$&</a>};
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

my $re_abbr;

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

        $re_abbr = join '|', map { "(?:$_)" } @patterns;
        $re_abbr = qr/\b(?:$re_abbr)\b/;
    }

    sub expand_abbrs {
        my ($abbr, $state) = @_;
        my $abbr_n = uc $abbr;
        if ($state->{$abbr_n}++) { return encode_entities($abbr, ENTITIES); };
        return qq{<abbr title="} . encode_entities($abbrs{$abbr_n}[1], ENTITIES) . qq{">} . encode_entities($abbr, ENTITIES). qq{</abbr>};
    }
}

my $re_links;

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
        $re_links = join '|', map { "(?:$_)" } @patterns;
        $re_links = qr/\b(?:$re_links)\b/;
	}
    sub expand_links {
        my ($key, $state) = @_;
        if ($state->{$key}++) { return encode_entities($key, ENTITIES); };
        return qq{<a href="$links{$key}">} 
			   . encode_entities($key, ENTITIES) 
			   . qq{</a>};
    }

}

my %output_chain = (
        links => {
            re      => qr/$RE{URI}{HTTP}(?:#[\w_%:-]+)?/,
            match   => \&linkify,
            rest    => 'synopsis_links',
        },
        synopsis_links => {
            re      => qr/\bS\d\d:\d+(?:-\d+)?\b/,
            match   => \&synopsis_links,
            rest    => 'static_links',
        },
        static_links => {
             re     => $re_links,
             match  => \&expand_links,
             rest   => 'abbrs'
        },
        abbrs => {
            re => $re_abbr,
            match   => \&expand_abbrs,
            rest    => 'revision_links',
        },
        revision_links => {
            re      => qr/\br(\d+)\b/,
            match   => \&revision_links,
            rest    => 'email_obfuscate',
        },
        email_obfuscate => {
            re      => qr/(?<=\w)\@(?=\w)/,
            match   => '<img src="at.png" alt="@" />',
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
    my $str = shift;
    return '' unless length $str;
    my $rule = shift || "links";
    my $res = "";
    if ($rule eq 'encode'){
        return encode_entities( $str, ENTITIES );
    } else {
        my $re = $output_chain{$rule}{re};
        my $state = {};
        while ($str =~ m/$re/){
            my ($pre, $match, $post) = ($`, $&, $');
            $res .= output_process($pre, $output_chain{$rule}{rest});
            my $m = $output_chain{$rule}{match};
            if (ref $m && ref $m eq 'CODE'){
                $res .= &$m($match, $state);
            } else {
                $res .= $m;
            }
            $str = $post;
        }
        $res .= output_process($str, $output_chain{$rule}{rest});
    }
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
        $result .= " " . substr $str, $i, $chunk_size;
    }
    return $result;
}


sub message_line {
    my ($id, $nick, $timestamp, $message, $line_number, $c,
            $prev_nick, $colors, $link_url) = @_;
    my %h = (
        ID          => $id,
        TIME        => format_time($timestamp),
        MESSAGE     => output_process(my_decode($message)),
        LINE_NUMBER => ++$line_number,
        LINK_URL    => $link_url,
    );

    my @classes;
    my @msg_classes;

    if ($nick ne $prev_nick){
        # $c++ is used to alternate the background color
        $$c++;
        $h{NICK} = $nick;
        push @classes, 'new';
    } else {
        # omit nick in successive lines from the same nick
        $h{NICK} = "";
        push @classes, 'cont';
    }
    # determine nick color:
NICK:    foreach (@$colors){
        my $n = quotemeta $_->[0];
        if ($nick =~ m/^$n/ or $nick =~ m/^\* $n/){
            $h{NICK_CLASS} = $_->[1];
            last NICK;
        }
    }

    if ($nick =~ /^\* /) {
        push @msg_classes, 'act';
    }

    if ($nick eq ""){
        # empty nick column means that nobody said anything, but
        # it's a join, part, topic change etc.
        push @classes, "special";
        $h{SPECIAL} = 1;
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

=head1 NAME

IrcLog - common subroutines for ilbot

=head1 SYNOPSIS

there is no synopsis, since the module has no unified API, but is a loose 
collection of subs that are usefull for the irc log bot and the 
corresponding CGI scripts.

=head1 METHODS

* get_dbh

returns a DBI handle to a database. To achieve that, it reads the file 
C<database.conf>.

* gmt_today

returns the current date in the format YYYY-MM-DD, and uses UTC (GMT) to 
dermine the date.

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
      [ ['nick1', 'css_class_for_nick1'],
        ['nick2], 'css_class_for_nick2'],
        ...
      ]
    - The URL of the current page

* my_encode

takes a single string as its argument (in perl's internal Unicode format),
decodes it into UTF-8, and strips all characters that may no appear in 
valid XML

=cut

1;
