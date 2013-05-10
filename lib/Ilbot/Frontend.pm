package Ilbot::Frontend;
use strict;
use warnings;
use 5.010;
use HTML::Template;

sub new {
    my ($class, %opt) = @_;
    die "Missing option 'backend" unless $opt{backend};
    return bless {backend => $opt{backend} }, $class;
}

sub config {
    my ($self, %opt) = @_;
    my $key = $opt{key};
    die "Missing option 'key'" unless $key;
    my %defaults = (
        base_url        => '/',
        activity_images => 0,
    );
    return $self->{config}{uc $key}
            // $defaults{lc $key}
            // die "No config found for '$key'";
}

sub index {
    my ($self, %opt) = @_;
    die "Missing option 'out_fh'" unless $opt{out_fh};
    my $template = HTML::Template->new(
        filename            => 'template/index.tmpl',
        loop_context_vars   => 1,
        global_vars         => 1,
        die_on_bad_params   => 0,
    );
    my @channels;
    my $has_images = 0;
    for my $channel (@{ $self->backend->channels }) {
        next unless $channel =~ s/^\#+//;
        my %data = (channel => $channel);
        if ($self->conf(key => 'activity_images')) {
            my $filename = $channel;
            $filename =~ s/[^\w-]+//g;
            $filename = "images/index/$filename.png";
            if (-e $filename) {
                $data{image_path}   = $filename;
                $has_images         = 1;
            }
        }
        push @channels, \%data;
    }

    $template->param(has_images => $has_images);
    $template->param(base_url   => $self->config(key => 'base_url'));
    $template->param(channels   => \@channels);
    $template->output(print_to => $opt{out_fh});
}
