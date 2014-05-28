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
        $multiplier *= ( $width / 680.0 );

        $value *= $multiplier;

        # nobody needs to know this
        $res->[1] = [ Plack::Util::header_remove($res->[1], "X-HathiTrust-ImageSize") ];

    }    

    return $value;
}

sub label {
    return 'image';
}


1;
