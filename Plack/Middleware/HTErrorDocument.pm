package Plack::Middleware::HTErrorDocument;
use strict;
use warnings;
use parent qw(Plack::Middleware);
use Plack::MIME;
use Plack::Util;

use HTTP::Status qw(is_error);
use Utils;
use Debug::DUtils;

sub call {
    my $self = shift;
    my $env  = shift;

    my $r = $self->app->($env);

    $self->response_cb($r, sub {
        my $r = shift;

        unless (is_error($r->[0]) && exists $self->{$r->[0]}) {
            return;
        }

        my $filename = $$env{'SDRROOT'} . '/' . $self->{$r->[0]};
        my ( $mime_type, $body ) = $self->read_error_file($filename);

        $r->[2] = [ $$body ];

        my $h = Plack::Util::headers($r->[1]);
        $h->remove('Content-Length');
        $h->set('Content-Type', $mime_type);
    });
}

sub read_error_file {
  my ( $self, $filename ) = @_;
  my $mime_type = Plack::MIME->mime_type($filename);
  my $body;
  if ( $mime_type =~ m,^text/, ) {
    $body = Utils::read_file($filename, 1);
    my $app_name = Debug::DUtils::___determine_app();
    $$body =~ s,\./,/$app_name/common-web/,g;
  } else {
    open(my $in, $filename);
    binmode($in);
    my $tmp;
    while ( <$in> ) {
      $tmp .= $_;
    }
    close($in);
    $body = \$tmp;
  }
  return ( $mime_type, $body );
}

1;

__END__

=head1 NAME

Plack::Middleware::HTErrorDocument - Set Error Document based on HTTP status code

=head1 SYNOPSIS

  # in app.psgi
  use Plack::Builder;

  builder {
      enable "Plack::Middleware::HTErrorDocument",
          500 => '/uri/errors/500.html', 404 => '/uri/errors/404.html',
          subrequest => 1;
      $app;
  };

=head1 DESCRIPTION

Based on Plack::Middleware::ErrorDocument

=head1 CONFIGURATIONS

=over 4

=item subrequest

A boolean flag to serve error pages using a new GET sub request.
Defaults to false, which means it serves error pages using file
system path.

  builder {
      enable "Plack::Middleware::ErrorDocument",
          502 => '/home/www/htdocs/errors/maint.html';
      enable "Plack::Middleware::ErrorDocument",
          404 => '/static/404.html', 403 => '/static/403.html', subrequest => 1;
      $app;
  };

This configuration serves 502 error pages from file system directly
assuming that's when you probably maintain database etc. but serves
404 and 403 pages using a sub request so your application can do some
logic there like logging or doing suggestions.

When using a subrequest, the subrequest should return a regular '200' response.

=cut
