#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Net::Limesco;
use Data::Dumper;

my ($user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 username password [hostname [port]]";
}

my $lim = Net::Limesco->new($hostname, $port, 1);
if($lim->obtainToken($user, $pass)) {
	my %opts;
	for(qw(accountId currency paymentType destination transactionId amount status)) {
		print "Enter value for '$_': ";
		my $value = <STDIN>;
		1 while chomp $value;
		$opts{$_} = $value;
	}
	my @invoiceIds;
	while(1) {
		print "Enter an invoice id, stop with an empty line: ";
		my $value = <STDIN>;
		1 while chomp $value;
		last if($value eq "");
		push @invoiceIds, $value;
	}
	$opts{invoiceIds} = \@invoiceIds;
	$lim->createPayment(%opts);
}
