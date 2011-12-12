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
    
    my $app_name = $self->app_name;
    $$env{'psgix.app_name'} = $app_name;
    
    my $config = new MdpConfig(
                               Utils::get_uber_config_path($app_name),
                               $ENV{SDRROOT} . "/$app_name/lib/Config/global.conf",
                               $ENV{SDRROOT} . "/$app_name/lib/Config/local.conf"
                              );
    
    $$env{'psgix.config'} = $config;
    
    my $res = $self->app->($env);

    # # fix content length??
    # if ( ref $res eq 'ARRAY' && ref($res->[2]) eq 'ARRAY' ) {
    #     my $content_length = Plack::Util::header_get($res->[1], "Content-Length");
    #     if ( $content_length && $content_length != length(join('', @{$res->[2]})) ) {
    #         Plack::Util::header_set($res->[1], 'Content-Length', length(join('', @{$res->[2]})));
    #     }
    # }

    return $res if ref $res eq 'ARRAY';

    return sub {
        my $respond = shift;

        my $writer;
        $res->(sub { return $writer = $respond->(@_) });
    }
}

1;

__END__
