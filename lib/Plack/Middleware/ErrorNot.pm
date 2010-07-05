package Plack::Middleware::ErrorNot;

use strict;
use warnings;

use POSIX qw(strftime);
use JSON;
use Try::Tiny;
use Devel::StackTrace;
use AnyEvent::HTTP;

use parent qw(Plack::Middleware);
use Plack::Util::Accessor qw(api_key api_url);

sub call {
    my ($self, $env) = @_;

    my($trace, $exception);
    local $SIG{__DIE__} = sub {
        $trace = Devel::StackTrace->new;
        $exception = $_[0];
        die @_;
    };

    my $res;
    try { $res = $self->app->($env) };

    if ($trace && (!$res or $res->[0] == 500)) {
        $self->send_notify($trace, $exception, $env);
        $res = [500, ['Content-Type' => 'text/html'], [ "Internal Server Error" ]];
    }

    # break $trace here since $SIG{__DIE__} holds the ref to it, and
    # $trace has refs to Standalone.pm's args ($conn etc.) and
    # prevents garbage collection to be happening.
    undef $trace;

    return $res;
}

sub send_notify {
    my ($self, $trace, $exception, $env) = @_;

    my $req = Plack::Request->new($env);
    my $raised_at = strftime "%a %b %e %H:%M:%S %Y", gmtime;

    my @env_infos = (
        qw/PATH_INFO
          SERVER_NAME
          SERVER_PORT
          HTTP_ACCEPT
          HTTP_ACCEPT_CHARSER
          HTTP_ACCEPT_ENCODING
          HTTP_ACCEPT_LANGUAGE
          HTTP_HOST
          REQUEST_METHOD
          REMOTE_ADDR/
    );

    my $hash_exception = {
        api_key => $self->api_key,
        error   => {
            message   => $exception,
            raised_at => $raised_at,
            backtrace => '',
            request   => {
                url        => $req->uri->as_string,
                action     => $req->uri->path,
                parameters => map { $_ => $req->parameters->{$_} }
                  keys %{$req->parameters},
                session => map { $_ => $req->session->{$_} }
                  keys %{$req->session},
            },
        }
    };

    foreach my $env_key (@env_infos) {
        $hash_exception->{environment}->{$env_key} = $env->{$env_key}
          if exists $env->{$env_key};
    }

    my $cv = AE::cv;

    AnyEvent::HTTP::http_post $self->api_url,
      JSON::encode_json($hash_exception),
      headers => {
        'Content-Type' => 'application/json',
        'Accept-Type'  => 'application/json'
      }, $cv;

    $cv->recv unless $env->{'psgi.nonblocking'};
}

1;

=head1 NAME

Plack::Middleware::ErrorNot - Sends application errors to ErrorNot

=head1 SYNOPSIS

  enable "ErrorNot", api_key => "...", api_url => "...";

=head1 DESCRIPTION

This middleware catches exceptions (run-time errors) happening in your
application and sends them to L<ErrorNot|http://wiki.github.com/AF83/ErrorNot/>.

=head1 AUTHOR

franck cuny

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Plack::Middleware::StackTrace>, L<Plack::Middleware::HopToad>

=cut
