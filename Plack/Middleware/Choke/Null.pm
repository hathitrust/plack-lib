package Plack::Middleware::Choke::Null;

use base qw( Plack::Middleware::Choke );

sub test {
    my ( $self ) = @_;
    my $allowed = 1;
    my $message;
    
    return ( $allowed, $message );
    
}

1;