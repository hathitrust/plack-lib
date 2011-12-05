package Plack::Middleware::Choke::Bytes;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;

sub test {
    my ( $self ) = @_;

    my $delta = ( $self->now - $self->data->{'_ts'} );
    my $allowed = 1; my $message;
        
    my $tx_credit = 0; my $reset = 0;
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    $max_debt *= $self->multiplier;
    
    unless ( ref($self->data->{bytes}) ) {
        $self->data->{bytes} = { debt => 0, max_debt => join(" / ", @{ $self->max_debt} ) };
        if ( ref($self->credit_rate) ) {
            $self->data->{bytes}->{credit_rate} = join(" / ", @{ $self->credit_rate });
            if ( $self->rate_multiplier != 1 ) {
                $self->data->{bytes}->{credit_rate} .= qq{ * $self->rate_multiplier};
            }
        }
    }
    
    if ( ref($self->credit_rate) ) {
        my ( $credit_rate, $unit ) = @{ $self->credit_rate };
        $credit_rate *= $self->rate_multiplier;
        if ( $unit eq 'min' ) {
            $credit_rate = $credit_rate / 60.0;
        } elsif ( $unit eq 'hour' ) {
            $credit_rate = $credit_rate / 60.0 / 60.0;
        }
        $tx_credit = $credit_rate * $delta;
        if ( $self->data->{bytes}->{debt} > 0 ) {
            $self->data->{bytes}->{debt} -= $tx_credit;
            $self->data->{bytes}->{debt} = 0 if ( $self->data->{bytes}->{debt} < 0 );
        }
    }
    
    if ( $self->data->{_until_ts} ) {
        if ( $self->now > $self->data->{_until_ts} ) {
            # throttling is OVER!
            $self->data->{bytes}->{debt} = 0;
            delete $self->data->{_until_ts};
        } else {
            $allowed = 0;
            $message = qq{Request still throttled until : } . $self->data->{_until_ts};
        }
    } elsif ( $self->data->{bytes}->{debt} > $max_debt ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->data->{_until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{Request throttled until : } . $self->data->{_until_ts};
    }
    
    $self->headers->{'X-Choke-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'bytes';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->data->{_until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->data->{_until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->data->{_until_ts} if ( $self->data->{_until_ts} );
    $self->headers->{'X-Choke-Debt'} = $self->data->{bytes}->{debt};
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
    my $content_length = length($chunk);
    if ( $content_length ) {
        $self->data->{bytes}->{debt} += $content_length;
        $self->update_cache();
    }
    return $chunk;
}

1;
