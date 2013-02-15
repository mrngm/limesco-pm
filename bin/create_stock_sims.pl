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
	print "On every line, enter an ICCID and a PUK, separated by spaces. End with EOF or an empty line.\n";
	my @list;
	while(<STDIN>) {
		1 while chomp;
		last if($_ eq "");
		my ($iccid, $puk) = /^(\d+) (\d+)$/;
		push @list, [$iccid, $puk];
	}

	foreach(@list) {
		$lim->createSim(iccid => $_->[0], puk => $_->[1], state => "STOCK");
	}
}
