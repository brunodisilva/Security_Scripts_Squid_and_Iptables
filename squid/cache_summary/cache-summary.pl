#!/usr/local/bin/perl

# cache-summary.pl,v 1.4 1996/05/08 18:32:20 wessels Exp
#
# This file is under RCS control in
#    /O1/Squid_Central/Scripts/RCS/cache-summary.pl,v
#
$DATADIR = '/usr/local/etc/httpd/htdocs/Cache/Statistics/Data';

$me = $0;
@F = split('/', $me); pop @F;
$medir = join ('/', @F);

push (@INC, $medir);

require 'squid-logs.pl';
require 'getopts.pl';

$TopN = 10;

&Getopts('n:d:');
$TopN = $opt_n if (defined($opt_n));
$DATADIR = $opt_d if (defined $opt_d);

$sdate = shift || die "usage: $me -n N -d data_dir yymmdd caches...\n";
$yymm  = int($sdate / 100);

print "IRCache daily summary report for $sdate\n";
print "\n";
print "Site statistics files from:\n";
print "\n";

foreach $cache (@ARGV) {
	$DATA = "$DATADIR/$cache/$yymm/access.$sdate";
	next unless open DATA;
	print "  $cache\n";
	($CK,@X) = split ('\.', $cache);	# "CK" == 'cache key'
	push (@CKlist, $CK);

	while (<DATA>) {
	chop;
	next if (/^#/);
	($longkey,$val) = split;
	($cat,$key,$cs,$tag) = split(/\|/, $longkey);
	${$CK}{$cat}{$key}{$cs}{$tag} += $val;

	if ($cat eq 'TO') {	# TOTAL, special case
		$TCP_TOTAL_COUNT += $val if ($key eq 'TCP' && $cs eq 'REQUESTS');
		$UDP_TOTAL_COUNT += $val if ($key eq 'UDP' && $cs eq 'REQUESTS');
		$TCP_TOTAL_BYTES += ($val/1024) if ($key eq 'TCP' && $cs eq 'BYTES');
		next;
	}

	if ($cat eq 'TIMESTAMP') {	# TIMESTAMP, special case
		$FIRST = $val if ($key eq 'FIRST');
		$LAST = $val if ($key eq 'LAST');
		next;
	}

	if ($cat eq 'CL' && $cs eq 'COUNT') {
		$TAGS{$tag}++;
		$TAGM{$CK}{$tag} += $val;
		$ALL{$CK}{ALLTCP} += $val if ($tag =~ /^TCP_/);
		$ALL{$CK}{TCPHIT} += $val if ($tag =~ /TCP_.*HIT/);
		$ALL{$CK}{ALLUDP} += $val if ($tag =~ /^UDP_/);
	}
	if ($cat eq 'CL' && $cs eq 'BYTES') {
		$ALL{$CK}{BYTES} += $val if ($tag =~ /^TCP_/);
		$ALL{$CK}{CACHEDBYTES} += $val if ($tag =~ /TCP_.*HIT/);
	}
	if ($cs eq 'COUNT') {
		${$cat}{$key} += $val if ($tag =~ /^TCP_/);
	}
	if ($cs eq 'BYTES') {
		${$cat.'B'}{$key} += ($val / 1024) if ($tag =~ /^TCP_/);
	}
	}
	close DATA;

}
print "\n";

print "Summary Statistics:\n\n";

printf "%16.16s", '';
foreach $CK (@CKlist) {
	printf " %7s", $CK;
}
print "\n";

print "HTTP Requests  :";
foreach $CK (@CKlist) {
	printf " %7d", $ALL{$CK}{ALLTCP};
}
print "\n";

print "ICP Requests   :";
foreach $CK (@CKlist) {
	printf " %7d", $ALL{$CK}{ALLUDP};
}
print "\n";

print "HTTP:ICP Ratio :";
foreach $CK (@CKlist) {
	if ($ALL{$CK}{ALLUDP}) {
		printf " %7.1f", $ALL{$CK}{ALLTCP} / $ALL{$CK}{ALLUDP};
	} else {
		printf " %7s", '-';
	}
}
print "\n";

print "Hit rate (docs):";
foreach $CK (@CKlist) {
	if ($ALL{$CK}{ALLTCP}) {
		printf " %6d%%", 100 * $ALL{$CK}{TCPHIT}/$ALL{$CK}{ALLTCP}+0.5;
	} else {
		printf " %7s", '-';
	}
}
print "\n";

print "MB served (all):";
foreach $CK (@CKlist) {
	printf " %7d", $ALL{$CK}{BYTES} / (1<<20);
}
print "\n";

print "MB served cache:";
foreach $CK (@CKlist) {
	printf " %7d", $ALL{$CK}{CACHEDBYTES} / (1<<20);
}
print "\n";

print "Percent Savings:";
foreach $CK (@CKlist) {
	if ($ALL{$CK}{BYTES}) {
		printf " %6d%%",
			100 * $ALL{$CK}{CACHEDBYTES}/$ALL{$CK}{BYTES}+0.5;
	} else {
		printf " %7s", '-';
	}
}
print "\n";

print "\n";

print "Access Type Matrix:\n\n";
printf "%16.16s", '';
foreach $CK (@CKlist) {
	printf " %7s", $CK;
}
print "\n";
foreach $tag (sort keys %TAGS) {
	printf "%16.16s", $tag;
	foreach $CK (@CKlist) {
		printf " %7d", $TAGM{$CK}{$tag};
	}
	print "\n";
}
print "\n";

$i = 0;
print "Top $TopN Clients:\n\n";
foreach $key (sort {$CL{$b} <=> $CL{$a}} keys %CL) {
	printf "   %7d  %-16s %s\n", $CL{$key}, $key, &fqdn($key);
	last if (++$i == $TopN);
}
print "\n";

$i = 0;
print "Top $TopN Servers:\n\n";
foreach $key (sort {$SE{$b} <=> $SE{$a}} keys %SE) {
	printf "   %7d  %s\n", $SE{$key}, $key;
	last if (++$i == $TopN);
}
print "\n";

$i = 0;
print "Top $TopN Object Types:\n\n";
foreach $key (sort {$TY{$b} <=> $TY{$a}} keys %TY) {
	printf "   %7d %2d%% %-12.12s  %9d kbytes %2d%%  %7d bytes/obj\n",
		$TY{$key},
		100 * $TY{$key} / $TCP_TOTAL_COUNT + 0.5,
		$key,
		$TYB{$key},
		100 * $TYB{$key} / $TCP_TOTAL_BYTES + 0.5,
		($TYB{$key}/$TY{$key}) * 1024;
	last if (++$i == $TopN);
}
print "\n";

