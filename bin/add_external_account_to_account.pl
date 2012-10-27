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
	my @opts;
	for(qw(accountId serviceName remoteName)) {
		print "Enter value for '$_': ";
		my $value = <STDIN>;
		1 while chomp $value;
		push @opts, $value;
	}
	if($lim->addExternalAccountToAccount(@opts)) {
		print "Succesfully added.\n";
	} else {
		print "Failed to add.\n";
	}
}
