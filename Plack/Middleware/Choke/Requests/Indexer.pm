package Plack::Middleware::Choke::Requests::Indexer;

use base qw( Plack::Middleware::Choke::Requests );

use Date::Manip;
use Data::Dumper;
use Plack::Request;

$INDEXING_DELTA = 60;

sub test {
    my ( $self, $env ) = @_;

    # only lock the book for 30 seconds
    # the standard test doesn't decay quickly 
    # enough --- indexing needs to say "up to 1 request within 30 seconds"
    # and then assume indexing failed / is needed
    
    my $last_debt = $self->data->{requests}->{debt};
    my $last_ts = $self->data->{_ts};
    
    if ( $self->now - $last_ts >= $INDEXING_DELTA ) {
        # print STDERR "INDEXER : clearing debt\n";
        $self->data->{requests}->{debt} = 0;
    } else {
        # print STDERR "INDEXER : using debt\n";
    }

    return $self->SUPER::test($env);
}

1;
