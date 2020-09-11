package Plack::Middleware::Choke::Debug;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;

use Plack::Request;

sub test {
    my ( $self, $env ) = @_;

    my $delta = ( $self->now - $self->data->{'ts'} );
    my $allowed = 1; my $message;

    my $request = $self->request;
    my $seq = $request->param('seq');
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    $max_debt *= $self->multiplier;

    unless ( ref($store->{bytes_debt}) ) {
        $store->{bytes_debt} = {};
    }
    
    $self->data->{bytes_debt}->{$seq} += 1 unless ( $request->param('ping') );

    if ( $self->data->{until_ts} ) {
        if ( $self->now > $self->data->{until_ts} ) {
            # throttling is OVER!
            $message = qq{THROTTLING IS OVER!};
            $self->data->{bytes_debt}->{$seq} = 0;
            delete $self->data->{until_ts};
        } else {
            $allowed = 0;
            $message = qq{STILL THROTTLED DEBUG : } . $self->data->{until_ts};
        }
    } elsif ( $self->data->{bytes_debt}->{$seq} && ! $request->param('ping') ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->data->{until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{NEWLY THROTTLED DEBUG};
    }
    
    $self->headers->{'X-Choked-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'debug';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->data->{until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->data->{until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->data->{until_ts} if ( $self->data->{until_ts} );
    $self->headers->{'X-Choke-Debt'} = $self->data->{bytes_debt}->{$seq};
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = qq{[$seq]};
    $self->headers->{'X-Choke-Ping'} = $request->param('ping');
    
    return ( $allowed, $message );
    
}

1;