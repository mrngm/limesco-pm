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
  use Data::Dumper;
  my $lim = Net::Limesco->new();
  $lim->obtainToken();
  print Dumper($lim->getMyInvoices());

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

=head2 getMySims ()

=cut

sub getMySims {
	my ($self) = @_;
	$self->_assertToken();
	$self->_debug("Obtaining my SIMs...\n");
	return $self->_get_json("/sims");
}

=head2 getMyInvoices ()

=cut

sub getMyInvoices {
	my ($self) = @_;
	$self->_assertToken();
	$self->_debug("Obtaining my invoices...\n");
	return $self->_get_json("/accounts/~/invoices");
}

=head2 getMyPayments ()

=cut

sub getMyPayments {
	my ($self) = @_;
	$self->_assertToken();
	$self->_debug("Obtaining my payments...\n");
	return $self->_get_json("/accounts/~/payments");
}

=head2 getIssuers ()

=cut

sub getIssuers {
	my ($self) = @_;
	$self->_debug("Obtaining issuers...\n");
	return $self->_get_json("/ideal/issuers");
}

=head1 ADMINISTRATOR METHODS

Methods to communicate with the administration part of the Limesco REST API.

=head2 getAccount (accountId)

=cut

sub getAccount {
	my ($self, $account) = @_;
	croak "Missing account ID" if(!$account);
	$self->_assertToken();
	$self->_debug("Obtaining information about account ID $account...\n");
	return $self->_get_json("/accounts/$account");
}

=head2 saveAccount (account)

=cut

sub saveAccount {
	my ($self, $account) = @_;
	my $id = $account->{'id'};
	croak "Missing account ID (use createAccount to create one)" if(!$id);
	$self->_assertToken();
	$self->_debug("Storing account with ID $id\n");
	return $self->_put("/accounts/$id", $account);
}

=head2 saveSim (sim)

=cut

sub saveSim {
	my ($self, $sim) = @_;
	my $id = $sim->{'iccid'};
	croak "Missing SIM ID (use createSim to create one)" if(!$id);
	$self->_assertToken();
	$self->_debug("Storing SIM with ID $id\n");
	return $self->_put("/sims/$id", $sim);
}

=head2 getAccountValidation (accountId)

=cut

sub getAccountValidation {
	my ($self, $accountid) = @_;
	croak "Missing account ID" if(!$accountid);
	$self->_assertToken();
	$self->_debug("Obtaining validation information about account ID $accountid...\n");
	my $response = $self->_get("/accounts/$accountid/validate");
	if($response->{'success'} && $response->{'code'} == 204) { # No content
		return ();
	}
	if(!$response->{'body'}) {
		warn $response->{'error'} . "\n";
		return;
	}
	return @{decode_json($response->{'body'})};
}

=head2 getSimValidation (simId)

=cut

sub getSimValidation {
	my ($self, $simid) = @_;
	croak "Missing SIM ICCID" if(!$simid);
	$self->_assertToken();
	$self->_debug("Obtaining validation information about SIM ICCID $simid...\n");
	my $response = $self->_get("/sims/$simid/validate");
	if($response->{'success'} && $response->{'code'} == 204) { # No content
		return ();
	}
	if(!$response->{'body'}) {
		warn $response->{'error'} . "\n";
		return;
	}
	return @{decode_json($response->{'body'})};
}

=head2 getSimsByOwnerId (accountId)

=cut

sub getSimsByOwnerId {
	my ($self, $accountid) = @_;
	croak "Missing account ID" if(!$accountid);
	$self->_assertToken();
	$self->_debug("Obtaining SIMs from owner ID $accountid...\n");
	return @{$self->_get_json("/accounts/$accountid/sims")};
}

=head2 getSim (simId)

=cut

sub getSim {
	my ($self, $simid) = @_;
	croak "Missing SIM ID" if(!$simid);
	$self->_assertToken();
	$self->_debug("Obtaining information about SIM ID $simid...\n");
	return $self->_get_json("/sims/$simid");
}

=head2 getUnallocatedSims ()

=cut

sub getUnallocatedSims {
	my ($self) = @_;
	$self->_assertToken();
	$self->_debug("Obtaining unallocated SIMs...\n");
	return @{$self->_get_json("/sims/unallocated")};
}

=head2 getAllAccounts ()

=cut

sub getAllAccounts {
	my ($self) = @_;
	$self->_debug("Retrieving all accounts...\n");
	my $res = $self->_post_json("/accounts/find", {});
	return @$res if($res);
	return;
}

=head2 findAccountsBy (method => value)

=cut

sub findAccountsBy {
	my ($self, $field, $value) = @_;
	$self->_debug("Searching for accounts where $field = $value...\n");
	my $res = $self->_post_json("/accounts/find", {$field => $value});
	return @$res if($res);
	return;
}

=head2 createAccount (options)

options is a hash containing the fields 'email', 'companyName', 'firstName',
'lastName', 'streetAddress', 'postalCode', 'locality'.

=cut

sub createAccount {
	my ($self, %in_opts) = @_;
	my %opts;
	for(qw(email companyName firstName lastName streetAddress postalCode locality)) {
		my $val = delete $in_opts{$_};
		if(!defined $val) {
			croak "Missing option $_";
		}
		$opts{$_} = $val;
	}
	foreach(keys %in_opts) {
		croak "Unknown option $_";
	}
	$opts{fullName} = {
		firstName => delete $opts{firstName},
		lastName  => delete $opts{lastName},
	};
	my $name = $opts{fullName}{firstName} . " " . $opts{fullName}{lastName};
	$opts{address} = {
		streetAddress => delete $opts{streetAddress},
		postalCode => delete $opts{postalCode},
		locality => delete $opts{locality},
	};
	$self->_debug("Creating account for %s\n", $name);
	my $resp = $self->_post("/accounts", \%opts);
	my $accountloc = $resp->{location};
	if(!$accountloc) {
		warn $resp->{error} . "\n";
		return;
	}
	$self->_debug("Account created for %s at %s\n", $name, $accountloc);

	return $self->_get_json_url($accountloc);
}

=head2 addExternalAccountToAccount (accountId, service => remotename)

Add the remote id "remotename" for service "service" to the account pointed to
by "accountId".

=cut

sub addExternalAccountToAccount {
	my ($self, $accountid, $service, $remotename) = @_;
	$self->_debug("Adding external account %s for %s to account ID %s\n", $remotename, $service, $accountid);
	my $resp = $self->_post("/accounts/$accountid/addExternalAccounts", {$service => $remotename});
	if($resp->{error}) {
		warn $resp->{error} . "\n";
		return 0;
	}
	$self->_debug("External account %s added\n", $remotename);
	return 1;
}

=head2 createPayment (options)

options is a hash containing the fields 'accountId', 'currency', 'paymentType',
'destination', and 'amount', and optionally 'status', 'transactionId' and
'invoiceIds'.

=cut

sub createPayment {
	my ($self, %in_opts) = @_;
	my %opts;
	## Required options
	for(qw(accountId currency paymentType destination amount)) {
		my $val = delete $in_opts{$_};
		if(!$val) {
			croak "Missing option $_";
		}
		$opts{$_} = $val;
	}
	## Optional option
	for(qw(status invoiceIds transactionId)) {
		if(exists($in_opts{$_})) {
			$opts{$_} = delete $in_opts{$_};
		}
	}
	foreach(keys %in_opts) {
		croak "Unknown option $_";
	}
	if($opts{invoiceIds} && ref($opts{invoiceIds}) ne "ARRAY") {
		croak "invoiceIds option must be an array reference";
	}
	my $accountId = delete $opts{accountId};
	$self->_debug("Creating payment for account ID %s\n", $accountId);
	my $resp = $self->_post("/accounts/$accountId/payments", \%opts);
	my $paymentloc = $resp->{location};
	if(!$paymentloc) {
		warn $resp->{error} . "\n";
		return;
	}
	$self->_debug("Payment created for account ID %s at %s\n", $accountId, $paymentloc);

	return $self->_get_json_url($paymentloc);
}

=head2 createSim (options)

options is a hash containing the fields 'iccid', 'puk' and 'state', and
optionally 'contractStartDate', 'phoneNumber', 'sipRealm', 'sipUsername',
'sipUri', 'sipAuthenticationUsername', 'sipPassword', 'sipExpiry',
'callConnectivityType', 'ownerAccountId', 'apnType', 'activationInvoiceId'
and 'lastMonthlyFeesInvoice'.

=cut

sub createSim {
	my ($self, %in_opts) = @_;
	my %opts;
	## Required options
	for(qw(iccid puk state)) {
		my $val = delete $in_opts{$_};
		if(!$val) {
			croak "Missing option $_";
		}
		$opts{$_} = $val;
	}
	## Optional options
	my $hasSip = 0;
	for(qw( contractStartDate phoneNumber sipRealm sipUsername sipUri
		sipAuthenticationUsername sipPassword sipExpiry
		callConnectivityType ownerAccountId apnType
		activationInvoiceId lastMonthlyFeesInvoice))
	{
		if(exists($in_opts{$_})) {
			$hasSip = 1 if($_ =~ /^sip/);
			$opts{$_} = delete $in_opts{$_};
		}
	}
	foreach(keys %in_opts) {
		croak "Unknown option $_";
	}

	if($hasSip) {
		$opts{sipSettings} = {};
		for(qw(sipRealm sipUsername sipUri sipAuthenticationUsername sipPassword sipExpiry)) {
			my $newName = $_;
			$newName =~ s/^sip(.)/lc($1)/e;
			$opts{sipSettings}{$newName} = delete $opts{$_};
		}
	}

	$self->_debug("Creating SIM with state %s for account ID %s\n", $opts{state}, $opts{ownerAccountId} || "(none)");
	my $resp = $self->_post("/sims", \%opts);
	my $simloc = $resp->{location};
	if(!$simloc) {
		warn $resp->{error} . "\n";
		return;
	}
	$self->_debug("SIM created at %s\n", $simloc);

	return $self->_get_json_url($simloc);
}

=head2 allocateSim (options)

options is a hash containing the fields 'simIccid', 'ownerAccountId',
'apn' (APN_NODATA, APN_500MB, APN_2000MB), 'callConnectivityType' (OOTB, DIY),
and 'numberPorting' (true, false).

=cut

sub allocateSim {
	my ($self, %in_opts) = @_;
	my %opts;
	## Required options
	for(qw(simIccid ownerAccountId apn callConnectivityType numberPorting)) {
		my $val = delete $in_opts{$_};
		if(!$val) {
			croak "Missing option $_";
		}
		$opts{$_} = $val;
	}
	## Optional options
	foreach(keys %in_opts) {
		croak "Unknown option $_";
	}

	my $iccid = delete $opts{'simIccid'};
	$self->_debug("Allocating SIM %s to account ID %s\n", $iccid, $opts{'ownerAccountId'});
	my $resp = $self->_post("/sims/$iccid/allocate", \%opts);
	if($resp->{error}) {
		warn $resp->{error} . "\n";
		return;
	}
	$self->_debug("SIM allocated\n");
	return 1;
}

=head1 DISPLAY METHODS

=head2 account_to_str ($account, $html)

=cut

sub account_to_str {
	my ($self, $account, $html) = @_;
	$html ||= 0;

	if(!$account || ref($account) ne "HASH" || !$account->{'id'}) {
		return "Invalid account";
	}

	if(!$account->{'email'} || !$account->{'fullName'} || !$account->{'fullName'}{'lastName'}) {
		return "Invalid account " . $account->{'id'};
	}

	my $name = $account->{'fullName'}{'firstName'} . " " . $account->{'fullName'}{'lastName'};
	my $email = $account->{'email'};
	my $company = $account->{'companyName'};
	my $namedescr = $html ? ("<underline>" . $name . "</underline>") : $name;
	if($company) {
		$namedescr = $html ? ("<underline>$company</underline> ($name)") : "$company ($name)";
	}
	return "$namedescr <$email>";
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
	$msg = sprintf($msg, @args);
	if(ref($self->{debug}) eq "CODE") {
		$self->{debug}->($msg);
	} elsif($self->{debug}) {
		print $msg;
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
			location => $location,
			success => 1,
			code => $response->code};
	} else {
		return {error => $response->status_line,
			success => 0,
			code => $response->code};
	}
}

sub _get_json {
	my $self = shift;
	my $resp = $self->_get(@_);
	if(!$resp->{body}) {
		warn $resp->{error} . "\n";
		return;
	}
	return decode_json($resp->{body});
}

sub _get {
	my $self = shift;
	my $url = $self->__url(shift);
	return $self->_get_url($url, @_);
}

sub _get_json_url {
	my ($self, $url) = @_;
	my $resp = $self->_get_url($url);
	if(!$resp->{body}) {
		warn $resp->{error} . "\n";
		return;
	}
	return decode_json($resp->{body});
}

sub _get_url {
	my ($self, $url, $body, $bodytype) = @_;
	$self->_debug("Doing GET request to URL: %s\n", $url);
	my $response = $self->{ua}->get($url, $self->__headers($body, $bodytype));
	return $self->__wrap_response($response);
}

sub _post_json {
	my $self = shift;
	my $resp = $self->_post(@_);
	if(!$resp->{body}) {
		warn $resp->{error} . "\n";
		return;
	}
	return decode_json($resp->{body});
}

sub _post {
	my $self = shift;
	my $url = $self->__url(shift);
	return $self->_post_url($url, @_);
}

sub _put {
	my $self = shift;
	my $url = $self->__url(shift);
	return $self->_put_url($url, @_);
}

sub _post_url {
	my ($self, $url, $body, $bodytype) = @_;
	$self->_debug("Doing POST request to URL: %s\n", $url);
	my $response = $self->{ua}->post($url, $self->__headers($body, $bodytype));
	return $self->__wrap_response($response);
}

sub _put_url {
	my ($self, $url, $body, $bodytype) = @_;
	$self->_debug("Doing PUT request to URL: %s\n", $url);
	my $response = $self->{ua}->put($url, $self->__headers($body, $bodytype));
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
