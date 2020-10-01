package Plack::Middleware::PopulateENV;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use Debug::DUtils;
use MdpConfig;
use Utils;

use Plack::Util::Accessor qw( 
    app_name 
);

sub call {
    my($self, $env) = @_;
    
    local %ENV = (%ENV, %{ $env });

    foreach my $key ( keys %ENV ) {
        $$env{$key} = $ENV{$key} unless ( defined $$env{$key} );
    }

    my $app_name = $self->app_name;
    $$env{'psgix.app_name'} = $app_name;
    
    my $config = new MdpConfig(
                               Utils::get_uber_config_path($app_name),
                               $ENV{SDRROOT} . "/$app_name/lib/Config/global.conf",
                               $ENV{SDRROOT} . "/$app_name/lib/Config/local.conf"
                              );
    
    $$env{'psgix.config'} = $config;
    
    my $res = $self->app->($env);
    return $res;

}

1;

__END__
