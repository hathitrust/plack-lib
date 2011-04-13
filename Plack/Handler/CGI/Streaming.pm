package Plack::Handler::CGI::Streaming;
use base qw/Plack::Handler::CGI/;

sub _handle_response {
    my ($self, $res) = @_;

    *STDOUT->autoflush(1);

    my $hdrs;
    $hdrs = "Status: $res->[0]\015\012";

    my $headers = $res->[1];
    if ( $#$headers >= 0 ) {
        while (my ($k, $v) = splice(@$headers, 0, 2)) {
            $hdrs .= "$k: $v\015\012";
        }
        $hdrs .= "\015\012";
        print STDOUT $hdrs;
    }

    my $body = $res->[2];
    my $cb = sub { print STDOUT $_[0] };

    # inline Plack::Util::foreach here
    if (ref $body eq 'ARRAY') {
        for my $line (@$body) {
            $cb->($line) if length $line;
        }
    }
    elsif (defined $body) {
        local $/ = \65536 unless ref $/;
        while (defined(my $line = $body->getline)) {
            $cb->($line) if length $line;
        }
        $body->close;
    }
    else {
        return Plack::Handler::CGI::Writer->new;
    }
}

1;