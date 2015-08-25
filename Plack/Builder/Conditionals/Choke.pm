package Plack::Builder::Conditionals::Choke;

use base qq/Plack::Builder::Conditionals/;

use Plack::Request;

sub import {
    my $class = shift;
    my $caller = caller;
    my %args = @_;
    
    $class->SUPER::import(@_);

    ## grr, not very subclass friendly...
    # my @EXPORT = qw/env unchoked/;
    my @EXPORT = qw/match_if addr path method header browser any all env unchoked param/;

    no strict 'refs';
    my $i=0;
    for my $sub (@EXPORT) {
        my $sub_name = $args{'-prefix'} ? $args{'-prefix'} . '_' . $sub : $sub;
        *{"$caller\::$sub_name"} = \&$sub;
    }
}

sub env {
    my $not;
    my $key;
    my @args;
    if ( $_[0] eq '!' ) {
        $not = shift;
        push @args, $not;
    }
    $key = shift;
    push @args, @_;
    
    return _match($key, @args);
}

sub unchoked {
    return sub {
        my $env = shift;
        return ( ! $$env{'psgix.choked'} );
    }
}

sub param {
    my $not;
    my $key;
    my @args;
    if ( $_[0] eq '!' ) {
        $not = shift;
    }
    $key = shift;
    my $value = shift;
    my $max_number = shift;

    return sub {
        my $env = shift;
        my $request = Plack::Request->new($env);
        my @tmp = $request->param($key);
        my $check = $request->param($key);

        if ( defined $max_number ) {
            return 0 if ( scalar @tmp > $max_number );
        }

        if ( $value ) {
            if ( ref($value) eq 'Regexp' ) {
                $check = $check =~ $value;
            } else {
                $check = $check eq $value;
            }
        } else {
            $check = 1 if ( $check );
        }
        if ( $not ) { $check = ! $check };
        ## print STDERR "PARAM :: $key :: [$check] :: $$env{QUERY_STRING} :: $$env{HTTP_QUERY_STRING}\n";
        return $check;
    }
}

1;