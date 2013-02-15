#!/usr/bin/perl
use strict;
use warnings;
use lib "../lib";
use lib "lib";
use Net::Limesco;
use OpenOffice::OODoc;
use Cwd qw(realpath);

my ($ott, $iccid, $user, $pass, $hostname, $port) = @ARGV;
if(!defined($pass)) {
	die "Usage: $0 OTTfile iccid username password [hostname [port]]";
}

my $lim = Net::Limesco->new($hostname, $port, 1);
if(!$lim->obtainToken($user, $pass)) {
	die "Unable to obtain token as user $user.\n";
}

my $sim = $lim->getSim($iccid) or die $!;
my $account = $lim->getAccount($sim->{'ownerAccountId'}) or die $!;

my $oofile = odfContainer($ott) or die $!;
my $content = odfDocument(
	container => $oofile,
	part => 'content'
);

my $root = $content->getBody;

sub c {
	my ($a, @items) = @_;
	while(@items > 1) {
		$a = $a->{shift @items};
	}
	return $content->outputTextConversion($a->{shift @items});
}
sub a {
	return c($account, @_);
}
sub S {
	return c($sim, @_);
}

$content->replaceText($root, "%FIRSTNAME%", a("fullName", "firstName"));
$content->replaceText($root, "%LASTNAME%", a("fullName", "lastName"));
$content->replaceText($root, "%STREET%", a("address", "streetAddress"));
$content->replaceText($root, "%POSTALCODE%", a("address", "postalCode"));
$content->replaceText($root, "%LOCALITY%", a("address", "locality"));

my (undef, undef, undef, $mday, $mon, $year) = localtime(time());
my @months = qw(januari februari maart april mei juni juli augustus
	september oktober november december);

$content->replaceText($root, "%DATE%",
	sprintf("%02d %s %4d", $mday, $months[$mon], $year + 1900));
$content->replaceText($root, "%ICCID%", S("iccid"));
$content->replaceText($root, "%PUK%", S("puk"));

my $filename = sprintf("limesco-%s.odt", $sim->{'iccid'});
$oofile->save($filename) or die $!;
print "Wrote to " . realpath($filename) . "\n";
