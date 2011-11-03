package Plack::Middleware::Choke::Utils;

use Debug::DUtils;
use Utils;
use Utils::Cache::JSON;
use Utils::Extract;

sub setup_ram_cache {
    return Utils::Cache::JSON->new(qq{/ram/choke});
}

sub setup_filesystem_cache {
    my $choke_cache_key = shift || "choke_cache_dir";
    
    my $app_name = Debug::DUtils::___determine_app(); # $self->app_name;
    my $config = new MdpConfig(
                               Utils::get_uber_config_path($app_name),
                               $ENV{SDRROOT} . "/$app_name/lib/Config/global.conf",
                               $ENV{SDRROOT} . "/$app_name/lib/Config/local.conf"
                              );


    my $cache_dir = $config->get($choke_cache_key);
    if ( $cache_dir =~ m,___CACHE___, ) {
       $cache_dir = Utils::get_true_cache_dir($config, $choke_cache_key);
    }
    print STDERR "HEY: $cache_dir\n";
    return Utils::Cache::JSON->new($cache_dir);
}


1;