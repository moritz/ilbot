#!/usr/bin/env perl
# TO BE REPLACED BY THE INSTALLER
use 5.010;
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Plack::Util qw/load_psgi/;

my $app = Plack::Util::load_psgi("$FindBin::Bin/ilbot.psgi");

use Plack::Handler::FCGI;
Plack::Handler::FCGI->new()->run($app)


# vim: ft=perl expandtab ts=4 sw=4
