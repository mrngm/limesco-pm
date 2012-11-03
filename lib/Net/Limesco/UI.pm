package Net::Limesco::UI;
use strict;
use warnings;
use Curses::UI;

sub new {
	my ($pkg, $limesco, $ui, $win) = @_;
	my $self = {
		lim => $limesco,
		ui => $ui,
		win => $win,
	};
	bless $self, $pkg;
	return $self;
}

sub list_of_account_ids {
	my ($self, @account_ids) = @_;
	$self->{ui}->progress(-max => 1, -message => "Loading accounts...");
	my @accounts;
	foreach(@account_ids) {
		push @accounts, $self->{lim}->getAccount($_);
		$self->{ui}->setprogress(@accounts/@account_ids, "Loading accounts... " . @accounts . "/" . @account_ids);
	}
	$self->{ui}->noprogress;
	return $self->list_of_accounts(@accounts);
}

sub account_to_str {
	my ($self, $account, $html) = @_;
	$html ||= 0;

	my $marker = "";
	if($account->{'state'} eq "UNCONFIRMED") {
		$marker = "[U]";
	} elsif($account->{'state'} eq "CONFIRMATION_IMPOSSIBLE") {
		$marker = "[CI]";
	} elsif($account->{'state'} eq "CONFIRMATION_REQUESTED") {
		$marker = "[C]";
	} elsif($account->{'state'} eq "DEACTIVATED") {
		$marker = "[D]";
	}

	if(!$account->{'email'} || !$account->{'fullName'} || !$account->{'fullName'}{'lastName'}) {
		if($account->{'externalAccounts'} && %{$account->{'externalAccounts'}}) {
			my $ext = $account->{'externalAccounts'};
			return "[!] Dummy external account: " . join(", ", map { $ext->{$_} . " ($_)" } keys %$ext);
		}
		return "$marker " . $account->{'_id'};
	}

	my $name = $account->{'fullName'}{'firstName'} . " " . $account->{'fullName'}{'lastName'};
	my $email = $account->{'email'};
	my $company = $account->{'companyName'};
	my $namedescr = $html ? ("<underline>" . $name . "</underline>") : $name;
	if($company) {
		$namedescr = $html ? ("<underline>$company</underline> ($name)") : "$company ($name)";
	}
	return "$marker $namedescr <$email>";
}

sub list_of_accounts {
	my ($self, @accounts) = @_;
	@accounts = sort { ($a->{'fullName'}{'firstName'}||"") cmp ($b->{'fullName'}{'firstName'}||"") } @accounts;
	@accounts = sort { ($a->{'fullName'}{'lastName'}||"") cmp ($b->{'fullName'}{'lastName'}||"") } @accounts;
	my $listbox = $self->{win}->add("acctbox", 'Listbox',
		-values => [map {$_->{'_id'}} @accounts],
		-labels => {map {$_->{'_id'} => $self->account_to_str($_, 1)} @accounts},
		-vscrollbar => 'right',
		-hscrollbar => 'bottom',
		-htmltext => 1,
	);
	return ($listbox, "acctbox");
}

sub show_account_id {
	my ($self, $account_id) = @_;
	my $account = $self->{lim}->getAccount($account_id);
	if(!$account) {
		$self->warning("Account ID given '$account_id' does not exist");
		return;
	}
	return $self->show_account($account);
}

sub warning {
	my ($self, $error) = @_;
	my $dialog = $self->{ui}->error($error);
	$dialog->onblur(sub { $self->{ui}->mainloopExit });
	$self->{ui}->mainloop();
}

sub fatal_error {
	my ($self, $error) = @_;
	my $dialog = $self->{ui}->error($error);
	$dialog->onblur(sub { exit(0); });
	$self->{ui}->mainloop();
}

sub show_account {
	my ($self, $account) = @_;
	if(!$account) {
		$self->fatal_error("Empty account in show_account");
	}

	my $ext = $account->{'externalAccounts'} || {};
	my $text = join "\n",
		"ID: " . $account->{'_id'},
		"E-mail address: " . ($account->{'email'} || "unset"),
		"Account state: " . ($account->{'state'} || "unset"),
		"Company name: " . ($account->{'companyName'} || ""),
		"Full name: " . ($account->{'fullName'}{'firstName'} || "") . " " . ($account->{'fullName'}{'lastName'} || ""),
		"Address: ",
		"    " . ($account->{'address'}{'streetAddress'} || ""),
		"    " . ($account->{'address'}{'postalCode'} || "") . " " . ($account->{'address'}{'locality'} || ""),
		"External accounts: " . (%$ext ? join(", ", map { $ext->{$_} . " ($_)" } keys %$ext) : "(none)");

	my $label = $self->{win}->add('lbl', 'Label', -text => $text);
	return ($label, 'lbl');
}

1;
