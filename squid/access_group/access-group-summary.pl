#!/usr/local/bin/perl

# access-group-summary.pl,v 1.3 1996/03/25 17:37:20 wessels Exp
#
# This file is under RCS control in
#    /O1/Cache_Central/Scripts/RCS/access-group-summary.pl,v
#


$| = 1;

$me = $0;
@F = split('/', $me); pop @F;
$medir = join ('/', @F);
push (@INC, $medir);

require 'cached-logs.pl';

@NLANR_caches = ('IT','PB','UC','BO','SV','SD','localhost');

$UDP_TOTAL_COUNT = 0;
$TCP_TOTAL_COUNT = 0;
$TCP_TOTAL_BYTES = 0;

while ($site = shift) {
	if ($site =~ /([^:]+):(.*)/) {
		$site = $1;
		$F = $2;
	} else {
		$F = "$site.sum";
	}
	unless (open F) {
		warn "$F: $!\n";
		next;
	}
	while (<F>) {
	        chop;
        	next if (/^#/);

		($longkey,$val) = split;
		($cat,$key,$cs,$tag) = split(/\|/, $longkey);
		if ($cat eq 'PR') {

			$SI{$site}{$cs}{$tag} += $val;
			$SI{ALL}{$cs}{$tag} += $val;

			$SI{$site}{COUNT}{ALL_UDP} += $val if
				($tag =~ /UDP_/ && $cs eq 'COUNT');
			$SI{$site}{COUNT}{ALL_TCP} += $val if
				($tag =~ /TCP_/ && $cs eq 'COUNT');
			$SI{$site}{BYTES}{ALL} += $val if
				($tag =~ /TCP_/ && $cs eq 'BYTES');

			$SI{ALL}{COUNT}{ALL_UDP} += $val if
				($tag =~ /UDP_/ && $cs eq 'COUNT');
			$SI{ALL}{COUNT}{ALL_TCP} += $val if
				($tag =~ /TCP_/ && $cs eq 'COUNT');
			$SI{ALL}{BYTES}{ALL} += $val if
				($tag =~ /TCP_/ && $cs eq 'BYTES');
		}

		if ($cat eq 'CL') {
			$client = $key;
			if ($tag =~ /UDP_/ && $cs eq 'COUNT') {
				$CL{$client}{UDP_COUNT}{$site} += $val;
				$CL{$client}{UDP_COUNT}{ALL} += $val;
			}
			if ($tag =~ /TCP_/ && $cs eq 'COUNT') {
				$CL{$client}{TCP_COUNT}{$site} += $val;
				$CL{$client}{TCP_COUNT}{ALL} += $val;
			}
		}

	}
	close F;
	push (@sites, $site);
}

$UDP_TOTAL_COUNT = $SI{ALL}{COUNT}{ALL_UDP};
$TCP_TOTAL_COUNT = $SI{ALL}{COUNT}{ALL_TCP};
$TCP_TOTAL_BYTES = $SI{ALL}{BYTES}{ALL};

sub xsort {
	local($href) = @_;
	local(@keys) = keys %{$href};
	sort { (${$href}{$b}{COUNT}{ALL_UDP} + ${$href}{$b}{COUNT}{ALL_TCP}) <=> (${$href}{$a}{COUNT}{ALL_UDP} + ${$href}{$a}{COUNT}{ALL_TCP}) } @keys;
}

&summary_table('Site', 'SUMMARY OF SITE USAGE', \%SI,
	\&xsort,undef,undef);


##############################################################################

sub matrix_hdr {
	local($title, @sites) = @_;
	print "\n\n", &center($title), "\n\n";
	printf "%-20s %7s %4s  %4s %4s %4s %4s %4s %4s\n",
        	'Client',
        	'count',
        	'%all',
        	@sites;
	1;
}

sub matrix_dashes {
	printf "%-20s %7s %4s  %4s %4s %4s %4s %4s %4s\n",
		'-'x20,
		'-'x7,
		'-'x4,
		'-'x4, '-'x4, '-'x4, '-'x4, '-'x4, '-'x4;
	1;
}

foreach $c (keys %CL) {
	push(@TCP_Clients, $c) if defined $CL{$c}{TCP_COUNT};
	push(@UDP_Clients, $c) if defined $CL{$c}{UDP_COUNT};
}

##############################################################################

&matrix_hdr('MATRIX OF CLIENT TCP ACTIVITY (COUNTS)', @sites);
&matrix_dashes;
foreach $c (sort byTCPcounts2 @TCP_Clients) {
	$fqdn = &fqdn($c);
	next unless (grep(/$fqdn/, @NLANR_caches));
	&cli_srv_pct(\%{$CL{$c}{TCP_COUNT}}, $c, $TCP_TOTAL_COUNT);
}
&matrix_dashes;
foreach $c (sort byTCPcounts2 @TCP_Clients) {
	$fqdn = &fqdn($c);
	next if (grep(/$fqdn/, @NLANR_caches));
	&cli_srv_pct(\%{$CL{$c}{TCP_COUNT}}, $c, $TCP_TOTAL_COUNT);
}
&matrix_dashes;

##############################################################################

&matrix_hdr('MATRIX OF CLIENT UDP ACTIVITY (COUNTS)', @sites);
&matrix_dashes;
foreach $c (sort byUDPcounts @UDP_Clients) {
	$fqdn = &fqdn($c);
	next unless (grep(/$fqdn/, @NLANR_caches));
	&cli_srv_pct(\%{$CL{$c}{UDP_COUNT}}, $c, $UDP_TOTAL_COUNT);
}
&matrix_dashes;
foreach $c (sort byUDPcounts @UDP_Clients) {
	$fqdn = &fqdn($c);
	next if (grep(/$fqdn/, @NLANR_caches));
	&cli_srv_pct(\%{$CL{$c}{UDP_COUNT}}, $c, $UDP_TOTAL_COUNT);
}
&matrix_dashes;

##############################################################################

&matrix_hdr('MATRIX OF CLIENT TCP ACTIVITY (COUNTS, DOMAIN SORT)', @sites);
&matrix_dashes;
foreach $c (sort by_rev_dom @TCP_Clients) {
	$fqdn = &fqdn($c);
	next if (grep(/$fqdn/, @NLANR_caches));
	&cli_srv_pct(\%{$CL{$c}{TCP_COUNT}}, $c, $TCP_TOTAL_COUNT);
}
&matrix_dashes;

##############################################################################

sub byUDPcounts {
	local($A) = 0;
	local($B) = 0;
	local($i) = 0;
	foreach $s (@sites) {
		$i++;
		$A += $CL{$a}{UDP_COUNT}{$s} * $i / $CL{$a}{UDP_COUNT}{ALL};
		$B += $CL{$b}{UDP_COUNT}{$s} * $i / $CL{$b}{UDP_COUNT}{ALL};
	}
	$A <=> $B;
}

sub byTCPcounts {
	local($A) = 0;
	local($B) = 0;
	local($i) = 0;
	foreach $s (@sites) {
		$i++;
		$A += $CL{$a}{TCP_COUNT}{$s} * $i / $CL{$a}{TCP_COUNT}{ALL};
		$B += $CL{$b}{TCP_COUNT}{$s} * $i / $CL{$b}{TCP_COUNT}{ALL};
	}
	$A <=> $B;
}

sub byTCPcounts2 {
	$CL{$b}{TCP_COUNT}{ALL} <=> $CL{$a}{TCP_COUNT}{ALL};
}

sub summary_table {
	local($name,$title,$hash,$sortproc,$keyprint,$N) = @_;
	local($h1);

	print "\n", &center($title), "\n\n";
	&header($name);
	&dashes();
	foreach $p (&{$sortproc}($hash)) {
	#print "p='$p'\n";
		if ($p eq 'BREAK') {
			&dashes();
			next;
		}
		$h1 = \%{${$hash}{$p}};
		&print_counts($h1, $keyprint);
		last if (--$N == 0);
	}
	&dashes();
	print "\n";
	1;
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
                $THC += $v if ($k eq 'TCP_HIT');
                $UDP_count += $v if ($k =~ /^UDP_/);
                $UHC += $v if ($k =~ /^UDP_HIT/);
        }

        foreach $k (keys %{${$hashref}{BYTES}}) {
                $v=${$hashref}{BYTES}{$k};
                $TCP_size += $v if ($k =~ /^TCP_/);
                $THS += $v if ($k eq 'TCP_HIT');
        }

        $UDP_hitrate = $UHC / $UDP_count if ($UDP_count);
        $UDP_allrate = $UDP_count / $UDP_TOTAL_COUNT;

        $TCP_hitrate = $THC / $TCP_count if ($TCP_count);
        $TCP_allrate = $TCP_count / $TCP_TOTAL_COUNT;

        $TCP_savings = $THS / $TCP_size if ($TCP_size);
        $TCP_sizerate = $TCP_size / $TCP_TOTAL_BYTES;

        $p = &{$keyprint}($p) if (defined($keyprint));

        printf "%-23.23s ", $p;
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


sub dashes {
printf "%s %s-%s-%s %s-%s-%s %s-%s-%s\n", '-'x23,
	'-'x7,'-'x4,'-'x4,
	'-'x7,'-'x4,'-'x4,
	'-'x8,'-'x4,'-'x4;
}

sub header {
	local($_) = @_;
	local($lead) = 23 + 1;
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

sub by_rev_dom {
	&rev_fqdn(&fqdn($a)) cmp &rev_fqdn(&fqdn($b));
}

##############################################################################

sub cli_srv_pct {
	local($H,$name,$TOTAL) = @_;


#print STDERR "H is a ". ref($H) . "\n";
#print STDERR "H has keys: ", join(' ', keys %{$H}), "\n";

#print STDERR "NAME = $name   TOTAL = $TOTAL\n";

	printf "%-20.20s %7d %4s  ",
		&rev_fqdn(&fqdn($name)),
		${$H}{'ALL'},
		&percent(${$H}{'ALL'} / $TOTAL);
	unless (${$H}{'ALL'}) {
		print '   - 'x($#sites+1), "\n";
		return;
	}
	foreach $k (@sites) {
		$pct = ${$H}{$k} / ${$H}{'ALL'};
		printf "%4s ", $pct ? &percent($pct) : '-';
	}
	print "\n";
}

