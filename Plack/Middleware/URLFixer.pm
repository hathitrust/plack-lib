package Plack::Middleware::URLFixer;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use URI::Escape;

use Plack::Response;

sub call {
    my($self, $env) = @_;
    
    if ( $$env{REQUEST_URI} =~ m,%3B[^%]?|%3D[^%],i) {
        my $redirect_url;

        my $redirect_url = $$env{REQUEST_URI};
        $redirect_url = uri_unescape($redirect_url);
        $redirect_url = ( ( $$env{SERVER_PORT} eq '443' ) ? 'https://' : 'http://' ) . $$env{SERVER_NAME} . $redirect_url;

        print STDERR "REDIRECT: $redirect_url\n";

        my $res = Plack::Response->new(302);
        $res->redirect($redirect_url);
        
        return $res->finalize;
        
    }
        
    return $self->app->($env);
}

1;

__END__
