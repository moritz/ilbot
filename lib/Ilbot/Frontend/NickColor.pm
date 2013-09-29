package Ilbot::Frontend::NickColor;
use strict;
use warnings;
use POSIX qw/floor/;

use Exporter qw/import/;
our @EXPORT_OK = qw/nick_to_color/;
use Memoize qw/memoize/;
memoize 'nick_to_color';

sub hsv2rgb {
    my ( $h, $s, $v ) = @_;

    if ( $s == 0 ) {
        return $v, $v, $v;
    }

    $h /= 60;
    my $i = floor( $h );
    my $f = $h - $i;
    my $p = $v * ( 1 - $s );
    my $q = $v * ( 1 - $s * $f );
    my $t = $v * ( 1 - $s * ( 1 - $f ) );

    if ( $i == 0 ) {
        return $v, $t, $p;
    }
    elsif ( $i == 1 ) {
        return $q, $v, $t;
    }
    elsif ( $i == 2 ) {
        return $p, $v, $t;
    }
    elsif ( $i == 3 ) {
        return $p, $q, $v;
    }
    elsif ( $i == 4 ) {
        return $t, $p, $v;
    }
    else {
        return $v, $p, $q;
    }
}

sub nick_to_color {
    return 0 unless defined $_[0];
    my $nick = lc $_[0];
    $nick    =~ s/_+$//;
    $nick    =~ s/^\*\s+//;
    use Digest::MD5 qw/md5/;
    use Data::Dumper; $Data::Dumper::Useqq = 1;
    my ($h, $s, $v) = unpack 'SCC', md5($nick);
    # always use full saturation to avoid readability issues
    my ($r, $g, $b) = hsv2rgb($h * 360 / 2**16, 1, $v / 255 * 0.8);
    $_ = sprintf '%02x', int(255 * $_) for $r, $g, $b;
    return "#$r$g$b";
}

1;
