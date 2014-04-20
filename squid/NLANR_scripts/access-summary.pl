#!/usr/local/bin/perl

# access-summary.pl,v 1.24 1996/08/22 16:03:20 wessels Exp
#
# This file is under RCS control in
#    /O1/Squid_Central/Scripts/RCS/access-summary.pl,v
#

#length of the name entry for hosts
$namelength=23;

$me = $0;
@F = split('/', $me); pop @F;
$medir = join ('/', @F);

push (@INC, $medir);

require 'squid-logs.pl';
require 'getopts.pl';

@NLANR_names = ('IT','PB','UC','BO','SV','SD','DC','localhost');

$UDP_TOTAL_COUNT = 0;
$TCP_TOTAL_COUNT = 0;
$TCP_TOTAL_BYTES = 0;

$TopN = 25;

&Getopts('n:');
$TopN = $opt_n if (defined($opt_n));


while (<>) {
	chop;
	next if (/^#/);
	($longkey,$val) = split;
	($cat,$key,$cs,$tag) = split(/\|/, $longkey);
	next if ($tag eq 'TCP_DONE');	# so this might work on older summaries
	${$cat}{$key}{$cs}{$tag} += $val;


	if ($cat eq 'TO') {	# TOTAL, special case
		$TCP_TOTAL_COUNT = $val if ($key eq 'TCP' && $cs eq 'REQUESTS');
		$UDP_TOTAL_COUNT = $val if ($key eq 'UDP' && $cs eq 'REQUESTS');
		$TCP_TOTAL_BYTES = $val if ($key eq 'TCP' && $cs eq 'BYTES');
		next;
	} elsif ($cat eq 'AC') {
		$ACOUNT{$key} = $val;
	}

	if ($cat eq 'TIMESTAMP') {	# TIMESTAMP, special case
		$FIRST = $val if ($key eq 'FIRST');
		$LAST = $val if ($key eq 'LAST');
		next;
	}

	${$cat}{$key}{$cs}{'TCP'} += $val
		if (($tag =~ /^TCP_/) && ($cs eq 'COUNT'));
	${$cat}{$key}{$cs}{'UDP'} += $val
		if (($tag =~ /^UDP_/) && ($cs eq 'COUNT'));
	${$cat}{$key}{$cs}{'ALL'} += $val
		if (($tag =~ /^TCP_/ || $tag =~ /^UDP_/) && ($cs eq 'COUNT'));
	${$cat}{$key}{$cs}{'ALL'} += $val
		if ($tag =~ /^TCP_/ && ($cs eq 'BYTES'));

}


sub xsort {
	local($href) = @_;
	local(@keys) = keys %{$href};
	sort { ${$href}{$b}{COUNT}{ALL} <=> ${$href}{$a}{COUNT}{ALL} } @keys;
}

sub aksort {
	local($href,$AK) = @_;	#	AK = "all-key"
	local(@keys) = keys %{$href};
	sort { ${$href}{$b}{COUNT}{$AK} <=> ${$href}{$a}{COUNT}{$AK} } @keys;
}

sub clsort {
	local($href) = @_;
	local(@keys) = keys %{$href};
	local(@keys1) = ();
	local(@keys2) = ();
	local($key);
	local($fqdn);
	local($x);
	foreach $key (@keys) {
		$fqdn = &fqdn($key);
		if (grep(/$fqdn/, @NLANR_names)) {
			push (@keys1, $key);
		} else {
			push (@keys2, $key);
		}
	}
	@keys1 = sort { ${$href}{$b}{COUNT}{ALL} <=> ${$href}{$a}{COUNT}{ALL} } @keys1;
	@keys2 = sort { ${$href}{$b}{COUNT}{ALL} <=> ${$href}{$a}{COUNT}{ALL} } @keys2;
	#print "RETURNING ", join (' ', (@keys1, 'BREAK', @keys2)), "\n";
	(@keys1, 'BREAK', @keys2);
}

print "FIRST ACCESS: ", &strtime($FIRST), "\n";
print " LAST ACCESS: ", &strtime($LAST), "\n";
print "\n";


&table_table('Method', 'SUMMARY OF REQUEST METHOD USAGE', \%ME,
	\&xsort,undef,undef);
&table_table('Protocol', 'SUMMARY OF PROTOCOL USAGE', \%PR,
	\&xsort,undef,undef);
&table_table('Client',   'SUMMARY OF CLIENT USAGE',   \%CL,
	\&clsort,\&rev_fqdn,$TopN);
&table_table('Server',   'SUMMARY OF SERVER USAGE',   \%SE,
	\&xsort,\&rev_server,$TopN);
&table_table('Type',     'SUMMARY OF URL TYPES',      \%TY,
	\&xsort,undef,undef);
&table_table('Domain',   'SUMMARY OF URL TOP-LEVEL DOMAINS', \%DO,
	\&xsort,\&top_domain_name,undef);

&utilization_table('Client',   'CLIENT UTILIZATION', \%CL,
	undef,\&rev_fqdn,undef);

&access_count_hist;

&list_top('URL', "TOP $TopN HTTP Reqeusts", \%UR,
	\&aksort, undef, $TopN, 'ALLTCP');
&list_top('URL', "TOP $TopN ICP Reqeusts",  \%UR,
	\&aksort, undef, $TopN, 'ALLUDP');

&print_chart(\%TI, 'Request Distribution HTTP requests per half hour', 'TCP');
&print_chart(\%TI, 'Request Distribution ICP requests per half hour', 'UDP');
&print_chart(\%TI, 'Request Distribution, combined HTTP and ICP requests, perhalf hour', 'ALL');

exit 0;

##############################################################################

sub table_table {
	local($name,$title,$hash,$sortproc,$keyprint,$N) = @_;
	local($h1);

	print "\n", &center($title), "\n\n";
	&table_header($name);
	&table_dashes();
	foreach $p (&{$sortproc}($hash)) {
		#print "p='$p'\n";
		if ($p eq 'BREAK') {
			&table_dashes();
			next;
		}
		$h1 = \%{${$hash}{$p}};
		&print_counts($h1, $keyprint);
		last if (--$N == 0);
	}
	&table_dashes();
	print "\n";
	1;
}

sub list_top {
	local($name,$title,$hash,$sortproc,$keyprint,$N,$AK) = @_;
	local($h1);
	local($p);
	local($v);

	print "\n", &center($title), "\n\n";
	foreach $p (&{$sortproc}($hash,$AK)) {
		$h1 = \%{${$hash}{$p}};
		$v = ${$h1}{COUNT}{$AK};
		last unless ($v > 0);
		printf "%6d %-72.72s\n", $v, $p;
		last if (--$N == 0);
	}
	print "\n";
	1;
}

sub print_chart {
	local($hashref,$title,$AK) = @_;
	local($max) = 1;
	local(%TOD);
	print "\n\n", &center($title), "\n\n";
	foreach $i ( 0..47 ) {
		$TOD{$i} = ${$hashref}{$i}{COUNT}{$AK};
        	$max = $TOD{$i} if ($TOD{$i} > $max);
	}
	$factor = 10 / $max;
	print "\t           +------------------------------------------------+\n";
	for ($r=9; $r>=0; $r--) {
        	$l = ($r / $factor) + 1;
        	$h = ($r+1) / $factor;
        	printf "\t%5d-%5d|", $l, $h;
        	foreach $i ( 0..47 ) {
                	print (($TOD{$i} * $factor > $r) ? '#' : ' ');
        	}
        	print "|\n";
	}
	print "\tCounts     /------------------------------------------------+\n";
	print "\t       Hour 0 1 2 3 4 5 6 7 8 9 10  12  14  16  18  20  22   \n";
	1;
}

sub utilization_table {
	local($name,$title,$hash,$sortproc,$keyprint,$N) = @_;
	local($h1);
	local(@CLIENTS);
	local($C);
	local(%UTIL);
	local(%HITRATE);
	local(%RATIO);

	print "\n", &center($title), "\n\n";
	printf "%-" . $namelength . "." . $namelength . "s %7s + %14s = %s\n",
		'Client Hostname',
		'Hitrate',
		'HTTP:ICP Ratio',
		'Utilization';
	printf "%-" . $namelength . "." . $namelength . "s %7s   %14s   %s\n",
		'-'x$namelength,
		'-'x7,
		'-'x14,
		'-'x11;
	@CLIENTS = keys %{$hash};
	foreach $C (@CLIENTS) {
		$h1 = \%{${$hash}{$C}}; $UTIL{$C} = &utilization($h1,\$hitrate,\$ratio);
		$HITRATE{$C} = $hitrate;
		$RATIO{$C} = $ratio;
	}
	foreach $C (sort {$UTIL{$b} <=> $UTIL{$a}} @CLIENTS) {
		printf "%-" . $namelength . "." . $namelength . "s %7.2f + %14.2f = %11.2f\n",
			&{$keyprint}($C),
			$HITRATE{$C},
			$RATIO{$C},
			$UTIL{$C};
	}
	print "\n";
	1;
}

sub access_count_hist {
	local($k);
	print "\n", &center('Access Count Histogram');
	print "\n", &center('Number of objects accessed N times'), "\n\n";
		'Number of objects accessed N times';
	printf "%3.3s %6s\n",
		'N',
		'Count';
	printf "%-3.3s %6s\n",
		'-'x3,
		'-'x6;
	foreach $k (sort {$a <=> $b} keys %ACOUNT) {
		printf "%3d %6d\n",
			$k, $ACOUNT{$k};
	}
}

##############################################################################

sub print_counts {
	local($hashref, $keyprint) = @_;
	local($TCP_count) = 0;
	local($TCP_hitrate) = 0;
	local($TCP_allrate) = 0;
	local($THC) = 0;
	local($TCP_size) = 0;
	local($TCP_savings) = 0;
	local($TCP_sizerate) = 0;
	local($THS) = 0;
	local($UDP_count) = 0;
	local($UDP_hitrate) = 0;
	local($UDP_allrate) = 0;
	local($UHC) = 0;

	foreach $k (keys %{${$hashref}{COUNT}}) {
		$v=${$hashref}{COUNT}{$k};
		$TCP_count += $v if ($k =~ /^TCP_/);
		$THC += $v if ($k =~ /TCP.*HIT/);
		$UDP_count += $v if ($k =~ /^UDP_/);
		$UHC += $v if ($k =~ /UDP.*HIT/);
	}

	foreach $k (keys %{${$hashref}{BYTES}}) {
		$v=${$hashref}{BYTES}{$k};
		$TCP_size += $v if ($k =~ /^TCP_/);
		$THS += $v if ($k =~ /TCP.*HIT/);
	}

	$UDP_hitrate = $UHC / $UDP_count if ($UDP_count);
	$UDP_allrate = $UDP_count / $UDP_TOTAL_COUNT;

	$TCP_hitrate = $THC / $TCP_count if ($TCP_count);
	$TCP_allrate = $TCP_count / $TCP_TOTAL_COUNT;

	$TCP_savings = $THS / $TCP_size if ($TCP_size);
	$TCP_sizerate = $TCP_size / $TCP_TOTAL_BYTES;

	$p = &{$keyprint}($p) if (defined($keyprint));

        #printf "%-23.23s ", $p;
	printf "%-" . $namelength . "." . $namelength . "s ", $p;
	printf "%7d ", $UDP_count;
	printf "%4s ", &percent($UDP_allrate);
	printf "%4s ", &percent($UDP_hitrate);
	printf "%7d ", $TCP_count;
	printf "%4s ", &percent($TCP_allrate);
	printf "%4s ", &percent($TCP_hitrate);
	printf "%8.2f ", $TCP_size / 1000000;
	printf "%4s ", &percent($TCP_sizerate);
	printf "%4s ", &percent($TCP_savings);
	print "\n";
}

sub utilization {
	local($hashref, $hitref, $ratioref) = @_;
	local($TCP_count) = 0;
	local($TCP_hitrate) = 0;
	local($THC) = 0;
	local($UDP_count) = 0;
	local($UDP_TCP_ratio) = 0.8;

	foreach $k (keys %{${$hashref}{COUNT}}) {
		$v=${$hashref}{COUNT}{$k};
		$TCP_count += $v if ($k =~ /^TCP_/);
		$THC += $v if ($k =~ /TCP.*HIT/);
		$UDP_count += $v if ($k =~ /^UDP_/);
	}

	$TCP_hitrate = $THC / $TCP_count if ($TCP_count);
	$UDP_TCP_ratio = $TCP_count / $UDP_count if ($UDP_count);
	${$hitref} = $TCP_hitrate if $hitref;
	${$ratioref} = $UDP_TCP_ratio if $ratioref;
	$TCP_hitrate + $UDP_TCP_ratio;
}

sub table_dashes {
printf "%s %s-%s-%s %s-%s-%s %s-%s-%s\n", '-'x$namelength,
	'-'x7,'-'x4,'-'x4,
	'-'x7,'-'x4,'-'x4,
	'-'x8,'-'x4,'-'x4;
}

sub table_header {
	local($_) = @_;
	local($lead) = $namelength + 1;
	print ' 'x$lead;
	print '    UDP COUNTS        TCP COUNTS          TCP BYTES' . "\n";

	print $_;
	print ' 'x($lead - length);
	print ' counts %all %hit  counts %all %hit   Mbytes %all %hit' . "\n";
}

sub rev_server {
	local($_) = @_;
	local($proto);
	local($name);
	local(@F);
        if (/([^:]+):\/\/([^:]+)(.*)/) {
                $proto = $1;
                $name = $2;
                $port = $3;
                unless ($name =~ /^[0-9\.]+$/) {
                        @F = split(/\./, $name);
                        $name = join ('.', reverse @F);
                }
                $_ = $proto . '://' . $name . $port;
        }
	$_;
}

