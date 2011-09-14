package Plack::Middleware::Choke::Bytes;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;

sub test {
    my ( $self ) = @_;

    ## print STDERR Dumper($self) . "\n";
    
    my $delta = ( $self->now - $self->store->{'ts'} );
    my $allowed = 1; my $message;
        
    my $tx_credit = 0; my $reset = 0;
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    
    unless ( $self->store->{bytes_debt} ) {
        $self->store->{bytes_debt} = 0;
    }
    
    if ( ref($self->credit_rate) ) {
        my ( $credit_rate, $unit ) = @{ $self->credit_rate };
        if ( $unit eq 'min' ) {
            $credit_rate = $credit_rate / 60.0;
        }
        $tx_credit = $credit_rate * $delta;
        if ( $self->store->{bytes_debt} > 0 ) {
            $self->store->{bytes_debt} -= $tx_credit;
            $self->store->{bytes_debt} = 0 if ( $self->store->{bytes_debt} < 0 );
        }
    }
    
    if ( $self->store->{until_ts} ) {
        if ( $self->now > $self->store->{until_ts} ) {
            # throttling is OVER!
            $self->store->{bytes_debt} = 0;
            delete $self->store->{until_ts};
        } else {
            $allowed = 0;
            $message = qq{STILL THROTTLED : } . $self->store->{until_ts};
        }
    } elsif ( $self->store->{bytes_debt} > $max_debt ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->store->{until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{NEWLY THROTTLED};
    }
    
    $self->headers->{'X-Choked-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'bytes';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->store->{until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->store->{until_ts} if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-Debt'} = $self->store->{bytes_debt};
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = $tx_credit;

    $rate = qq{$max_debt bytes / $max_debt_unit};
    $rate =~ s, \+([0-9]), $1,;
    $self->headers->{'X-Choke-Rate'} = $rate;
    
    print STDERR "ER: $allowed\n";
    return ( $allowed, $message );
    
}

sub post_process {
    my ( $self, $chunk ) = @_;
    unless ( $chunk ) {
        $self->cache->update({ -key => $self->cache_key, -value => $self->store });
    } else {
        my $content_length = length($chunk);
        $self->store->{bytes_debt} += $content_length;
    }
    return $chunk;
}

1;