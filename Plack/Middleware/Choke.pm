package Plack::Middleware::Choke;
use base qw( Plack::Middleware );

use Data::Dumper;
use Date::Manip;

use Plack::Util;
use Plack::Request;
use Plack::Response;

use Debug::DUtils;
use Utils;
use Utils::Cache::JSON;

use Digest::SHA qw(sha256_hex);

use File::Slurp;

use Plack::Util::Accessor qw( 
    app_name 
    key 
    credit_rate 
    max_debt 
    headers 
    request 
    client_identifier_sub 
    cache
    data 
    post_processed
    client_identifier 
    client_idtype 
    client_hash 
    response
    multiplier
);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    unless ( $self->response ) {
        $self->response({});
    }
    unless ( $self->response->{content_type} ) {
        $self->response->{content_type} = 'text/html';
    }
    unless ( $self->response->{filename} ) {
        if ( $self->response->{content_type} eq 'image/jpeg' ) {
            $self->response->{filename} = $ENV{SDRROOT} . "/mdp-web/graphics/503_image_distorted.jpg";
        } else {
            $self->response->{filename} = $ENV{SDRROOT} . "/mdp-web/503_error.html";
        }
    }
    
    $self->post_processed(0);
    
    $self;
}

sub now {
    my $self = shift;
    return time();
}

sub setup_client_identifier {
    my ( $self, $request ) = @_;
    my ($idtype, $client_identifier, $client_identifier_hashed);
    if ( $self->client_identifier_sub ) {
        ( $idtype, $client_identifier, $client_identifier_hashed ) = $self->client_identifier_sub->($request);
        $client_identifier_hashed = $client_identifier unless ( $client_identifier_hashed );
    }
    elsif ( $request->env->{REMOTE_USER} ) {
        # wrap it to avoid long shib identities
        $client_identifier = $request->env->{REMOTE_USER};
        $client_identifier_hashed = sha256_hex($client_identifier);
        $idtype = 'REMOTE_USER';
        $do_hash = 1;
    }
    else {
        $client_identifier_hashed = $client_identifier = $request->env->{REMOTE_ADDR};
        $client_identifier_hashed =~ s{(\d+)\.(\d+)\.(\d+)\.(\d+)}{sprintf('%03d%03d%03d%03d', $1, $2, $3, $4)}e;
        $idtype = 'REMOTE_ADDR'
    }
    $self->client_idtype($idtype);
    $self->client_identifier($client_identifier);

    $self->client_hash(join('.', $self->app_name, $client_identifier_hashed));
}

sub setup_context {
    my ( $self, $env ) = @_;

    my $request = Plack::Request->new($env);
    $self->request($request);

    unless ( $self->app_name ) {
        my $app_name = $request->env->{'psgix.app_name'};
        $self->app_name($app_name)
    }
    unless ( $self->key ) {
        $self->key($self->app_name);
    }
    $self->key($self->app_name . "-" . $self->key);
    $self->cache($request->env->{'psgix.cache'});
    
    # check for cookie...
    my $cookie_name = qq{CHOKE-} . (uc $self->key);
    if ( defined($request->cookies->{$cookie_name}) ) {
        $request->env->{CHOKE_MAX_DEBT_MULTIPLIER} = $request->cookies->{$cookie_name};
    }
    
    if ( defined($request->env->{CHOKE_MAX_DEBT_MULTIPLIER}) ) {
        $self->multiplier($request->env->{CHOKE_MAX_DEBT_MULTIPLIER});
    } else {
        $self->multiplier(1);
    }
}

sub call {
    my ( $self, $env ) = @_;
    
    my $allowed = 1; my $message;
    
    $self->headers({});
    
    $self->setup_context($env);
    $self->setup_client_identifier($self->request);
    
    my $data = $self->cache->Get($self->client_hash, $self->key);
    if ( ref($data) && $self->multiplier =~ m,:, ) {
        # check whether we need to reset here. Huzzah!
        my ( $multiplier, $timestamp ) = split(/:/, $self->multiplier);
        $self->multiplier($multiplier);
        if ( $timestamp > $$data{ts} ) {
            # timestamp is newer than this cache, so reset
            $data = undef;
        }
    }
    unless ( ref($data) ) {
        $data = { ts => $self->now, debug => 'NOT FOUND', idtype => $self->client_idtype, client_identifier => $self->client_identifier };
    } else {
        $$data{debug} = "LOADED: " . scalar localtime;
    }

    $self->data($data);
    
    ( $allowed, $message ) = $self->test($env);
    
    $self->data->{ts} = $self->now;
    $self->cache->Set($self->client_hash, $self->key, $self->data, 1); # force save
    
    $self->headers->{'X-Choke-Debug'} = qq{$allowed :: $message};

    unless ( $allowed ) {
        my $response = Plack::Response->new(503);
        my $response_headers = $response->headers;

        $self->headers->{'Content-Type'} = $self->response->{content_type};
        $response->headers($self->headers);
        
        my $content = read_file($self->response->{filename});

        my $request_url = $self->request->uri;
        $content =~ s,__REQUEST_URL__,$request_url,;
            
        my $app_name = $self->app_name;
        $content =~ s,\./,/$app_name/common-web/,g;
        
        my $choked_until;
        if ( $self->headers->{'X-Choke-UntilEpoch'} ) {
            $choked_until = $self->headers->{'X-Choke-UntilEpoch'} - time();
            my $choked_until_units = "seconds";
            if ( $choked_until > 120 ) {
                $choked_until_units = "minutes";
                $choked_until = int($choked_until / 60);
            }
            $choked_until = qq{ You may proceed in <span id="throttle-timeout">$choked_until $choked_until_units</span>.};
        }
        $content =~ s,___CHOKED_UNTIL___,$choked_until,;
        
        $content =~ s,___MESSAGE___,$message,;
        
        $response->body($content);
        return $response->finalize;
    }
        
    $env->{'psgix.choked'} = 1;

    my $res = $self->app->($env);
    
    if ( ref($res) eq 'ARRAY' ) {
        # simple, don't really want to do the callbacks...
        $self->_add_headers($res);

        $self->post_process($res->[2]);
        $self->finish_processing();
        return $res;
    }
    
    $self->response_cb($res, sub {
        my $res = shift;
        if ( $res ) {

            $self->_add_headers($res);

            return sub {
                my $chunk = shift;
                if ( length($chunk) ) {
                    return $self->post_process($chunk);
                } else {
                    print STDERR "MMM\n";
                    $self->finish_processing;
                    return;
                }
            }
        }
    });
    
}

sub post_process {
    my ( $self, $chunk ) = @_;
    # NOOP
    return $chunk;
}

sub finish_processing {
    my ( $self ) = @_;
    $self->cache->Set($self->client_hash, $self->key, $self->data, 1); # force save
    # if ( $self->post_processed ) {
    #     print STDERR "POST PROCESSING FINISHED\n";
    #     $self->cache->Set($self->client_hash, $self->key, $self->data, 1); # force save
    # }
}

sub _add_headers {
    my ( $self, $res ) = @_;
    my $h = Plack::Util::headers($res->[1]);
    foreach my $key ( keys %{ $self->headers } ) {
        $h->set( $key, $self->headers->{$key}) if ( $self->headers->{$key} );
    }
}

1;