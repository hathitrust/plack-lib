package Plack::Middleware::Choke::Requests::Image;

use base qw( Plack::Middleware::Choke::Requests );

use Date::Manip;
use Data::Dumper;
use Plack::Request;
use Plack::Util;

sub process_post_multiplier {
    my ( $self, $res ) = @_;

    my $size = Plack::Util::header_get($res->[1], "X-HathiTrust-ImageSize");
    if ( $size && $size =~ m,(\d+)x(\d+), ) {
        my ( $width, $height ) = split(/x/, $size);
        ## my $max = ( $w > $h ) ? $w : $h;

        my $multiplier = 1.0;
        $multiplier *= ( $width / 680.0 );

        $self->data->{requests}->{debt} *= $multiplier;
        $self->dirty(1);

        # nobody needs to know this
        $res->[1] = [ Plack::Util::header_remove($res->[1], "X-HathiTrust-ImageSize") ];

    }

    return $self->SUPER::process_post_multiplier($res);
}

sub label {
    return 'image';
}


1;
