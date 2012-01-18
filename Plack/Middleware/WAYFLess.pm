package Plack::Middleware::WAYFLess;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use URI::Escape;

use Plack::Response;

sub call {
    my($self, $env) = @_;
    
    if ( $$env{QUERY_STRING} =~ m,[?;&]auth:,i) {
        my $wayfless_url;
        
        ( my $target_url = $$env{REQUEST_URI} ) =~ s,[;&]auth:([\w]+)=([^;&]+),,i;
        $target_url =~ s,/cgi/,/shcgi/,; $target_url =~ s,http://,https://,;
        my ( $type, $idp_url ) = ( $$env{QUERY_STRING} =~ m,[;&]auth:([\w]+)=([^;&]+),i );
        
        $idp_url = uri_escape($idp_url);
        $target_url = uri_escape($target_url);
        
        my ( $type, $idp_url ) = ( $1, $2 );
        if ( $type eq 'swle' ) {
            $wayfless_url = qq{https://$$env{SERVER_NAME}/Shibboleth.sso/Login?entityID=$idp_url&target=$target_url};
        }
        
        my $res = Plack::Response->new(302);
        $res->redirect($wayfless_url);
        
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
