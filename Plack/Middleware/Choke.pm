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
    client_identifier 
    client_idtype 
    client_hash 
    response
    multiplier
    rate_multiplier
    debt_multiplier
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

    $self->headers({});
    
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
    
    if ( defined($request->env->{CHOKE_MAX_DEBT_MULTIPLIER}) ) {
        $self->multiplier($request->env->{CHOKE_MAX_DEBT_MULTIPLIER});
    } else {
        $self->multiplier(1);
    }

    if ( defined($request->env->{CHOKE_RATE_MULTIPLIER}) ) {
        $self->rate_multiplier($request->env->{CHOKE_RATE_MULTIPLIER});
    } else {
        $self->rate_multiplier(1);
    }
}

sub call {
    my ( $self, $env ) = @_;
    
    my $allowed = 1; my $message;
    
    $self->setup_context($env);
    $self->setup_client_identifier($self->request);
    
    my $data = $self->cache->Get($self->client_hash, $self->cache_key);
    unless ( ref($data) ) {
        $data = { _ts => $self->now, _debug => 'NOT FOUND', _idtype => $self->client_idtype, _client_identifier => $self->client_identifier };
    } else {
        $$data{_debug} = "LOADED: " . scalar localtime;
    }

    $self->data($data);
    
    ( $allowed, $message ) = $self->test($env);
    
    # update timestamp
    $self->data->{_ts} = $self->now;

    unless ( $allowed ) {
        $self->log_test_failure();
    } else {
        # clear this if $allowed
        delete $self->data->{_stamp_ts};
    }
    
    $self->update_cache();
    
    unless ( $allowed && ! $self->request->param('ping') ) {
        return $self->intercept_response($allowed);
    }
    
    # avoid further processing by default choke policies
    $env->{'psgix.choked'} = 1;

    my $res = $self->app->($env);

    # now update debt
    $self->process_post_multiplier($res);
    $self->update_debt($res);
    $self->update_cache();
    
    if ( ref($res) eq 'ARRAY' ) {
        # the response_cb callback approach automatically 
        # chucks the content-length header; avoid if possible
        
        $self->_add_headers($res);
        
        $self->post_process($res->[2]);
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
                    return;
                }
            }
        }
    });
    
}

sub intercept_response {
    my ( $self, $allowed ) = @_;
    
    # the middleware can be "pinged" to check the status
    # of the request; these need to return a status of 200

    # TODO: probably should return something other than the 
    # error documents.
    
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

sub post_process {
    my ( $self, $chunk ) = @_;
    # NOOP
    return $chunk;
}

sub update_cache {
    my ( $self ) = @_;
    $self->cache->Set($self->client_hash, $self->cache_key, $self->data, 1); # force save
}

sub update_debt {
    my ( $self ) = @_;
    # NOOP
}

sub process_post_multiplier {
    my ( $self, $res ) = @_;
    
    # look for X-HathiTrust-InCopyright header
    # format: X-HathiTrust-InCopyright: user=staff,superuser
    # assumes that any non-authorized access to copyright material
    # is handled by the wrapped app

    $self->debt_multiplier(1);

    my $in_copyright_header = Plack::Util::header_get($res->[1], "X-HathiTrust-InCopyright");
    if ( defined($in_copyright_header) ) {
        my $config = $self->request->env->{'psgix.config'};
        
        my $debt_multiplier = $config->get(qq{choke_debt_multiplier_for_anyone});
        my @roles = ();
        my @tmp = split(/,/, (split(/;/, $in_copyright_header))[0]);
        $tmp[0] =~ s,user=,,;
        push @roles, join('_', @tmp) if ( scalar @tmp > 1 );
        push @roles, $tmp[0];
        
        foreach my $role ( @roles ) {
            my $debt_multiplier_key = qq{choke_debt_multiplier_for_$role};
            if ( $config->has($debt_multiplier_key) ) {
                $debt_multiplier = $config->get($debt_multiplier_key);
                last;
            }
        }
        $self->debt_multiplier($debt_multiplier);
    }
}

sub dirty {
    my $self = shift;
    my ( $flag ) = @_;
    if ( $flag ) {
        $$self{dirty} = $flag;
    }
    return $$self{dirty};
}

sub apply_debt_multiplier {
    my ( $self, $debt_multiplier ) = @_;
    # NOOP
}

sub label {
    return 'default';
}

sub log_test_failure {
    my ( $self ) = @_;
    $self->data->{_log} = [] unless ( ref($self->data->{_log}) );
    my $is_newly_throttled = ! exists($self->data->{_stamp_ts});
    if ( $is_newly_throttled ) {
        $self->data->{_stamp_ts} = $self->data->{_ts};
        my $previous_throttle_ts = '-';
        if ( scalar(@{ $self->data->{_log} }) > 0 ) {
            $previous_throttle_ts = Utils::Time::iso_Time('datetime', $self->data->{_log}->[-1]);
        }
        Utils::Logger::__Log_string($self->request->env->{'psgix.config'}, 
            join("|",
                $self->request->env->{REMOTE_ADDR},
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

sub _add_headers {
    my ( $self, $res ) = @_;
    my $h = Plack::Util::headers($res->[1]);
    foreach my $key ( keys %{ $self->headers } ) {
        $h->set( $key, $self->headers->{$key}) if ( $self->headers->{$key} );
    }
}

1;
