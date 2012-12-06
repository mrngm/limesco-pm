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
$win->set_binding(sub {
	if($accountwin) {
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

	$accountwin->add('accountinfo', 'Label', -text => $text)->show();
	$accountwin->focus();
	$accountwin->show();
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
