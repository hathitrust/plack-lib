package Plack::Middleware::Choke::Bytes;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;

sub test {
    my ( $self ) = @_;

    my $delta = ( $self->now - $self->data->{'ts'} );
    my $allowed = 1; my $message;
        
    my $tx_credit = 0; my $reset = 0;
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    
    unless ( $self->data->{bytes_debt} ) {
        $self->data->{bytes_debt} = 0;
    }
    
    if ( ref($self->credit_rate) ) {
        my ( $credit_rate, $unit ) = @{ $self->credit_rate };
        if ( $unit eq 'min' ) {
            $credit_rate = $credit_rate / 60.0;
        }
        $tx_credit = $credit_rate * $delta;
        if ( $self->data->{bytes_debt} > 0 ) {
            $self->data->{bytes_debt} -= $tx_credit;
            $self->data->{bytes_debt} = 0 if ( $self->data->{bytes_debt} < 0 );
        }
    }
    
    if ( $self->data->{until_ts} ) {
        if ( $self->now > $self->data->{until_ts} ) {
            # throttling is OVER!
            $self->data->{bytes_debt} = 0;
            delete $self->data->{until_ts};
        } else {
            $allowed = 0;
            $message = qq{Request still throttled until : } . $self->data->{until_ts};
        }
    } elsif ( $self->data->{bytes_debt} > $max_debt ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->data->{until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{Request throttled until : } . $self->data->{until_ts};
    }
    
    $self->headers->{'X-Choke-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'bytes';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->data->{until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->data->{until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->data->{until_ts} if ( $self->data->{until_ts} );
    $self->headers->{'X-Choke-Debt'} = $self->data->{bytes_debt};
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = $tx_credit;
    $self->headers->{'X-Choke-Message'} = $message;
    $self->headers->{'X-Choke-Delta'} = $delta;

    $rate = qq{$max_debt bytes / $max_debt_unit};
    $rate =~ s, \+([0-9]), $1,;
    $self->headers->{'X-Choke-Rate'} = $rate;
    
    return ( $allowed, $message );
    
}

sub post_process {
    my ( $self, $chunk ) = @_;
    unless ( $chunk ) {
        $self->cache->Set($self->client_hash, $self->key, $self->data, 1); # force save
    } else {
        my $content_length = length($chunk);
        $self->data->{bytes_debt} += $content_length;
    }
    return $chunk;
}

1;