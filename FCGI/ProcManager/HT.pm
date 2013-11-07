package FCGI::ProcManager::HT;

use parent qw/FCGI::ProcManager/;

use strict;
use Exporter;
use POSIX qw(:signal_h);

use Utils::Extract;

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

### invoke cleanup from Utils::Extract

sub cleanup {
    Utils::Extract::__handle_EndBlock_cleanup();
}

END {
    cleanup();
}


1;
