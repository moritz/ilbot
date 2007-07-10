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
    
    if ($accept =~ m{ application/xhtml\+xml (; q= ([\d.]+) )? }x) {
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

=cut

1;
