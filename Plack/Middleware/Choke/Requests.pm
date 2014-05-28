package Plack::Middleware::Choke::Requests;

use base qw( Plack::Middleware::Choke );

use Date::Manip;
use Data::Dumper;
use Plack::Request;

sub test {
    my ( $self, $env ) = @_;

    my $delta = ( $self->now - $self->data->{'_ts'} );
    my $allowed = 1; my $message; my $rate;

    my $tx_credit = 0; my $reset = 0;
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };
    $max_debt *= $self->multiplier;

    unless ( ref($self->data->{requests}) ) {
        $self->data->{requests} = { debt => 0, max_debt => join(" / ", @{ $self->max_debt} ) };
        if ( ref($self->credit_rate) ) {
            $self->data->{requests}->{credit_rate} = join(" / ", @{ $self->credit_rate });
            if ( $self->rate_multiplier != 1 ) {
                $self->data->{requests}->{credit_rate} .= qq{ * $self->rate_multiplier};
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
        if ( $self->data->{requests}->{debt} > 0 ) {
            $self->data->{requests}->{debt} -= $tx_credit;
            $self->data->{requests}->{debt} = 0 if ( $self->data->{requests}->{debt} < 0 );
        }
    }

    my $last_debt = $self->data->{requests}->{debt};

    if ( $self->data->{_until_ts} ) {
        if ( $self->now > $self->data->{_until_ts} ) {
            # throttling is OVER!
            $self->data->{requests}->{debt} = 0;
            delete $self->data->{_until_ts};
        } else {
            $allowed = 0;
            $message = qq{Request still throttled until : } . $self->data->{_until_ts};
        }
    } elsif ( $self->data->{requests}->{debt} >= $max_debt ) {
        $allowed = 0;
        unless ( $max_debt_unit =~ m,^\+, ) {
            $max_debt_unit = qq{+ 1 $max_debt_unit};
        }
        $self->data->{_until_ts} = UnixDate($max_debt_unit, "%s");
        $message = qq{Request throttled until : } . $self->data->{_until_ts};
    }

    $self->headers->{'X-Choke-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = $self->label;
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->data->{_until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->data->{_until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->data->{_until_ts} if ( $self->data->{_until_ts} );
    $self->headers->{'X-Choke-Debt'} = $last_debt;
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = $tx_credit;
    $self->headers->{'X-Choke-Message'} = $message;
    $self->headers->{'X-Choke-Delta'} = $delta;

    $rate = qq{$max_debt requests / $max_debt_unit};
    $rate =~ s,requests,request, if ( $max_debt == 1 );
    $rate =~ s, \+([0-9]), $1,;
    $self->headers->{'X-Choke-Rate'} = $rate;

    return ( $allowed, $message );

}

sub update_debt {
    my ( $self, $res ) = @_;
    my $incr = $self->get_increment($res) * $self->debt_multiplier;
    my $last_debt = $self->data->{requests}->{debt};
    $self->data->{requests}->{debt} += $incr;
}

sub get_increment {
    my $self = shift;
    return 1;
}

sub apply_debt_multiplier {
    my ( $self, $debt_multiplier ) = @_;
    $self->data->{requests}->{debt} *= $debt_multiplier;
    $self->dirty(1);
}

sub label {
    return 'requests';
}

1;
