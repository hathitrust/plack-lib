package Plack::Middleware::Choke::Requests::Indexer;

use base qw( Plack::Middleware::Choke::Requests );

use Date::Manip;
use Data::Dumper;
use Plack::Request;

$INDEXING_DELTA = 60;

sub test {
    my ( $self, $env ) = @_;
    
    my $last_debt = $self->data->{requests}->{debt};
    my $last_ts = $self->data->{_ts};
    
    if ( $self->now - $last_ts >= $INDEXING_DELTA ) {
        $self->data->{requests}->{debt} = 0;
    }

    return $self->SUPER::test($env);
}

1;
