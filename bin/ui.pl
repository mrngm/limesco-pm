#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Encode;
use Curses;
use Curses::UI;
use Net::Limesco;

my ($user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 username password [hostname [port]]";
}

open STDERR, '>', "ui.log" or die $!;
my $lim = Net::Limesco->new($hostname, $port, 1 && sub { print STDERR $_[0] });
if(!$lim->obtainToken($user, $pass)) {
	die "Couldn't obtain token";
}

my $ui = Curses::UI->new(-clear_on_exit => 1, -color_support => 1);

my $win;
my $accountwin;
my $simwin;
my $allocate_listbox;

reinit:

if($simwin) {
	$simwin->hide();
	$accountwin->delete('simwin');
	undef $simwin;
}
if($accountwin) {
	$accountwin->hide();
	$win->delete('subwin');
	undef $accountwin;
}
if($win) {
	$win->hide();
	$ui->delete('win');
}

$win = $ui->add('win', 'Window',
	-border => 1,
	-bfg => "red",
	-title => "Account list");
$win->show();
$win->focus();

#my @account_ids = $lim->getAllAccountIds();
my @account_ids = map { $_->{'id'} } $lim->getAllAccounts();
$ui->progress(-max => 1, -message => "Loading account information...");
my @accounts = ();
foreach(@account_ids) {
	push @accounts, $lim->getAccount($_);
	$ui->setprogress(@accounts/@account_ids, "Loading accounts... " . @accounts . "/" . @account_ids);
}
$ui->noprogress;

@accounts = sort { lc($a->{'fullName'}{'firstName'}||"") cmp lc($b->{'fullName'}{'firstName'}||"") } @accounts;
@accounts = sort { lc($a->{'fullName'}{'lastName'}||"") cmp lc($b->{'fullName'}{'lastName'}||"") } @accounts;
my $listbox = $win->add("acctbox", 'Listbox',
	-values => [map {$_->{'id'}} @accounts],
	-labels => {map {$_->{'id'} => account_to_str($_, 1)} @accounts},
	-vscrollbar => 'right',
	-hscrollbar => 'bottom',
	-htmltext => 1,
);
$listbox->focus();

$win->set_binding(sub {
	if($allocate_listbox) {
		$allocate_listbox->hide();
		$accountwin->delete('sim_allocbox');
		$accountwin->focus();
		undef $allocate_listbox;
	} elsif($simwin) {
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

## ADD
$win->set_binding(sub {
	if($simwin) {
		# ignore
	} elsif($accountwin) {
		my $account_id = $accountwin->userdata();
		my @unallocated_sims = $lim->getUnallocatedSims();
		my $allocate_listbox = $accountwin->add('sim_allocbox', 'Listbox',
			-values => [map {$_->{'iccid'}} @unallocated_sims],
			-labels => {map {$_->{'iccid'} => sim_to_str($_, 0, 1)} @unallocated_sims},
			-vscrollbar => 'right',
			-hscrollbar => 'bottom',
			-htmltext => 1,
			-title => "Select a SIM to allocate",
		);
		$allocate_listbox->focus();
		$allocate_listbox->onChange(sub {
			my $sim_id = $allocate_listbox->get();
			$allocate_listbox->clear_selection();
			my $apn = "";
			my $cct = "";
			my $npt = "";
			$ui->leave_curses();
			until($apn eq "APN_NODATA" || $apn eq "APN_500MB" || $apn eq "APN_2000MB") {
				print "Valid inputs are: APN_NODATA, APN_500MB, APN_2000MB.\n";
				print "Internet / APN type? ";
				$apn = <STDIN>;
				1 while chomp $apn;
			}
			until($cct eq "DIY" || $cct eq "OOTB") {
				print "Valid inputs are: DIY, OOTB.\n";
				print "Call connectivity type? ";
				$cct = <STDIN>;
				1 while chomp $cct;
			}
			until($npt eq "true" || $npt eq "false") {
				print "Valid inputs are: true, false.\n";
				print "Will a number be ported immediately? ";
				$npt = <STDIN>;
				1 while chomp $npt;
			}
			if(!$lim->allocateSim(
				simIccid => $sim_id,
				ownerAccountId => $account_id,
				apn => $apn,
				callConnectivityType => $cct,
				numberPorting => $npt))
			{
				print "Allocation failed. Press enter to reinit.\n";
				<STDIN>;
			}
			$ui->reset_curses();
			goto reinit;
		});
	} else {
		$ui->leave_curses();
		print "Creating a new account.\n";
		my @vars = (
			["First name", "firstName"],
			["Last name", "lastName"],
			["Company name (or empty)", "companyName"],
			["E-mail address", "email"],
			["Street address", "streetAddress"],
			["Postal code", "postalCode"],
			["City / locality (, country)", "locality"],
		);
		my %opts;
		foreach(@vars) {
			print $_->[0] . "? ";
			my $var = <STDIN>;
			$var = decode_utf8($var);
			1 while chomp($var);
			$opts{$_->[1]} = $var;
		}
		my $account = $lim->createAccount(%opts) or die("Creating an account failed");
		$ui->reset_curses();
		goto reinit;
	}
}, "a");

## UPDATE
$win->set_binding(sub {
	if($simwin) {
		$ui->dialog("SIM updating is not possible yet.");
	} elsif($accountwin) {
		$ui->dialog("Account updating is not possible yet.");
	} else {
		# ignore
	}
}, "u");

$listbox->onChange(sub {
	my $account_id = $listbox->get();
	$listbox->clear_selection();
	my $account = $lim->getAccount($account_id);
	$accountwin = $win->add('subwin', 'Window',
		-border => 1,
		-bfg => "green",
		-userdata => $account_id,
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
		"External accounts: " . (%$ext ? join(", ", map { $ext->{$_} . " ($_)" } keys %$ext) : "(none)"),
		getAccountValidationLines($account->{'id'});

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
		my $csd = "Not started yet";
		if($sim->{'contractStartDate'}) {
			my (undef, undef, undef, $mday, $mon, $year) = localtime($sim->{'contractStartDate'} / 1000);
			$csd = sprintf("%4d-%02d-%02d", $year + 1900, $mon + 1, $mday);
		}
		my $owner = "(none)";
		if($sim->{'ownerAccountId'}) {
			$owner = account_to_str($lim->getAccount($sim->{'ownerAccountId'}), 0);
		}
		my $text = join "\n",
			"ICCID: " . $sim->{'iccid'},
			"PUK: " . $sim->{'puk'},
			"State: " . $sim->{'state'},
			"",
			"Contract start date: $csd",
			"Call connectivity type: " . $sim->{'callConnectivityType'},
			"Phone number: " . $sim->{'phoneNumber'},
			"Owner: $owner",
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

	my $marker = "   ";
	if($account->{'state'} eq "UNCONFIRMED") {
		$marker = "[U]";
	} elsif($account->{'state'} eq "CONFIRMATION_IMPOSSIBLE") {
		$marker = "[X]";
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

	return $marker . " " . $lim->account_to_str($account, $html);
}

sub sim_to_str {
	my ($sim, $with_account, $html) = @_;
	$with_account ||= 0;
	$html ||= 0;

	my $iccid = $sim->{'iccid'};

	my $marker = "";
	if($sim->{'state'} eq "STOCK") {
		return "Stock SIM, ICCID " . $iccid;
	} elsif($sim->{'state'} eq "ALLOCATED") {
		$marker = "[A]";
	} elsif($sim->{'state'} eq "ACTIVATION_REQUESTED") {
		$marker = "[Q]";
	} elsif($sim->{'state'} eq "DISABLED") {
		$marker = "[D]";
	}

	my $phonenr = $sim->{'phoneNumber'} || "(none)";
	if(!$sim->{'contractStartDate'}) {
		return "$marker no contract start date, number $phonenr, iccid $iccid";
	}
	my (undef, undef, undef, $mday, $mon, $year) = localtime($sim->{'contractStartDate'} / 1000);

	return sprintf("%s started %4d-%02d-%02d, number %s, iccid %s", $marker, $year+1900, $mon+1, $mday, $phonenr, $iccid);
}

sub getAccountValidationLines {
	my ($accountid) = @_;
	my @validation = $lim->getAccountValidation($accountid);
	return () if(@validation == 0);

	my @lines = ("");
	foreach(@validation) {
		push @lines, "!! Proposed change: ".$_->{'explanation'};
	}
	return @lines;
}
