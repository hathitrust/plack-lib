package Plack::Middleware::Choke::Requests;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;
use Plack::Request;

sub test {
    my ( $self, $env ) = @_;

    ## print STDERR Dumper($self) . "\n";
    
    my $delta = ( $self->now - $self->store->{'ts'} );
    my $allowed = 1; my $message; my $rate;
        
    my $tx_credit = 0; my $reset = 0;
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    
    unless ( $self->store->{request_debt} ) {
        $self->store->{request_debt} = 0;
    }
    
    my $request = Plack::Request->new($env);
    if ( my $reset_max_debt = $request->param('choke.' . $self->key_prefix . '.max_debt' ) ) {
        if ( $reset_max_debt != $self->store->{max_debt} ) {
            $self->store->{max_debt} = $reset_max_debt;
            $self->store->{request_debt} = 0;
            delete $self->store->{until_ts};
        }
        ( $max_debt, $max_debt_unit ) = split(/:/, $reset_max_debt);
    } elsif ( $self->{store}->{max_debt} ) {
        delete $self->{store}->{max_debt};
        $self->store->{request_debt} = 0;
        delete $self->store->{until_ts};
    }
    
    my $reset_credit_rate = $request->param('choke.' . $self->key_prefix . '.credit_rate' );
    if ( ref($self->credit_rate) || $reset_credit_rate ) {
        my ( $credit_rate, $unit ) = @{ $self->credit_rate };
        
        if ( $reset_credit_rate ) {
            ( $credit_rate, $unit ) = split(/:/, $reset_credit_rate);
            if ( $reset_credit_rate != $self->{store}->{credit_rate} ) {
                $self->store->{credit_rate} = $reset_credit_rate;
            }
        } else {
            delete $self->store->{credit_rate};
        }
        
        if ( $unit eq 'min' ) {
            $credit_rate = $credit_rate / 60.0;
        } elsif ( $unit eq 'hour' ) {
            $credit_rate = $credit_rate / 60.0 / 60.0;
        }
        $tx_credit = $credit_rate * $delta;
        if ( $self->store->{request_debt} > 0 ) {
            $self->store->{request_debt} -= $tx_credit;
            $self->store->{request_debt} = 0 if ( $self->store->{request_debt} < 0 );
        }
    }
    
    my $last_debt = $self->{store}->{request_debt};
    
    if ( $self->store->{until_ts} ) {
        if ( $self->now > $self->store->{until_ts} ) {
            # throttling is OVER!
            $self->store->{request_debt} = 0;
            delete $self->store->{until_ts};
        } else {
            $allowed = 0;
            $message = qq{STILL THROTTLED REQUESTS : } . $self->store->{until_ts};
        }
    } elsif ( $self->store->{request_debt} >= $max_debt ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->store->{until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{NEWLY THROTTLED REQUESTS};
    }
    
    $self->store->{request_debt} += 1 if ( $allowed );
    
    $self->headers->{'X-Choked-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'requests';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->store->{until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->store->{until_ts} if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-Debt'} = $last_debt; # $self->store->{request_debt};
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = $tx_credit;
    $self->headers->{'X-Choke-Key'} = $self->key_prefix;
    $self->headers->{'X-Choke-Message'} = $message;
    
    $rate = qq{$max_debt requests / $max_debt_unit};
    $rate =~ s,requests,request, if ( $max_debt == 1 );
    $rate =~ s, \+([0-9]), $1,;
    $self->headers->{'X-Choke-Rate'} = $rate;
    
    print STDERR "ER: $allowed\n";
    return ( $allowed, $message );
    
}

1;