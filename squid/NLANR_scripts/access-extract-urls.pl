#!/usr/local/bin/perl

# access-extract-urls.pl,v 1.19 1996/06/02 03:41:43 wessels Exp
#
# This file is under RCS control in
#    /O1/Squid_Central/Scripts/RCS/access-extract-urls.pl,v
#
# This script is a special case subset of access-extract.pl because
# creating a hash of URLs eats up lots of memory.

$|=1;

$me = $0;
@F = split('/', $me); pop @F;
$medir = join ('/', @F);
$debug=0;

push (@INC, $medir);

require 'timelocal.pl';
require 'squid-logs.pl';

$usage = "usage: $me -h\n";

# Defaults
$HTTPDFormat = 0;
$MaxEntries = 50;

while (($#ARGV >=  $[) && ($ARGV[0] =~ /^-/) && ($_ = shift)) {
	if ($_ eq '-h') {
		$HTTPDFormat = 1;
	} else {
		warn "$me: $_: unknown option\n";
		die $usage;
	}
}

$CATS{'UR'} = $MaxEntries;

truncate('/var/tmp/UR_COUNT_ALLTCP.dir', 0);
truncate('/var/tmp/UR_COUNT_ALLTCP.pag', 0);
truncate('/var/tmp/UR_COUNT_ALLUDP.dir', 0);
truncate('/var/tmp/UR_COUNT_ALLUDP.pag', 0);
truncate('/var/tmp/UR_COUNT_ALL.dir', 0);
truncate('/var/tmp/UR_COUNT_ALL.pag', 0);

die "dbmopen: $!\n" unless
	dbmopen(%UR_COUNT_ALLTCP, '/var/tmp/UR_COUNT_ALLTCP', 0660);
die "dbmopen: $!\n" unless
	dbmopen(%UR_COUNT_ALLUDP, '/var/tmp/UR_COUNT_ALLUDP', 0660);
die "dbmopen: $!\n" unless
	dbmopen(%UR_COUNT_ALL, '/var/tmp/UR_COUNT_ALL', 0660);

$i = 0;
while (<>) {
	@F = $HTTPDFormat ? &parse_common_log($_) : split;
	next unless (@F);
        ($when,$elapsed,$who,$tag,$size,$method,$what,$id,$hier) = @F;
        ($tag,$code) = split('/', $tag);

	$count_tcp = $tag =~ /^TCP_/ ? 1 : 0;
	$count_udp = $tag =~ /^UDP_/ ? 1 : 0;
	next unless ($count_tcp || $count_udp);
        print "T=$when,E=$elapsed,A=$who,T=$tag,S=$size,M=$method,R=$what\n" if ($debug);

	next unless (length($what) < 1024);		# ndbm barfs on URLS >= 1024 chars

	$UR_COUNT_ALLTCP{$what} = $UR_COUNT_ALLTCP{$what}+1 if $count_tcp;
	$UR_COUNT_ALLUDP{$what} = $UR_COUNT_ALLUDP{$what}+1 if $count_udp;
	$UR_COUNT_ALL{$what} = $UR_COUNT_ALL{$what}+1;

	printf "# %d %d\n", time, $i if ($debug && ++$i % 10000 == 0);

}

while (($k,$v) = each %UR_COUNT_ALLTCP) {
	$ACOUNT{$v}++;
}

# memory efficient sort...
#
$max = $CATS{UR} - 1;
@counts = ();
while (($k,$v) = each %UR_COUNT_ALL) {
	next unless ($v > 1);

	#print "$v $k\n";
	push(@counts, $v);
	next unless ($#counts > ($max*20));

	#printf "# SORTING %d counts...\n", $#counts+1;
	@counts = sort { $b <=> $a } @counts;
	$#counts = $max;
	print "# COUNTS = ", join(' ', @counts), "\n" if ($debug);
}

printf "# SORTING %d counts...\n", $#counts+1;
@counts = sort { $b <=> $a } @counts;
print "# COUNTS = ", join(' ', @counts), "\n";

$thresh = $#counts > $max ? $counts[$max] : 0;
print "# THRESH %UR = $thresh\n";
@counts = undef;

# dump

while (($k,$v) = each %UR_COUNT_ALL) {
	next if ($v < $thresh);
	print "UR|$k|COUNT|ALL $v\n";
	print "UR|$k|COUNT|ALLTCP $UR_COUNT_ALLTCP{$k}\n"
		if defined $UR_COUNT_ALLTCP{$k};
	print "UR|$k|COUNT|ALLUDP $UR_COUNT_ALLUDP{$k}\n"
		if defined $UR_COUNT_ALLUDP{$k};
}

unlink "/var/tmp/UR_COUNT_ALLTCP.dir";
unlink "/var/tmp/UR_COUNT_ALLTCP.pag";
unlink "/var/tmp/UR_COUNT_ALLUDP.dir";
unlink "/var/tmp/UR_COUNT_ALLUDP.pag";
unlink "/var/tmp/UR_COUNT_ALL.dir";
unlink "/var/tmp/UR_COUNT_ALL.pag";

print "# Access histogram\n";
print "# AC|N number-of-objects-accessed-N-times\n";
while (($k,$v) = each %ACOUNT) {
	print "AC|$k $v\n";
}

exit 0;


sub request_count {
	local($h1) = @_;
	local($n) = 0;
	local($k1);
	local($k2);
	local($h2);

	foreach $k1 (keys %{$h1}) {
		next unless ($k1 eq 'COUNT');
		$h2 = \%{${$h1}{$k1}};
		foreach $k2 (keys %{$h2}) {
			next unless ($k2 =~ /^TCP_/ || $k2 =~ /^UDP_/);
			$n += ${$h2}{$k2};
		}
	}
	#print "request_count: returning $n\n";
	$n;
}
