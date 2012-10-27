#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Net::Limesco;
use Data::Dumper;

my ($hostname, $port) = @ARGV;

my $lim = Net::Limesco->new($hostname, $port, 1);
print Dumper($lim->getIssuers());
