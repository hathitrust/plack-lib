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
    cache_key
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
    
    $self->cache_key($self->app_name . "-" . $self->key);
    $self->cache($request->env->{'psgix.cache'});
    
    # check for cookie...
    my $cookie_name = qq{CHOKE-} . (uc $self->cache_key);
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
    
    my $data = $self->cache->Get($self->client_hash, $self->cache_key);
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
        $data = { _ts => $self->now, _debug => 'NOT FOUND', _idtype => $self->client_idtype, _client_identifier => $self->client_identifier };
    } else {
        $$data{_debug} = "LOADED: " . scalar localtime;
    }

    $self->data($data);
    
    ( $allowed, $message ) = $self->test($env);
    
    $self->data->{_ts} = $self->now;

    unless ( $allowed ) {
        $self->data->{_log} = [] unless ( ref($self->data->{_log}) );
        my $is_newly_throttled = ( $self->data->{_until_ts} > $self->data->{_ts} );
        if ( $is_newly_throttled ) {

            my $previous_throttle_ts = '-';
            if ( scalar(@{ $self->data->{_log} }) > 0 ) {
                $previous_throttle_ts = Utils::Time::iso_Time('datetime', $self->data->{_log}->[-1]);
            }
            Utils::Logger::__Log_string($$env{'psgix.config'}, 
                join("|",
                    $$env{REMOTE_ADDR},
                    Utils::Time::iso_Time('datetime', $self->data->{_ts}),
                    $previous_throttle_ts,
                    $self->client_idtype,
                    $self->cache_key,
                    $self->headers->{'X-Choke'},
                    $self->headers->{'X-Choke-Debt'},
                    $self->headers->{'X-Choke-Max'},
                    $self->headers->{'X-Choke-Until'},
                ),
                "choke_logfile",
                '___QUERY___',
                'choke'
            );

            push @{ $self->data->{_log} }, $self->now;
        }
    }
    
    $self->update_cache();
    
    $self->headers->{'X-Choke-Debug'} = qq{$allowed :: $message};

    unless ( $allowed && ! $self->request->param('ping') ) {
        my $code = $allowed ? 200 : 503;
        my $response = Plack::Response->new($code);
        my $response_headers = $response->headers;
        
        # don't cache 503 messages
        $self->headers->{'Cache-Control'} = "max-age=0, no-store";

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
        
        $self->process_post_multiplier($res);
        $self->_add_headers($res);
        
        $self->post_process($res->[2]);
        return $res;
    }
    
    $self->response_cb($res, sub {
        my $res = shift;
        if ( $res ) {

            $self->process_post_multiplier($res);
            $self->_add_headers($res);

            return sub {
                my $chunk = shift;
                if ( length($chunk) ) {
                    return $self->post_process($chunk);
                } else {
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

sub update_cache {
    my ( $self ) = @_;
    $self->cache->Set($self->client_hash, $self->cache_key, $self->data, 1); # force save
}

sub process_post_multiplier {
    my ( $self, $res ) = @_;
    
    # look for X-HathiTrust-InCopyright header
    my $debt_multiplier_target = Plack::Util::header_get($res->[1], "X-HathiTrust-InCopyright");
    if ( defined($debt_multiplier_target) ) {
        my $config = $self->request->env->{'psgix.config'};
        
        # this needs to exist
        my $debt_multiplier_key = qq{choke_debt_multiplier_for_$debt_multiplier_target};
        my $debt_multiplier = $config->has($debt_multiplier_key) ? 
                              $config->get($debt_multiplier_key) : 
                              $config->get(qq{choke_debt_multiplier_for_anyone});
        print STDERR "APPLYING DEBT MULTIPLIER : $debt_multiplier\n";
        $self->apply_debt_multiplier($debt_multiplier);
    }
}

sub apply_debt_multiplier {
    my ( $self, $debt_multiplier ) = @_;
    # NOOP
}

sub _add_headers {
    my ( $self, $res ) = @_;
    my $h = Plack::Util::headers($res->[1]);
    foreach my $key ( keys %{ $self->headers } ) {
        $h->set( $key, $self->headers->{$key}) if ( $self->headers->{$key} );
    }
}

1;
