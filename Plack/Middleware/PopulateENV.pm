package Plack::Middleware::PopulateENV;
use strict;
use parent qw(Plack::Middleware);

use Carp ();
use Debug::DUtils;

sub call {
    my($self, $env) = @_;
    
    local %ENV = %ENV;
    foreach my $key ( keys %$env ) {
        $ENV{$key} = $$env{$key};
    }
    
    my $app_name = Debug::DUtils::___determine_app(); # $self->app_name;
    $$env{'psgix.app_name'} = $app_name;
    
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
