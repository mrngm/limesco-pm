#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Net::Limesco;
use Net::Limesco::UI;

my ($user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 username password [hostname [port]]";
}

my $lim = Net::Limesco->new($hostname, $port);
if(!$lim->obtainToken($user, $pass)) {
	die "Couldn't obtain token";
}

my $ui = Curses::UI->new(-clear_on_exit => 1, -color_support => 1);
my $win = $ui->add('root', 'Window',
	-border => 1,
	-bfg => "red",
	-title => "");
$win->set_binding(sub { $ui->mainloopExit() }, "q");

my $limui = Net::Limesco::UI->new($lim, $ui, $win);
$win->title("List of accounts");
my ($listbox, $id) = $limui->list_of_account_ids(map { $_->{'id'} } $lim->getAllAccounts());
$listbox->focus();
$listbox->onChange(sub {
	my $account_id = $listbox->get();
	my $account = $lim->getAccount($account_id);
	$win->set_color_bfg("green");
	$win->title("Account view: " . $limui->account_to_str($account));
	my ($label, $label_id);
	$win->set_binding(sub {
		$label->hide();
		$win->delete($label_id);
		$listbox->show();
		$listbox->focus();
		$win->set_binding(sub { $ui->mainloopExit() }, "q");
	}, "q");
	$listbox->hide();
	($label, $label_id) = $limui->show_account($account);
	$label->show();
	$label->focus();
	$label->draw();
});

$ui->mainloop;
exit;
