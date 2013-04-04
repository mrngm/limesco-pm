#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Encode;
use Curses;
use Curses::UI;
use Net::Limesco;
use Term::Menu;
use Test::Deep::NoTest;
use Data::Dumper;

my ($user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 username password [hostname [port]]";
}

open STDERR, '>', "ui.log" or die $!;
my $lim = Net::Limesco->new($hostname, $port, 1 && sub { print STDERR $_[0] });
if(!$lim->obtainToken($user, $pass)) {
	die "Couldn't obtain token";
}

my $ui = Curses::UI->new(-clear_on_exit => 1,
	-color_support => 1,
	-mouse_support => 0);

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
#$ui->progress(-max => 1, -message => "Loading account information...");
#my @accounts = ();
#foreach(@account_ids) {
#	push @accounts, $lim->getAccount($_);
#	$ui->setprogress(@accounts/@account_ids, "Loading accounts... " . @accounts . "/" . @account_ids);
#}
#$ui->noprogress;
my @accounts = $lim->getAllAccounts();

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
	if($allocate_listbox) {
		# ignore
	} elsif($simwin) {
		# ignore
	} elsif($accountwin) {
		my $account_id = $accountwin->userdata();
		my @unallocated_sims = $lim->getUnallocatedSims();
		if(@unallocated_sims == 0) {
			$ui->dialog("There are no unallocated SIMs to allocate.");
			return;
		}
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
	if($allocate_listbox) {
		# ignore
	} elsif($simwin) {
		$ui->leave_curses();
		my $simid = $simwin->userdata();
		update_sim($simid);
		$ui->reset_curses();
		goto reinit;
	} elsif($accountwin) {
		$ui->leave_curses();
		my $accountid = $accountwin->userdata();
		update_account($accountid);
		$ui->reset_curses();
		goto reinit;
	} else {
		# ignore
	}
}, "u", "e");

$listbox->onChange(sub {
	my $account_id = $listbox->get();
	$listbox->clear_selection();
	my $account = $lim->getAccount($account_id);
	$accountwin = $win->add('subwin', 'Window',
		-border => 1,
		-bfg => "green",
		-userdata => $account_id,
		-title => "Account view: " . account_to_str($account));

	my @sims = sort { $a->{'iccid'} <=> $b->{'iccid'} } $lim->getSimsByOwnerId($account_id);

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
			-userdata => $sim_id,
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
		my @sipsettings = "(No SIP settings found in this SIM)";
		if($sim->{'sipSettings'}) {
			my $s = $sim->{'sipSettings'};
			@sipsettings = (
				"Realm: " . $s->{'realm'},
				"Username: " . $s->{'username'},
				"Authentication username: " . $s->{'authenticationUsername'},
				"Password: " . $s->{'password'},
				"URI: " . $s->{'uri'},
				"Expiry: " . $s->{'expiry'},
				"SpeakUp trunk password: " . $s->{'speakupTrunkPassword'}
			);
		}
		my $lmfi = "(none)";
		if($sim->{'lastMonthlyFeesInvoice'}) {
			my $i = $sim->{'lastMonthlyFeesInvoice'};
			$lmfi = sprintf("At %02d-%04d: %s", $i->{'year'}, $i->{'month'}, $i->{'invoiceId'});
		}
		my $text = join "\n",
			"ICCID: " . $sim->{'iccid'},
			"PUK: " . $sim->{'puk'},
			"State: " . $sim->{'state'},
			"",
			"Contract start date: $csd",
			"Call connectivity type: " . $sim->{'callConnectivityType'},
			"Phone number: " . $sim->{'phoneNumber'},
			"Porting state: " . $sim->{'portingState'},
			"Owner: $owner",
			"APN type: " . $sim->{'apnType'},
			"Exempt from cost contribution: " . $sim->{'exemptFromCostContribution'},
			"Activation invoice ID: " . $sim->{'activationInvoiceId'},
			"Last monthly fees invoice: $lmfi",
			"",
			@sipsettings;
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
	if($account->{'state'} eq "UNPAID") {
		$marker = "[P]";
	} elsif($account->{'state'} eq "UNCONFIRMED") {
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

	my $marker = "   ";
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

sub update_account {
	my ($accountid) = @_;
	my $account = $lim->getAccount($accountid);
	return if(!$account);
	# Two types of account updates are available: updates suggested by the API,
	# and direct field updates.
	# Updates suggested by the API might spawn third actions to take, such as
	# sending an e-mail. They may also cause direct field updates. When the
	# updates are explicitly confirmed, the field updates are written into the
	# Account object and sent back to the API, which will save them into the
	# database.
	my @suggested = $lim->getAccountValidation($accountid);
	my $suggested = [map {[0, $_]} @suggested];
	my $updates = {};
	warn Dumper($account);
	update_object_step("account", $account, $suggested, $updates);
	return if(keys %$updates == 0);
	if(!eq_deeply($account, $lim->getAccount($accountid))) {
		warn "WARNING: Account changed during process, refusing to process changes.\n";
		warn Dumper($updates);
		die "Fatal error.\n";
	}
	warn "Old account:\n";
	warn Dumper($account);
	warn "\n";
	recursive_update($account, $updates);
	warn "New account:\n";
	warn Dumper($account);
	warn "\n";
	$lim->saveAccount($account);
}

sub update_sim {
	my ($simid) = @_;
	my $sim = $lim->getSim($simid);
	return if(!$sim);
	my @suggested = $lim->getSimValidation($simid);
	my $suggested = [map {[0, $_]} @suggested];
	my $updates = {};
	warn Dumper($sim);
	update_object_step("sim", $sim, $suggested, $updates);
	return if(keys %$updates == 0);
	if(!eq_deeply($sim, $lim->getSim($simid))) {
		warn "WARNING: SIM changed during process, refusing to process changes.\n";
		warn Dumper($updates);
		die "Fatal error.\n";
	}
	warn "Old SIM:\n";
	warn Dumper($sim);
	warn "\n";
	recursive_update($sim, $updates);
	warn "New SIM:\n";
	warn Dumper($sim);
	warn "\n";
	$lim->saveSim($sim);
}

sub recursive_update {
	my ($a, $b) = @_;
	foreach(keys %$b) {
		my $u = $b->{$_};
		if(ref($u)) {
			die "Only able to process hashes in recursive_update" if(ref($u) ne "HASH");
			$a->{$_} ||= {};
			recursive_update($a->{$_}, $b->{$_});
		} else {
			$a->{$_} = $b->{$_};
		}
	}
}

sub update_object_step {
	my ($type, $object, $suggested, $proposed_updates) = @_;

	system 'clear';

	if(%$proposed_updates) {
		print "Planned updates:\n";
		foreach(keys %$proposed_updates) {
			my $u = $proposed_updates->{$_};
			$u .= "\n" if(!ref($u));
			$u = Dumper($u) if(ref($u));
			print "  $_ => $u";
		}
	}

	my $prompt = Term::Menu->new(
		beforetext => "Available actions:",
		aftertext => "Select an action: ");

	my $choices = 0;
	my %options;

	for(my $i = 0; $i < @$suggested; ++$i) {
		my ($rerun, $suggestion) = @{$suggested->[$i]};
		my $title = ($rerun ? "Re-run suggested: " : "Suggested: ") . $suggestion->{'explanation'};
		$options{'sugg_' . $i} = [$title, ++$choices];
	}

	$options{'specific'} = ["Update specific field", ++$choices];

	my $answer = $prompt->menu(
		write  => ["Write updates", "w"],
		cancel => ["Cancel updates", "c"],
		%options
	);
	print "\n";
	if($answer eq "write") {
		return;
	} elsif($answer eq "cancel") {
		for(keys %$proposed_updates) {
			delete $proposed_updates->{$_};
		}
		return;
	} elsif($answer eq "specific") {
		$prompt = Term::Menu->new(
			beforetext => "What field to update?",
			aftertext => "Select an action: ");
		$choices = 0;
		%options = ();
		foreach(keys %$object) {
			next if($_ eq "id");
			$options{'opt_' . $_} = [$_, ++$choices];
		}
		$answer = $prompt->menu(
			cancel => ["Cancel update", "c"],
			%options);
		print "\n";
		if($answer eq "cancel") {
			# do nothing
		} elsif($answer =~ /^opt_(.+)$/) {
			# update field $1
			run_object_field_update($type, $object, $proposed_updates, $1);
		} else {
			die "Unexpected answer from menu";
		}
	} elsif($answer =~ /^sugg_(\d+)$/) {
		my ($suggestion) = $suggested->[$1][1];
		if(run_object_suggestion($type, $object, $proposed_updates, $suggestion)) {
			$suggested->[$1][0] = 1;
		}
	} else {
		die "Unexpected answer from menu";
	}
	print "\n\nReturning to menu...\n";
	sleep 1;
	return update_object_step($type, $object, $suggested, $proposed_updates);
}

sub run_object_suggestion {
	my ($type, $object, $proposed_updates, $suggestion) = @_;
	print "Running suggestion " . $suggestion->{'identifier'} . ": " . $suggestion->{'explanation'} . "\n";
	if($type eq "account") {
		print "On Account: " . account_to_str($object) . "\n\n";
	} elsif($type eq "sim") {
		print "On SIM: " . sim_to_str($object) . "\n\n";
		my $account = $lim->getAccount($object->{'ownerAccountId'});
		print "Of Account: " . account_to_str($account) . "\n\n";
	} else {
		die "Unknown object type";
	}
	my $ran_succesfully = 1;

	my $these_proposed_updates = $suggestion->{'changes'};
	if($type eq "account" && $suggestion->{'identifier'} eq "ASK_CONFIRMATION") {
		print "Send the following e-mail: \n\n";
		print join "\n",
			"Dag " . ($object->{'fullName'}{'firstName'}) . ",",
			"",
			"Je inschrijving bij Limesco is ontvangen. Welkom!",
			"",
			"Graag zouden wij je willen vragen om de gegevens hieronder te bevestigen, of indien nodig te corrigeren. Voorlopig doen we dat nog even handmatig met een reply op deze e-mail, omdat de geautomatiseerde infrastructuur nog niet af is.",
			"",
			"Naam: " . ($object->{'fullName'}{'firstName'} || "") . " " . ($object->{'fullName'}{'lastName'} || ""),
			"Eventuele bedrijfsnaam voor facturering: (geen)",
			"Adres: ",
			"    " . ($object->{'address'}{'streetAddress'} || ""),
			"    " . ($object->{'address'}{'postalCode'} || "") . " " . ($object->{'address'}{'locality'} || ""),
			"Type abonnement: Out-of-the-box",
			"  (De andere optie is 'Do it yourself', waarbij je verkeer langs een telefooncentrale loopt. Als je die optie kiest, vragen we later nog om extra accountgegevens.)",
			"Data-abonnement:",
			"",
			"Ik wil mijn telefoonnummer naar Limesco porteren: ja/nee",
			"Type nummer: zakelijk / prive / prepaid",
			"Te porteren nummer: ",
			"Huidige provider:",
			"SIM-kaartnummer bij huidige provider:",
			"Klantnummer bij huidige provider:",
			"Einddatum contract bij huidige provider:",
			"",
			"";
		print "Press ENTER when that's done... ";
		<STDIN>;
	} elsif($type eq "sim" && $suggestion->{'identifier'} eq "REQUEST_ACTIVATION") {
		print "Log in to the SpeakUp portal at https://portal.speakup.nl/\n";
		print "Click 'Order mobile number for new whitelabel customer'\n\n";
		my $a = $lim->getAccount($object->{'ownerAccountId'});
		print "Enter customer data:\n";
		print "Name: " . ($a->{'companyName'} ? $a->{'companyName'} : ($a->{'fullName'}{'firstName'} . " " . $a->{'fullName'}{'lastName'})) . "\n";
		print "Street + nr + addition: " . $a->{'address'}{'streetAddress'} . "\n";
		print "Zipcode + City: " . $a->{'address'}{'postalCode'} . " " . $a->{'address'}{'locality'} . "\n";
		print "\n";
		my $is_ootb = $object->{'callConnectivityType'} eq "OOTB";
		print "Order Type: " . ($is_ootb ? "Mobile" : "Mobile On PBX") . "\n";
		print "Subscription Type: " . ($is_ootb ? "Pay as you go" : "PBX Lite") . "\n";
		my $data = $object->{'apnType'};
		print "Data-Package: " . (
			$data eq "APN_NODATA" ? "No Data" :
				$data eq "APN_500MB" ? "500 MB" : "2000 MB")
			. "\n";
		print "Comment: " . $object->{'iccid'} . "\n";
		my $port = $object->{'portingState'} ne "NO_PORT";
		print "Port Existing Number: " . ($port ? "Yes" : "No") . "\n";
		if($port) {
			print "Enter porting number as in confirmation e-mail\n";
		}

		print "\nPress ENTER when that's done...\n";
		<STDIN>;
	} elsif($type eq "sim" && $suggestion->{'identifier'} eq "PROCESS_ACTIVATION") {
		my $port = $object->{'portingState'} ne "NO_PORT";
		print "Enter " . ($port?"temporary":"new") . " telephone number: ";
		my $phone = <STDIN>;
		1 while chomp($phone);
		$phone =~ s/-//g;
		$phone =~ s/^0031/31/g;
		$phone =~ s/^0/31/g;

		$these_proposed_updates->{phoneNumber} = $phone;

		# TODO: porting state
		if($port) {
			# TODO: update porting state
			# set contractStartDate to porting date
		} else {
			use Time::Local;
			my @timefields = localtime();
			pop @timefields; # isdst
			pop @timefields; # yday
			pop @timefields; # wday
			$timefields[0] = $timefields[1] = $timefields[2] = 0; # date only
			$these_proposed_updates->{contractStartDate} = timelocal(@timefields) * 1000;
		}

		my $phone_human = $phone;
		if($phone_human =~ /^316(\d{8})/) {
			$phone_human = "06-$1";
		}

		my $a = $lim->getAccount($object->{'ownerAccountId'});
		print "Updates are prepared. Send a reply to the original activation e-mail/ticket:";
		print "\n\n";
		print "Hallo " . $a->{'fullName'}{'firstName'} . ",\n\n";
		print "Je SIM is geactiveerd en heeft als " . ($port?"tijdelijk ":"nieuw ");
		print "telefoonnummer $phone_human gekregen.";

		if($object->{'apnType'} ne "APN_NODATA") {
			print " Voor het gebruiken van je databundel moet je wellicht je telefoon nog instellen; kijk voor de benodigde instellingen op <https://secure.limesco.nl/wiki/Telefooninstellingen>.";
		}

		if($port) {
			# TODO: porteergegevens
			print "\n\nEr zal een portering plaatsvinden.";
		}

		print "\n\n";
		print 'Stuur bij problemen met je SIM of voor feedback of suggesties een mailtje naar support@limesco.nl. Veel plezier met je Limesco SIM!';

		print "\n\n\nPress ENTER when that's done...\n";
		<STDIN>;
	} else {
		print "Warning: Unchecked suggestion.\n";
	}

	print "\n";

	if(%$these_proposed_updates == 0) {
		print "No updates for this suggestion. Press ENTER to continue.\n";
		<STDIN>;
		return $ran_succesfully;
	}

	print "Updates that will be added to planned updates:\n";
	foreach(keys %$these_proposed_updates) {
		print "  $_ => " . $these_proposed_updates->{$_} . "\n";
	}
	my $prompt = Term::Menu->new(
		beforetext => "Add these updates?",
		aftertext => "Select an action: ");
	my $answer = $prompt->menu(
		1 => ["Yes", "y"],
		0 => ["No", "n"]);
	if($answer) {
		foreach(keys %$these_proposed_updates) {
			$proposed_updates->{$_} = $these_proposed_updates->{$_};
		}
		return 1;
	}
	return 0;
}

sub run_object_field_update {
	my ($type, $object, $proposed_updates, $field) = @_;

	my %closed_choices;
	my %hashmaps;
	my @date_fields;

	if($type eq "account") {
		%closed_choices = (
			state => [qw(UNPAID UNCONFIRMED CONFIRMATION_REQUESTED CONFIRMED CONFIRMATION_IMPOSSIBLE DEACTIVATED)],
		);
		%hashmaps = (
			fullName => [qw(firstName lastName)],
			address  => [qw(streetAddress postalCode locality)],
			externalAccounts => [qw(speakup)],
		);
	} elsif($type eq "sim") {
		%closed_choices = (
			state => [qw(STOCK ALLOCATED ACTIVATION_REQUESTED ACTIVATED DISABLED)],
			apnType => [qw(APN_NODATA APN_500MB APN_2000MB)],
			portingState => [qw(NO_PORT WILL_PORT PORT_PENDING PORT_DATE_KNOWN PORTING_COMPLETED)],
			exemptFromCostContribution => [qw(true false)],
			callConnectivityType => [qw(OOTB DIY)],
		);
		%hashmaps = (
			sipSettings => [qw(realm username authenticationUsername password uri expiry)],
			lastMonthlyFeesInvoice => [qw(year month invoiceId)],
		);
		@date_fields = qw(contractStartDate);
	} else {
		die "Unknown type";
	}
	my @closed_options = keys %closed_choices;
	my @hashmap_options = keys %hashmaps;

	if(ref($object->{$field}) && !($field ~~ @hashmap_options)) {
		print "Unable to update field $field: it's a complex structure.\n";
		return;
	}
	print "Updating field $field.\n";
	my $curval = $object->{$field};
	$curval = Dumper($curval) if(ref($curval));
	print "Current value: $curval\n";
	if(exists $proposed_updates->{$field}) {
		my $planupd = $proposed_updates->{$field};
		$planupd = Dumper($planupd) if(ref($planupd));
		print "Planned update: $planupd\n";
	}
	
	if($field ~~ @closed_options) {
		my $prompt = Term::Menu->new(
			beforetext => "Set it to?",
			aftertext => "Select an action: ");
		my %options;
		my $count = 0;
		foreach(@{$closed_choices{$field}}) {
			$options{'opt_' . $_} = [$_, ++$count];
		}
		my $answer = $prompt->menu(
			"cancel" => ["Cancel", "c"],
			%options
		);
		if($answer eq "cancel") {
			# ignore
		} elsif($answer =~ /^opt_(.+)$/) {
			$proposed_updates->{$field} = $1;
		} else {
			die "Unexpected answer from menu";
		}
	} elsif($field ~~ @hashmap_options) {
		my @subfields = @{$hashmaps{$field}};
		my $prompt = Term::Menu->new(
			beforetext => "Set what subfield?",
			aftertext => "Select an action: ");
		my %options;
		$options{$_} = [$subfields[$_-1], $_] for(1 .. @subfields);
		my $answer = $prompt->menu(
			q => ["Cancel action", "q"],
			%options
		);
		if(!$answer || $answer eq "q") {
			return;
		}
		my $subfield = $subfields[$answer-1];
		if(!defined($subfield)) {
			die "Unexpected answer from menu";
		}
		print "\nEnter a new value for field ".$field."->$subfield, or underscore ('_') to cancel:\n";
		my $value = <STDIN>;
		$value = decode_utf8($value);
		1 while chomp($value);
		if($value ne "_") {
			$proposed_updates->{$field}{$subfield} = $value;
		}
	} elsif($field ~~ @date_fields) {
		print "Enter a date, in the format YYYY-MM-DD (i.e. 2012-10-13), or nothing to cancel:\n";
		my $value = <STDIN>;
		1 while chomp($value);
		use Time::Local;
		if($value =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
			$proposed_updates->{$field} = timelocal(0, 0, 0, $3, $2-1, $1-1900) * 1000;
		} else {
			print "That's not valid input.\n";
		}
	} else {
		# Open choice
		print "Enter a new value, or underscore ('_') to cancel:\n";
		my $value = <STDIN>;
		$value = decode_utf8($value);
		1 while chomp($value);
		if($value ne "_") {
			$proposed_updates->{$field} = $value;
		}
	}
}
