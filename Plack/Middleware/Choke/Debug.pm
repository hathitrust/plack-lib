package Plack::Middleware::Choke::Debug;

use base qw( Plack::Middleware::Choke );
use Date::Manip;
use Data::Dumper;

use Plack::Request;

sub test {
    my ( $self, $env ) = @_;

    ## print STDERR Dumper($self) . "\n";
    
    my $delta = ( $self->now - $self->store->{'ts'} );
    my $allowed = 1; my $message;

    my $request = $self->request;
    my $seq = $request->param('seq');
    my ( $max_debt, $max_debt_unit ) = @{ $self->max_debt };

    if ( $seq % 6 == 0 ) {
        
        unless ( ref($store->{bytes_debt}) ) {
            $store->{bytes_debt} = {};
        }
        
        $self->store->{bytes_debt}->{$seq} += 1 unless ( $request->param('ping') );

        if ( $self->store->{until_ts} ) {
            if ( $self->now > $self->store->{until_ts} && ! $request->param('ping') ) {
                # throttling is OVER!
                $self->store->{bytes_debt}->{$seq} = 0;
                delete $self->store->{until_ts};
            } else {
                $allowed = 0;
                $message = qq{STILL THROTTLED DEBUG : } . $self->store->{until_ts};
            }
        } elsif ( $self->store->{bytes_debt}->{$seq} == 1 ) {
            $allowed = 0;
            unless ( $max_debt_unit =~ m,^\+, ) {
                $max_debt_unit = qq{+ 1 $max_debt_unit};
            }
            $self->store->{until_ts} = UnixDate($max_debt_unit, "%s");
            $message = qq{NEWLY THROTTLED DEBUG};
        }

    }
    
    
    $self->headers->{'X-Choked-Allowed'} = $allowed;
    $self->headers->{'X-Choke'} = 'debug';
    $self->headers->{'X-Choke-Now'} = UnixDate("epoch " . $self->now, "%Y-%m-%d %H:%M:%S");
    $self->headers->{'X-Choke-Until'} = UnixDate("epoch " . $self->store->{until_ts}, "%Y-%m-%d %H:%M:%S") if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-UntilEpoch'} = $self->store->{until_ts} if ( $self->store->{until_ts} );
    $self->headers->{'X-Choke-Debt'} = $self->store->{bytes_debt}->{$seq};
    $self->headers->{'X-Choke-Max'} = $max_debt;
    $self->headers->{'X-Choke-Credit'} = $seq;
    $self->headers->{'X-Choke-Ping'} = $request->param('ping');
    
    
    print STDERR "ER: $allowed\n";
    return ( $allowed, $message );
    
}

# sub post_process {
#     my ( $self, $headers, $res ) = @_;
#     my $content_length = Plack::Util::header_get( $res->[1], 'Content-length');
#     print STDERR "POST: $content_length\n";
#     $self->store->{bytes_debt} += $content_length;
#     $headers{'X-BytesLimit-Debt'} = $self->store->{bytes_debt};
#     $self->cache->update({ -key => $self->cache_key, -value => $self->store });
# }

1;