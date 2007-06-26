package IrcLog;
use warnings;
use strict;
use DBI;
use Config::File;
use Encode::Guess;
use Encode;
use Regexp::Common qw(URI);
use HTML::Entities;
use POSIX qw(ceil);
use Carp;
#use Regexp::MatchContext;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
        get_dbh 
        gmt_today
        my_encode
        message_line
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

# my_encode takes a string and encodes it in utf-8
sub my_encode {
    my $str = shift;
    $str =~ s/[\x02\x16]//g;
    my $enc = guess_encoding($str, qw(utf-8 latin1));
    if (ref($enc)){
        $str =  $enc->decode($str);
    } else {
        $str = decode("utf-8", $str);
    }
    return $str;
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
	return qq{<a href="http://dev.pugscode.org/changeset/$r">r$r</a>};
}

sub synopsis_links {
	my $s = shift;
	$s =~ m/^S(\d\d):(\d+)$/ or confess( 'Internal Error' );
	return qq{<a href="http://perlcabal.org/syn/S$1.html#line_$2">$&</a>};
}

sub linkify {
	my $url = shift;
	return qq{<a href="$url">} . break_words($url) . '</a>';
}

my $re_abbr;

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
        my $abbr = shift;
        return qq{<abbr title="} . encode_entities($abbrs{uc $abbr}[1], '<>&"') . qq{">} . encode_entities($abbr). qq{</abbr>};
    }
}

my %output_chain = (
        abbrs => {
            re => $re_abbr,
            match   => \&expand_abbrs,
            rest    => 'links',
        },
		links => {
			re	=> qr/$RE{URI}{HTTP}(?:#[\w_%-]+)?/,
			match	=> \&linkify,
			rest	=> 'revision_links',
		},
		revision_links => {
			re 	=> qr/\br(\d+)\b/,
			match	=> \&revision_links,
			rest	=> 'synopsis_links',
		},
		synopsis_links => {
			re	=> qr/\bS\d\d:\d+\b/,
			match	=> \&synopsis_links,
			rest	=> 'email_obfuscate',
		},
		email_obfuscate => {
			re 	=> qr/(?<=\w)\@(?=\w)/,
			match	=> '<img src="at.png">',
			rest	=> 'break_words',
		},
		break_words	=> {
			re	=> qr/\S{50,}/,
			match	=> \&break_apart,
			rest	=> 'encode',
		},
);

# does all the output processing of ordinary output lines
sub output_process {
	my $str = shift;
	return '' unless length $str;
	my $rule = shift || "abbrs";
	my $res = "";
	if ($rule eq 'encode'){
		return encode_entities($str, '<>&"');
	} else {
		my $re = $output_chain{$rule}{re};
		while ($str =~ m/$re/){
			my ($pre, $match, $post) = ($`, $&, $');
			$res .= output_process($pre, $output_chain{$rule}{rest});
			my $m = $output_chain{$rule}{match};
			if (ref $m && ref $m eq 'CODE'){
				$res .= &$m($match);
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
	my ($nick, $timestamp, $message, $line_number, $c, 
			$prev_nick, $colors, $link_url) = @_;
    my %h = (
        TIME     	=> format_time($timestamp),
        MESSAGE  	=> output_process(my_encode($message)),
		LINE_NUMBER => ++$line_number,
		LINK_URL => $link_url,
    );

    my @classes;
    
    if ($nick ne $prev_nick){
        # $c++ is used to alternate the background color
        $$c++;
        $h{NICK} = $nick;
        push @classes, 'new-nick';
    } else {
        # omit nick in successive lines from the same nick
        $h{NICK} = "";
    }
    # determine nick color:
    # perhaps do something more fancy, like count the number of lines per
    # nick, and give special colors to the $n most active nicks
NICK:    foreach (@$colors){
        my $n = quotemeta $_->[0];
        if ($nick =~ m/^$n/ or $nick =~ m/^\* $n/){
            $h{NICK_CLASS} = $_->[1];
            last NICK;
        }
    }

    if ($nick eq ""){
        # empty nick column means that nobody said anything, but 
        # it's a join, leave, topic etc.
        push @classes, "special";
        $h{SPECIAL} = 1;
    }
    if ($$c % 2){
        push @classes, "dark";
    }
    if (@classes){
        $h{CLASS} = join " ", @classes;
    }
	return \%h;
}

1;
