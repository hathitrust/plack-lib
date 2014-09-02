package Plack::Middleware::Choke::Cache::Filesystem;

use strict;
use parent qw(Plack::Middleware);

use Utils;
use Utils::Extract;
use MdpConfig;

use Plack::Util;
use Plack::Util::Accessor qw( module cache config_key name );

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    unless ( $self->module ) {
        $self->module("Utils::Cache::JSON");
    }

    unless ( $self->config_key ) {
        $self->config_key("choke_cache_dir");
    }

    unless ( $self->name ) {
        $self->config_key("psgix.cache");
    }

    $self;
}

sub call {
    my($self, $env) = @_;

    my $app_name = $$env{'psgix.app_name'};
    my $config = $$env{'psgix.config'};

    my $cache_dir = $config->get($self->config_key);
    if ( $cache_dir =~ m,___CACHE___, ) {
       $cache_dir = Utils::get_true_cache_dir($config, $self->config_key);
    }

    my $class = Plack::Util::load_class($self->module);
    $self->cache($class->new($cache_dir));

    $env->{$self->name} = $self->cache;

    my $res = $self->app->($env);

    return $res if ref $res eq 'ARRAY';

    return sub {
        my $respond = shift;

        my $writer;
        $res->(sub { return $writer = $respond->(@_) });
    }
}

1;
