package Plack::Middleware::Choke::Cache::Filesystem;

use strict;
use parent qw(Plack::Middleware);

use Utils;
use Utils::Extract;
use MdpConfig;

use Plack::Util;
use Plack::Util::Accessor qw( module cache config_key );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    unless ( $self->module ) {
        $self->module("Utils::Cache::JSON");
    }
    
    unless ( $self->config_key ) {
        $self->config_key("choke_cache_dir");
    }
    
    $self;
}

sub call {
    my($self, $env) = @_;
    
    my $app_name = $$env{'psgix.app_name'};
    my $config = new MdpConfig(
                               Utils::get_uber_config_path($app_name),
                               $ENV{SDRROOT} . "/$app_name/lib/Config/global.conf",
                               $ENV{SDRROOT} . "/$app_name/lib/Config/local.conf"
                              );


    my $cache_dir = $config->get($self->config_key);
    if ( $cache_dir =~ m,___CACHE___, ) {
       $cache_dir = Utils::get_true_cache_dir($config, $self->config_key);
    }

    my $class = Plack::Util::load_class($self->module);
    $self->cache($class->new($cache_dir));
    
    $env->{'psgix.cache'} = $self->cache;
    
    my $res = $self->app->($env);
    
    return $res if ref $res eq 'ARRAY';

    return sub {
        my $respond = shift;

        my $writer;
        $res->(sub { return $writer = $respond->(@_) });
    }
}

1;