#!/usr/local/bin/perl

# $Id: access-extract.pl,v 1.20 1997/05/21 23:24:55 wessels Exp $
#
# This file is under RCS control in
#    $Source: /O1/Squid_Central/Scripts/RCS/access-extract.pl,v $
#

$me = $0;
@F = split('/', $me); pop @F;
$medir = join ('/', @F);

push (@INC, $medir);

require 'timelocal.pl';
#require 'getopts.pl';
require 'squid-logs.pl';

$usage = "usage: $me -h --methods --protocols --clients --servers --types\n"
.	"     : --times --domains\n";

# Defaults
$HTTPDFormat = 0;
$MaxEntries = 50;

while (($#ARGV >=  $[) && ($ARGV[0] =~ /^-/) && ($_ = shift)) {
	if ($_ eq '-h') {
		$HTTPDFormat = 1;
	} elsif ($_ eq '--methods') {
		$CATS{'ME'} = $MaxEntries;
	} elsif ($_ eq '--protocols') {
		$CATS{'PR'} = $MaxEntries;
	} elsif ($_ eq '--clients') {
		$CATS{'CL'} = $MaxEntries;
	} elsif ($_ eq '--servers') {
		$CATS{'SE'} = $MaxEntries;
	} elsif ($_ eq '--types') {
		$CATS{'TY'} = $MaxEntries;
	} elsif ($_ eq '--times') {
		$CATS{'TI'} = $MaxEntries;
	} elsif ($_ eq '--domains') {
		$CATS{'DO'} = $MaxEntries;
	} else {
		warn "$me: $_: unknown option\n";
		die $usage;
	}
}
unless (keys %CATS) {
	$CATS{'ME'} = $MaxEntries;
	$CATS{'PR'} = $MaxEntries;
	$CATS{'CL'} = $MaxEntries;
	$CATS{'SE'} = $MaxEntries;
	$CATS{'TY'} = $MaxEntries;
	$CATS{'TI'} = $MaxEntries;
	$CATS{'DO'} = $MaxEntries;
}

while (<>) {
	@F = $HTTPDFormat ? &parse_common_log($_) : split;
	next unless (@F);
	($when,$elapsed,$who,$tag,$size,$method,$what,$id,$hier) = @F;
	($tag,$code) = split('/', $tag);
	print "$when,$elapsed,$who,$tag,$size,$method,$what\n" if ($debug);
	$do_count = 1;
	$do_size = $tag =~ /^TCP_/ || $tag eq 'UDP_HIT_OBJ' ? 1 : 0;

	$first = $when unless defined $first;
	$last = $when;

	foreach $cat (keys %CATS) {
		${$cat} = 'Unknown';
	}

	$ME = $method;

	$what = "ssl://$what/" if $method eq "CONNECT";
	if ($what =~ /([^:]+)/) {
		$PR = $1;
		$PR =~ tr/A-Z/a-z/;
	}

	$CL = $who;

	if ($what =~ m'([^:]+://[^/]+)/') {
		$SE = $1;
		$SE =~ tr/A-Z/a-z/;
		$SE =~ m'([^:]+)://([^:]+):?(.*)';
		$DO = &top_level_domain($2);
	}

	$when =~ s/\..*//;
	if ($when != $lasttime) {
		@T = localtime($when);
		$TI = int($T[2] * 2 + $T[1] / 30);
		$lasttime = $when;
	}

	$TY = &url_type($what);

	foreach $cat (keys %CATS) {
		${$cat}{${$cat}}{COUNT}{$tag}++ if ($do_count);
		${$cat}{${$cat}}{BYTES}{$tag} += $size if ($do_size);
	}

	$TO{TCP}{REQUESTS} ++ if ($tag =~ /^TCP_/);
	$TO{UDP}{REQUESTS} ++ if ($tag =~ /^UDP_/);
	$TO{TCP}{BYTES} += $size if ($do_size);
}

# memory efficient sort...
#
foreach $cat (keys %CATS) {
	$h0 = \%{$cat};
	$max = $CATS{$cat} - 1;
	@counts = ();
	while (($k,$v) = each %{$h0}) {
		$n = &request_count($v);
		$n > 1 ? push(@counts, $n) : delete ${$h0}{$k};
	}
	print "# SORTING %$cat, ", scalar(%{$h0}), " values...\n";
	@counts = sort { $b <=> $a } @counts;
	$thresh = $#counts > $max ? $counts[$max] : 0;
	print "# THRESH %$cat = $thresh\n";
	@counts = undef;
	while (($k,$v) = each %{$h0}) {
		$n = &request_count($v);
#		print "K = $k   V = $v  N = $n\n";
		next unless $n < $thresh;
#		print "deleting $k...\n";
#		${$h0}{$k} = undef;
		delete(${$h0}{$k});
	}
}

# Make sure these are set
$TO{TCP}{REQUESTS} = -1 unless ($TO{TCP}{REQUESTS} > 0);
$TO{UDP}{REQUESTS} = -1 unless ($TO{UDP}{REQUESTS} > 0);
$TO{TCP}{BYTES} = -1 unless ($TO{TCP}{BYTES} > 0);

# Print totals
print "TO|TCP|REQUESTS $TO{TCP}{REQUESTS}\n";
print "TO|UDP|REQUESTS $TO{UDP}{REQUESTS}\n";
print "TO|TCP|BYTES $TO{TCP}{BYTES}\n";

print "TIMESTAMP|FIRST $first\n";
print "TIMESTAMP|LAST  $last\n";

# dump

foreach $cat (keys %CATS) {
	$h0 = \%{$cat};
#	print "$cat is a ". ref($h0), "\n";
#	print "  --> KEYS of $h0: ", join (' ', keys %{$h0}), "\n";
#	print "  --> VALS of $h0: ", join (' ', values %{$h0}), "\n";
	foreach $k0 (keys %{$h0}) {
		$h1 = \%{${$h0}{$k0}};
#		print "$cat|$k0 is a ". ref($h1), "\n";
#		print "  --> KEYS of $h1: ", join (' ', keys %{$h1}), "\n";
		foreach $k1 (keys %{$h1}) {
			$h2 = \%{${$h1}{$k1}};
#			print "$cat|$k0|$k1 is a ". ref($h2), "\n";
			foreach $k2 (keys %{$h2}) {
				$v3 = ${$h2}{$k2};
				print "$cat|$k0|$k1|$k2 $v3\n";
			}
		}
	}
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
