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
	for(qw(iccid puk state contractStartDate phoneNumber sipRealm sipUsername
	sipUri sipAuthenticationUsername sipPassword sipExpiry ownerAccountId
	callConnectivityType apnType activationInvoiceId lastMonthlyFeesInvoice)) {
		print "Enter value for '$_': ";
		my $value = <STDIN>;
		1 while chomp $value;
		$opts{$_} = $value if $value;
	}
	$lim->createSim(%opts);
}
