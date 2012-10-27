package Net::Limesco;

use 5.012004;
use strict;
use warnings;

use Carp;
use LWP::UserAgent;
use JSON;

our $VERSION = "1.0";

=head1 NAME

Net::Limesco - Perl interface to the Limesco REST API

=head1 SYNOPSIS

  use Net::Limesco;
  my $lim = Net::Limesco->new();
  $lim->obtainToken();

=head1 DESCRIPTION

This module is an interface to the Limesco API found at
http://api.limesco.org/.

=head1 METHODS

=head2 new ([hostname, [port, [debug]]])

=cut

sub new {
	my ($pkg, $hostname, $port, $debug) = @_;
	$hostname ||= "api.limesco.org";
	$port ||= 80;
	$debug ||= 0;
	my $self = {
		hostname => $hostname,
		port => $port,
		debug => $debug,
		ua => LWP::UserAgent->new(),
	};
	$self->{ua}->timeout(2000);
	$self->{ua}->env_proxy();
	$self->{ua}->agent("Net::Limesco/$VERSION (".$self->{ua}->_agent().", Perl/$])");
	bless $self, $pkg;
	return $self;
}

=head2 obtainToken (username, password)

=cut

sub obtainToken {
	my ($self, $username, $password) = @_;
	$self->_debug("Obtaining token...\n");
	my $resp = $self->_post("/auth/login/obtainToken", {username => $username, password => $password});
	if(!$resp->{body}) {
		warn $resp->{error} . "\n";
		return;
	}
	$self->{token} = $resp->{body};
	$self->_debug("Token obtained: '%s'\n", $self->{token});
	return $self->{token};
}

## Internal undocumented methods starting here ##

sub _assertToken {
	my ($self) = @_;
	if(!$self->{token}) {
		croak "This call needs a token but we don't have one, call obtainToken() first";
	}
}

sub _debug {
	my ($self, $msg, @args) = @_;
	if($self->{debug}) {
		printf($msg, @args);
	}
}

sub __headers {
	my ($self, $body, $bodytype) = @_;
	my %h;
	if($body) {
		$h{'Content'} = encode_json($body);
		$h{'Content-Type'} = "application/json";
	}
	if($self->{token}) {
		$h{'X-Limesco-Token'} = $self->{token};
	}
	return %h;
}

sub __url {
	my ($self, $uri) = @_;
	return "http://" . $self->{hostname} . ":" . $self->{port} . $uri;
}

sub __wrap_response {
	my ($self, $response) = @_;
	if($response->is_success) {
		my $location = $response->header("Location");
		return {body => $response->decoded_content,
			location => $location};
	} else {
		return {error => $response->status_line};
	}
}

sub _get {
	my $self = shift;
	my $url = $self->__url(shift);
	return $self->_get_url($url, @_);
}

sub _get_url {
	my ($self, $url, $body, $bodytype) = @_;
	$self->_debug("Doing GET request to URL: %s\n", $url);
	my $response = $self->{ua}->get($url, $self->__headers($body, $bodytype));
	return $self->__wrap_response($response);
}

sub _post {
	my $self = shift;
	my $url = $self->__url(shift);
	return $self->_post_url($url, @_);
}

sub _post_url {
	my ($self, $url, $body, $bodytype) = @_;
	$self->_debug("Doing POST request to URL: %s\n", $url);
	my $response = $self->{ua}->post($url, $self->__headers($body, $bodytype));
	return $self->__wrap_response($response);
}

=head1 SEE ALSO

=over

=item *

http://limesco.org/

=item *

http://wiki.limesco.org/

=back

=head1 AUTHOR

Sjors Gielen, E<lt>sjors@limesco.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Sjors Gielen

See the LICENSE file for the license on this module.

=cut

1;

__END__
