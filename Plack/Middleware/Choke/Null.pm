package Plack::Middleware::Choke::Null;

use base qw( Plack::Middleware::Choke );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->is_disabled(0);
    $self;
}

sub test {
    my ( $self, $env ) = @_;
    my $allowed = 1;
    my $message;
    
    return ( $allowed, $message );
    
}

1;