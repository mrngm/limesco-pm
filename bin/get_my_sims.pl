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
	print Dumper($lim->getMySims());
}
