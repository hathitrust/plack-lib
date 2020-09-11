package Plack::Middleware::HTHTTPExceptions;
use strict;
use parent qw(Plack::Middleware::HTTPExceptions);
use Plack::Util::Accessor qw(rethrow);

use Carp ();
use Try::Tiny;
use Scalar::Util 'blessed';
use HTTP::Status ();


sub transform_error {
    my($self, $e, $env) = @_;

    my($code, $message);
    if (blessed $e && $e->can('as_psgi')) {
        return $e->as_psgi;
    }
    if (blessed $e && $e->can('code')) {
        $code = $e->code;
        $message =
            $e->can('as_string')       ? $e->as_string :
            overload::Method($e, '""') ? "$e"          : undef;
    } else {
        if ($self->rethrow) {
            die $e;
        }
        else {
            # $code = ( $e =~ m,Invalid document id provided, ) ? 404 : 500;
            $code = 500;
            $env->{'psgi.errors'}->print($e);
        }
    }

    if ($code !~ /^[3-5]\d\d$/) {
        die $e; # rethrow
    }

    $message ||= HTTP::Status::status_message($code);

    my @headers = (
         'Content-Type'   => 'text/plain',
         'Content-Length' => length($message),
    );

    if ($code =~ /^3/ && (my $loc = eval { $e->location })) {
        push(@headers, Location => $loc);
    }

    return [ $code, \@headers, [ $message ] ];
}

1;

__END__

=head1 NAME

Plack::Middleware::HTHTTPExceptions - Catch HTTP exceptions

=head1 SYNOPSIS

  use HTTP::Exception;

  my $app = sub {
      # ...
      HTTP::Exception::500->throw;
  };

  builder {
      enable "HTTPExceptions", rethrow => 1;
      $app;
  };

=head1 DESCRIPTION

Based on Plack::Middleware::HTHTTPExceptions.

=cut
