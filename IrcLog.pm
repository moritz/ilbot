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

# does all the output processing of ordinary output lines
sub output_process {
	my $str = shift;
	return linkify($str);

}

# expects a string consisting of a single long word, and returns the same
# string with spaces after each 50 bytes at least
sub break_apart {
    my $str = shift;
    my $max_chunk_size = shift || 50;
    my $l = length $str;
    my $chunk_size = ceil( $l / ceil($l/$max_chunk_size));

    my $result = substr $str, 0, $chunk_size;
    for (my $i = $chunk_size; $i < $l; $i += $chunk_size){
        $result .= " " . substr $str, $i, $chunk_size;
    }
    return $result;
}

# takes a valid UTF-8 string, turns URLs into links, and encodes unsafe
# characters
# nb there is no need to encode characters with high bits (encode_entities
# does that by default, but we're using utf-8 as output, so who cares...)
sub linkify {
    my $str = shift;
    my $result = "";
    while ($str =~ m/$RE{URI}{HTTP}(?:#[\w-]+)?/){
        my $linktext = $&;
        $linktext =~ s/(\S{60,})/ break_apart($1, 60) /eg;
        $result .= revision_linkify($`);
        $result .= qq{<a href="$&">} . encode_entities($linktext, '<>&"') . '</a>';
        $str = $';
    }
    return $result . revision_linkify($str);
}

#turns r\d+ into a link to the appropriate changeset.
# this is #perl6-specific and therefore not very nice
sub revision_linkify {
    my $str = shift;
    my $result = "";
    while ($str =~ m/ r(\d+)\b/){
        $result .= synopsis_linkify($`);
        $result .= qq{ <a href="http://dev.pugscode.org/changeset/$1">$&</a>};
        $str = $';
    }
    return $result . synopsis_linkify($str);

}

sub synopsis_linkify {
	my $str = shift;
	my $result = "";
	while ($str =~ m/\bS(\d\d):(\d+)\b/) {
		$result .= email_obfuscate($`);
		$result .= qq{<a href="http://perlcabal.org/syn/S$1.html#_line_$2">$&</a>};
        $str = $';
	}
    return $result . email_obfuscate($str);


}

sub email_obfuscate {
	my $str = shift;
	$str =~ s/(\S{60,})/ break_apart($1, 60) /eg;
	$str = encode_entities($str, '<>&');
	$str =~  s/(?<=\w)\@(?=\w)/<img src="at.png">/g;
	return $str;
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
    if ($nick ne $prev_nick){
        # $c++ is used to alternate the background color
        $$c++;
        $h{NICK} = $nick;
    } else {
        # omit nick in successive lines from the same nick
        $h{NICK} = "";
    }

    my @classes;
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
