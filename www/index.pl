#!/usr/bin/env perl
use strict;
use warnings;
use Config::File;
use HTML::Template;
use lib 'lib';
use IrcLog qw(get_dbh);
use IrcLog::WWW qw(http_header_obj);
use Plack::Response;

use Cache::FileCache;

my $conf = Config::File::read_config_file('www/www.conf');

sub get_index {

	my $dbh = get_dbh();

	my $base_url = $conf->{BASE_URL} || q{/irclog/};

	my $sth = $dbh->prepare("SELECT DISTINCT channel FROM irclog");
	$sth->execute();

	my @channels;

	while (my @row = $sth->fetchrow_array()){
		$row[0] =~ s/^\#//;
		push @channels, { channel => $row[0] };
	}

	my $template = HTML::Template->new(
			filename => 'www/template/index.tmpl',
			loop_context_vars   => 1,
			global_vars         => 1,
            die_on_bad_params   => 0,
    );
	$template->param(BASE_URL => $base_url);
	$template->param( channels => \@channels );


	return $template->output;
}

return sub {
    my $response = Plack::Response->new(200);
    $response->headers(http_header_obj);
    if ($conf->{NO_CACHE}) {
        $response->body(get_index());
        return $response->finalize;
    }

    my $cache = new Cache::FileCache( { 
            namespace 		=> 'irclog',
            } );

    my $data = $cache->get('index');
    if ( ! defined $data){
        $data = get_index();
        $cache->set('index', $data, '5 hours');
    }

    $response->body($data);
    return $response->finalize;
};
