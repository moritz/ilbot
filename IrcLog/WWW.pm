package IrcLog::WWW;
use strict;
use HTTP::Headers;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(http_header);

sub http_header {
    my $h = HTTP::Headers->new;
    
    $h->header(Status => '200 OK');
    $h->header(Vary => 'Accept');
    
    my $accept = $ENV{HTTP_ACCEPT} || 'text/html';
    
    my %qs = (html => 1, xhtml => 0);
    
#    if ($accept =~ m{ application/xhtml\+xml (; q= ([\d.]+) )? }x) {
#        $qs{xhtml} = ($2) ? $2 : 1;
#    }

    if ($accept =~ m{ text/html (; q= ([\d.]+) )? }x) {
        $qs{html} = ($2) ? $2 : 1;
    }
    
    my $type = ($qs{xhtml} >= $qs{html}) ? 'application/xhtml+xml' : 'text/html';
    $h->header('Content-Type' => "$type; charset=utf-8");
    
    return $h->as_string . "\n";
}

1;
