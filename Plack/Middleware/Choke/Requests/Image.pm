package Plack::Middleware::Choke::Requests::Image;

use base qw( Plack::Middleware::Choke::Requests );

use Date::Manip;
use Data::Dumper;
use Plack::Request;

sub test {
    my ( $self, $env ) = @_;

    # these feel darn hard coded with MediaHandler information

    my $multiplier = 1.0;
    if ( $self->request->param('size') ) {
        # work with size
        my $size = int($self->request->param('size')) || 1;
        $multiplier *= ( 100 / $size );
    } elsif ( $self->request->param('width') || $self->request->param('height') ) {
        # work with height/width
        my $dim = $self->request->param('width') || $self->request->param('height');
        $dim = int($dim) || 680;
        $multiplier *= ( 680 / $dim );
    }

    $self->multiplier($multiplier * $self->multiplier);

    return $self->SUPER::test($env);
}

1;
