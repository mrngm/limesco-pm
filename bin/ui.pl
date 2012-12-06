#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Curses;
use Curses::UI;
use Net::Limesco;

my ($user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 username password [hostname [port]]";
}

my $lim = Net::Limesco->new($hostname, $port, 0 && sub { print STDERR $_[0] });
if(!$lim->obtainToken($user, $pass)) {
	die "Couldn't obtain token";
}

my $ui = Curses::UI->new(-clear_on_exit => 1, -color_support => 1);

my $win = $ui->add('win', 'Window',
	-border => 1,
	-bfg => "red",
	-title => "Account list");

#my @account_ids = $lim->getAllAccountIds();
my @account_ids = map { $_->{'id'} } $lim->getAllAccounts();
$ui->progress(-max => 1, -message => "Loading account information...");
my @accounts;
foreach(@account_ids) {
	push @accounts, $lim->getAccount($_);
	$ui->setprogress(@accounts/@account_ids, "Loading accounts... " . @accounts . "/" . @account_ids);
}
$ui->noprogress;

@accounts = sort { ($a->{'fullName'}{'firstName'}||"") cmp ($b->{'fullName'}{'firstName'}||"") } @accounts;
@accounts = sort { ($a->{'fullName'}{'lastName'}||"") cmp ($b->{'fullName'}{'lastName'}||"") } @accounts;
my $listbox = $win->add("acctbox", 'Listbox',
	-values => [map {$_->{'id'}} @accounts],
	-labels => {map {$_->{'id'} => account_to_str($_, 1)} @accounts},
	-vscrollbar => 'right',
	-hscrollbar => 'bottom',
	-htmltext => 1,
);
$listbox->focus();

my $accountwin;
my $simwin;
$win->set_binding(sub {
	if($simwin) {
		$simwin->hide();
		$accountwin->delete('simwin');
		$accountwin->focus();
		undef $simwin;
	} elsif($accountwin) {
		$accountwin->hide();
		$win->delete('subwin');
		$win->focus();
		undef $accountwin;
	} else {
		exit(0);
	}
}, "q", KEY_LEFT());

$listbox->onChange(sub {
	my $account_id = $listbox->get();
	$listbox->clear_selection();
	my $account = $lim->getAccount($account_id);
	$accountwin = $win->add('subwin', 'Window',
		-border => 1,
		-bfg => "green",
		-title => "Account view: " . account_to_str($account));

	my @sims = $lim->getSimsByOwnerId($account_id);

	my $ext = $account->{'externalAccounts'} || {};
	my $text = join "\n",
		"ID: " . $account->{'id'},
		"E-mail address: " . ($account->{'email'} || "unset"),
		"Account state: " . ($account->{'state'} || "unset"),
		"Company name: " . ($account->{'companyName'} || ""),
		"Full name: " . ($account->{'fullName'}{'firstName'} || "") . " " . ($account->{'fullName'}{'lastName'} || ""),
		"Address: ",
		"    " . ($account->{'address'}{'streetAddress'} || ""),
		"    " . ($account->{'address'}{'postalCode'} || "") . " " . ($account->{'address'}{'locality'} || ""),
		"External accounts: " . (%$ext ? join(", ", map { $ext->{$_} . " ($_)" } keys %$ext) : "(none)");

	my $halfheight = $accountwin->height() / 2;
	$accountwin->add('accountinfo', 'Label', -text => $text, -width => -1, -height => $halfheight)->show();
	$accountwin->add('simboxtitle', 'Label', -text => "SIMs in this account", -width => -1, -height => 1, -y => $halfheight)->show();

	my $simbox = $accountwin->add("simbox", 'Listbox',
		-values => [map {$_->{'iccid'}} @sims],
		-labels => {map {$_->{'iccid'} => sim_to_str($_, 0, 1)} @sims},
		-vscrollbar => 'right',
		-hscrollbar => 'bottom',
		-htmltext => 1,
		-height => $halfheight,
		-y => $halfheight + 1,
		-title => "SIMs in this account",
	);

	$simbox->show();
	$accountwin->show();
	$simbox->focus();

	$simbox->onChange(sub {
		my $sim_id = $simbox->get();
		return if(!defined($sim_id));
		$simbox->clear_selection();
		my $sim = $lim->getSim($sim_id);
		$simwin = $accountwin->add('simwin', 'Window',
			-border => 1,
			-bfg => "yellow",
			-title => "SIM view: " . sim_to_str($sim));
		my (undef, undef, undef, $mday, $mon, $year) = localtime($sim->{'contractStartDate'} / 1000);
		my $text = join "\n",
			"ICCID: " . $sim->{'iccid'},
			"PUK: " . $sim->{'puk'},
			"State: " . $sim->{'state'},
			"",
			"Contract start date: " . sprintf("%4d-%02d-%02d", $year+1900, $mon+1, $mday),
			"Call connectivity type: " . $sim->{'callConnectivityType'},
			"Phone number: " . $sim->{'phoneNumber'},
			"Owner: " . account_to_str($lim->getAccount($sim->{'ownerAccountId'}), 0),
			"APN type: " . $sim->{'apnType'},
			"Exempt from cost contribution: " . $sim->{'exemptFromCostContribution'};
		$simwin->add('siminfo', 'Label', -text => $text)->show();
		$simwin->show();
		$simwin->focus();
	});

});

$ui->mainloop();
exit;

sub account_to_str {
	my ($account, $html) = @_;
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
		return "$marker " . $account->{'id'};
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

sub sim_to_str {
	my ($sim, $with_account, $html) = @_;
	$with_account ||= 0;
	$html ||= 0;

	my $marker = "";
	if($sim->{'state'} eq "STOCK") {
		$marker = "[S]";
	} elsif($sim->{'state'} eq "ALLOCATED") {
		$marker = "[A]";
	} elsif($sim->{'state'} eq "ACTIVATION_REQUESTED") {
		$marker = "[Q]";
	} elsif($sim->{'state'} eq "DISABLED") {
		$marker = "[D]";
	}

	my $iccid = $sim->{'iccid'};
	my $phonenr = $sim->{'phoneNumber'};
	my (undef, undef, undef, $mday, $mon, $year) = localtime($sim->{'contractStartDate'} / 1000);

	return sprintf("%s started %4d-%02d-%02d number %s iccid %s", $marker, $year+1900, $mon+1, $mday, $phonenr, $iccid);
}
