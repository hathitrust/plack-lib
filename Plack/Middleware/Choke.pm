package Plack::Middleware::Choke;
use base qw( Plack::Middleware );

use Data::Dumper;
use Date::Manip;

use Plack::Util;
use Plack::Request;
use Plack::Response;

use Tie::FileLRUCache;

use Plack::Util::Accessor qw( key_prefix credit_rate max_debt cache cache_key store headers request );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    if ( ! -d "/tmp/chokedb" ) {
        mkdir("/tmp/chokedb", 0775);
    }
    
    $self->cache(Tie::FileLRUCache->new({ -cache_dir => "/tmp/chokedb", -keep_last=> 100 }));
    $self;
}

sub now {
    my $self = shift;
    return time();
}


sub client_identifier {
    my ( $self, $env ) = @_;
    my $key_prefix = $self->key_prefix;
    if ( $env->{REMOTE_USER} ) {
        return $key_prefix."_".$env->{REMOTE_USER};
    }
    else {
        return $key_prefix."_".$env->{REMOTE_ADDR};
    }
}

sub call {
    my ( $self, $env ) = @_;
    
    my $allowed = 1; my $message;
    my $request = Plack::Request->new($env);
    $self->request($request);
    
    $self->headers({});
        
    $self->cache_key($self->client_identifier($env));
    my ( $in_cache, $store ) = $self->cache->check({ -key => $self->cache_key });
    unless ( $in_cache ) {
        $store = { ts => $self->now };
    }
    $self->store($store);
    
    ( $allowed, $message ) = $self->test($env);
    
    $self->store->{ts} = $self->now;
    $self->cache->update({ -key => $self->cache_key, -value => $self->store });
    
    $self->headers->{'X-Choke-Debug'} = qq{$allowed :: $message};

    unless ( $allowed ) {
        my $response = Plack::Response->new(503);
        my $response_headers = $response->headers;
        $response->headers($self->headers);
        $response->body("THROTTLED! BURN!\n\n$message");
        return $response->finalize;
    }
        
    $env->{'psgix.choked'} = 1;

    my $res = $self->app->($env);
    $self->response_cb($res, sub {
       my $res = shift;
       if ( $res ) {

           my $h = Plack::Util::headers($res->[1]);
           foreach my $key ( keys %{ $self->headers } ) {
               $h->set( $key, $self->headers->{$key});
           }
           
           return sub {
               my $chunk = shift;
               return $self->post_process($chunk);
           }
       }
    });
    
    
    # if ( ref($res) eq 'ARRAY' ) {
    #     foreach my $key ( keys %{ $self->headers } ) {
    #         Plack::Util::header_set( $res->[1], $key, $self->headers->{$key});
    #     }
    # } else {
    #     print STDERR "RES = " . ref($res) . "\n";
    # }
    # 
    # 
    # 
    # return $res;
}

sub post_process {
    my ( $self, $chunk ) = @_;
    # NOOP
    return $chunk;
}

1;