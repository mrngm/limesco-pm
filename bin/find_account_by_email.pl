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
	while(1) {
		print "Enter an e-mail address (empty line to stop)? ";
		my $e = <STDIN>;
		1 while chomp $e;
		last if($e eq "");
		print Dumper($lim->findAccountsBy(email => $e));
	}
}
