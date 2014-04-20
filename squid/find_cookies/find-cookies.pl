#!/usr/local/bin/perl

# Hi, I find 'Set-Cookie' headers for cache objects on disk.
# Run me like this:
#
#    perl find-cookies.pl /usr/local/squid/cache/??
#

require 'timelocal.pl';
#$| = 1;

%MO =  ('jan','1','feb','2','mar','3','apr','4','may','5','jun','6',
	'jul','7','aug','8','sep','9','oct','10','nov','11','dec','12');

$nopened=0;
while ($d = shift) {
    unless (opendir(DIR, $d)) {
        warn "$d: $!\n";
        next;
    }
    while ($s = readdir(DIR)) {
        next if ($s =~ /^\./);
        $s = join('/',$d,$s);
        next unless (-d $s);
        unless (opendir(SDIR, "$s")) {
            warn "$s: $!\n";
            next;
        }
	@FF = ();
        while ($f = readdir(SDIR)) {
            next if ($f =~ /^\./);
            next unless ($f =~ /\d+/);
	    push (@FF, $f);
	}
        closedir(SDIR);
	@FF = sort {$a <=> $b} @FF;
	while ($f = shift @FF) {
            $f = join('/',$s,$f);
            next unless (open f);
	    $nopened++;
            sysread(f, $buf, 1024);
	    $buf =~ s/\r\n\r\n/\r\nEND\r\n/m;
	    $buf =~ s/\r\r/\rEND\r/m;
	    $buf =~ s/\n\n/\nEND\n/m;
            @lines = split(/[\r\n]+/, $buf);
            foreach $line (@lines) {
		last if ($line eq 'END');
		if ($line =~ /^Set-Cookie/) {
			print "$line\n" if ($line =~ /^Set-Cookie/);
			$ncookie++;
		}
            }
            close(f);
        }
	printf ("%d/%d --> %3.1f%%\n", $ncookie, $nopened, 100 * $ncookie / $nopened);
    }
    closedir(DIR);
}
