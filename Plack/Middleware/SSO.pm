package Plack::Middleware::SSO;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use URI::Escape;

use Plack::Response;

sub call {
    my($self, $env) = @_;

    if ( $$env{QUERY_STRING} =~ m,(?:^|[;&])signon=,i) {
        my $redirect_url;
        my $is_cosign_active = ( defined $ENV{HT_IS_COSIGN_STILL_HERE} && $ENV{HT_IS_COSIGN_STILL_HERE} eq 'yes' );
        
        ( my $target_url = $$env{REQUEST_URI} ) =~ s,[\?;&]signon=([^:]+):([^;&]+),,i;
        $target_url =~ s,/cgi/,/shcgi/, if ( $is_cosign_active );
        $target_url =~ s,http://,https://,;
        my ( $type, $signon_url ) = ( $$env{QUERY_STRING} =~ m,(?:^|[;&])signon=([^:]+):([^;&]+),i );

        if ( $$env{REMOTE_USER} && ( $$env{Shib_Identity_Provider} eq $signon_url || $signon_url eq 'wayf' ) ) {
            # we don't need to redirect
            $$env{REQUEST_URI} = $target_url;
            $$env{QUERY_STRING} =~ s,(?:^|[;&])signon=([^:]+):([^;&]+),,i;
        } else {

            $signon_url = uri_escape($signon_url);
            $target_url = uri_escape($target_url);
            
            # handling of $type should be handled from an appropriate
            # subclass
            if ( $signon_url eq 'wayf' ) {
                $redirect_url = qq{https://$$env{SERVER_NAME}/cgi/wayf?target=$target_url};
            }
            elsif ( $type eq 'swle' ) {
                ### RRE - this will be removed when HathiTrust only uses Shibboleth
                if ( $signon_url eq uri_escape('https://shibboleth.umich.edu/idp/shibboleth') && $is_cosign_active ) {
                    $target_url = uri_unescape($target_url);
                    $target_url =~ s,/shcgi/,/cgi/,;
                    $target_url = qq{https://$$env{SERVER_NAME}} . $target_url;
                    if ( $$env{REMOTE_USER} ) {
                        $redirect_url = $target_url;
                    } else {
                        $redirect_url = qq{https://weblogin.umich.edu/?cosign-$$env{HTTP_HOST}&$target_url};
                    }
                } else {
                    $redirect_url = qq{https://$$env{SERVER_NAME}/Shibboleth.sso/Login?entityID=$signon_url&target=$target_url};
                }
            }

            my $res = Plack::Response->new(302);
            $res->redirect($redirect_url);
            
            return $res->finalize;
            
        }

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
