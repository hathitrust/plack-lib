package CGI::Application::PSGIApp;
use strict;
use Carp;

use vars qw($VERSION @ISA @EXPORT);

use base qw/CGI::Application/;

use CGI::PSGI;

our $VERSION = '0.1';

sub _run {
    my $self = shift;
    my $q = $self->query();

    my $rm_param = $self->mode_param();

    my $rm = $self->__get_runmode($rm_param);

    # Set get_current_runmode() for access by user later
    $self->{__CURRENT_RUNMODE} = $rm;

    # Allow prerun_mode to be changed
    delete($self->{__PRERUN_MODE_LOCKED});

    # Call PRE-RUN hook, now that we know the run mode
    # This hook can be used to provide run mode specific behaviors
    # before the run mode actually runs.
    $self->call_hook('prerun', $rm);

    # Lock prerun_mode from being changed after cgiapp_prerun()
    $self->{__PRERUN_MODE_LOCKED} = 1;

    # If prerun_mode has been set, use it!
    my $prerun_mode = $self->prerun_mode();
    if (length($prerun_mode)) {
        $rm = $prerun_mode;
        $self->{__CURRENT_RUNMODE} = $rm;
    }

    # Process run mode!
    my $body = $self->__get_body($rm);

    # Support scalar-ref for body return
    $body = $$body if ref $body eq 'SCALAR';

    # Call cgiapp_postrun() hook
    $self->call_hook('postrun', \$body);

    # Set up HTTP headers
    my $headers = $self->_send_headers();

    # Build up total output
    my $output  = $headers.$body;

    # Send output to browser (unless we're in serious debug mode!)
    unless ($ENV{CGI_APP_RETURN_ONLY}) {
        print $output;
    }

    # clean up operations
    $self->call_hook('teardown');

    if ( $ENV{CGI_APP_RETURN_ONLY} ) {
        return $body;
    }
    return $output;
}

sub _send_headers {
    return '';
}

sub run {
    my $self = shift;
    my $env = shift;
    
    $self->{__QUERY_OBJ} = CGI::PSGI->new($env);
    my $body = do {
        local $ENV{CGI_APP_RETURN_ONLY} = 1;
        $self->_run;
    };

    my $q    = $self->query;
    my $type = $self->header_type;
    
    my @headers;
    if ($type eq 'redirect') {
        my %props = $self->header_props;
        $props{'-location'} ||= delete $props{'-url'} || delete $props{'-uri'};
        @headers = $q->psgi_header(-Status => 302, %props);
    } elsif ($type eq 'header') {
        my %props = $self->header_props;
        @headers = $q->psgi_header(%props);
    } elsif ($type eq 'none') {
        Carp::croak("header_type of 'none' is not support by CGI::Application::PSGI");
    } else {
        Carp::croak("Invalid header_type '$type'");
    }

    use Scalar::Util;

    # code refs are passed without headers!!!
    if (ref($body) eq 'CODE' ) {
        return $body;
    }

    # wrap $body if it's not a blessed ref
    $body = [ $body ] unless Scalar::Util::blessed($body);
    return [ @headers, $body ];
    
}

1;