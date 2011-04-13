package FCGI::ProcManager::HT;

use parent qw/FCGI::ProcManager/;

use strict;
use Exporter;
use POSIX qw(:signal_h);

use constant DEFAULT_MAXREQUESTS => 1000;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    unless ( exists($self->{maxrequests}) ) {
        # allow maxrequests to be 0
        $self->{maxrequests} = exists($ENV{FCGI_MAXREQUESTS}) ? $ENV{FCGI_MAXREQUESTS} : DEFAULT_MAXREQUESTS;
    }
    
    $self->{n_request} = 0;
    $self;
}

sub pm_post_dispatch {
    my $self = shift;
    $self->SUPER::pm_post_dispatch(@_);
    
    # cleanup the tmp space
    cleanup();
    
    if ( $self->{maxrequests} > 0 ) {
        $self->{maxrequests} -= 1;
        if ( $self->{maxrequests} <= 0 ) {
            $self->pm_exit("max requests exhausted", 0);
        }
    }
}

### Copied from Utils::Extract

sub cleanup {
    my $pid = $$;
    my $suffix = shift;
    my $expired = 120; # seconds

    # regexp must match template in get_formatted_path()
    my $tmp_root = __get_root();
    if (opendir(DIR, $tmp_root)) {
        my @targets = grep(! /(^\.$|^\.\.$)/, readdir(DIR));
        my $pattern = qr{.*?_${pid}__.*};
        if ( $suffix ) { $pattern = qr{.*?_${pid}__[0-9]+_${suffix}} }
        # my @rm_pid_targets = grep(/.*?_${pattern}__.*/, @targets);
        my @rm_pid_targets = grep(/$pattern/, @targets);
        foreach my $sd (@rm_pid_targets) {
            system("rm", "-rf", "$tmp_root/$sd");
        }

        my $now = time();
        foreach my $sd (@targets) {
            my ($created) = ($sd =~ m,.*?__(\d+),);
            next unless ( $created );
            if (($now - $created) > $expired) {
                system("rm", "-rf", "$tmp_root/$sd");
            }
        }
    }
    
    closedir(DIR);
}

sub __get_root {
    my $tmp_root = defined($ENV{'RAMDIR'}) ? $ENV{'RAMDIR'} : "/ram";
    return $tmp_root;
}

END {
    cleanup();
}


1;
