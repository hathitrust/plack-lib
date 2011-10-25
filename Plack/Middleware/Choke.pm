package Plack::Middleware::Choke;
use base qw( Plack::Middleware );

use Data::Dumper;
use Date::Manip;

use Plack::Util;
use Plack::Request;
use Plack::Response;

use Context;
use MdpConfig;
use Debug::DUtils;
use Utils;
use Utils::Cache::JSON;

use Digest::SHA qw(sha256_hex);

use File::Slurp;

use Plack::Util::Accessor qw( app_name key credit_rate max_debt cache cache_key headers request config context client_identifier_sub data client_identifier client_idtype client_hash response cache_dir_key );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    # get configuration
    my $app_name = Debug::DUtils::___determine_app(); # $self->app_name;
    my $config = new MdpConfig(
                               Utils::get_uber_config_path($app_name),
                               $ENV{SDRROOT} . "/$app_name/lib/Config/global.conf",
                               $ENV{SDRROOT} . "/$app_name/lib/Config/local.conf"
                              );
        

    my $C = new Context;
    $C->set_object('MdpConfig', $config);
    $self->context($C);
    
    $self->setup_cache();
    
    unless ( $self->key ) {
        $self->key($self->app_name);
    } else {
        $self->key($self->app_name . "-" . $self->key);
    }
    
    unless ( $self->response ) {
        $self->response({});
    }
    unless ( $self->response->{content_type} ) {
        $self->response->{content_type} = 'text/html';
    }
    unless ( $self->response->{filename} ) {
        if ( $self->response->{content_type} eq 'image/jpeg' ) {
            $self->response->{filename} = $ENV{SDRROOT} . "/mdp-web/graphics/503_image.jpg";
        } else {
            $self->response->{filename} = $ENV{SDRROOT} . "/mdp-web/503_error.html";
        }
    }
    
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

sub setup_cache {
    my ( $self ) = @_;
    my $cache_dir_key = $self->cache_dir_key || "choke_cache_dir";

    my $cache_dir = $self->context->get_object('MdpConfig')->get($cache_dir_key); 
    if ( $cache_dir =~ m,___RAM___, ) {
        my $ramdir = Utils::Extract::__get_root();
        $cache_dir =~ s,/___RAM___,$ramdir,;
        $cache_dir .= "/";
    } else {
       $cache_dir = Utils::get_true_cache_dir($self->context, $cache_dir_key) . "/"; 
    }
    print STDERR "CHOKE: $cache_dir\n";
    $self->cache(Utils::Cache::JSON->new($cache_dir));
}

sub call {
    my ( $self, $env ) = @_;
    
    my $allowed = 1; my $message;
    my $request = Plack::Request->new($env);
    $self->request($request);
    
    $self->headers({});
    
    $self->setup_client_identifier($request);
    
    my $data = $self->cache->Get($self->client_hash, $self->key);
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
    $self->response_cb($res, sub {
       my $res = shift;
       if ( $res ) {

           my $h = Plack::Util::headers($res->[1]);
           foreach my $key ( keys %{ $self->headers } ) {
               $h->set( $key, $self->headers->{$key}) if ( $self->headers->{$key} );
           }
           
           return sub {
               my $chunk = shift;
               return $self->post_process($chunk);
           }
       }
    });
    
}

sub post_process {
    my ( $self, $chunk ) = @_;
    # NOOP
    return $chunk;
}

1;