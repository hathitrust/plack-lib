package Plack::Middleware::Choke::Requests::Image;

use base qw( Plack::Middleware::Choke::Requests );

use Date::Manip;
use Data::Dumper;
use Plack::Request;
use Plack::Util;

sub get_increment {
    my ( $self, $res ) = @_;

    my $value = 1;
    my $size = Plack::Util::header_get($res->[1], "X-HathiTrust-ImageSize");
    if ( $size && $size =~ m,(\d+)x(\d+), ) {
        my ( $width, $height ) = split(/x/, $size);
        ## my $max = ( $w > $h ) ? $w : $h;

        my $multiplier = 1.0;

        my $referer = $self->request ? $self->request->referer : '';
        unless ( $referer =~ m,^https://[^/]*\.hathitrust.org/, && $width >= 680 ) {
            $multiplier *= ( $width / 680.0 );
        }

        if ( $referer =~ m,^https://[^/]*babel\.hathitrust\.org/, && $referer =~ m,view=2up, ) {
            $multiplier *= 0.5;
        }

        $value *= $multiplier;

        # nobody needs to know this
        Plack::Util::header_remove($res->[1], 'X-HathiTrust-ImageSize');

    }    

    return $value;
}

sub label {
    return 'image';
}


1;
