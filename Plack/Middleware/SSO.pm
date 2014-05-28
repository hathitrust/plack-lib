package Plack::Middleware::SSO;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use URI::Escape;

use Plack::Response;

sub call {
    my($self, $env) = @_;
    
    if ( $$env{QUERY_STRING} =~ m,[?;&]signon=,i) {
        my $redirect_url;
        
        ( my $target_url = $$env{REQUEST_URI} ) =~ s,[;&]signon=([^:]+):([^;&]+),,i;
        $target_url =~ s,/cgi/,/shcgi/,; $target_url =~ s,http://,https://,;
        my ( $type, $signon_url ) = ( $$env{QUERY_STRING} =~ m,[;&]signon=([^:]+):([^;&]+),i );
        
        $signon_url = uri_escape($signon_url);
        $target_url = uri_escape($target_url);
        
        # handling of $type should be handled from an appropriate
        # subclass
        if ( $type eq 'swle' ) {
            $redirect_url = qq{https://$$env{SERVER_NAME}/Shibboleth.sso/Login?entityID=$signon_url&target=$target_url};
        }
        
        my $res = Plack::Response->new(302);
        $res->redirect($redirect_url);
        
        return $res->finalize;
        
    }
        
    my $res = $self->app->($env);

    return $res if ref $res eq 'ARRAY';

    return sub {
        my $respond = shift;

        my $writer;
        $res->(sub { return $writer = $respond->(@_) });
    }
}

1;

__END__