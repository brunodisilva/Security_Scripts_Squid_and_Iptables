#!/usr/bin/perl
#
# linblock.pl - Automatic blacklist retrieval and installation for Linux
#
# Website: http://dessent.net/linblock/
#
# Copyright (C) 2004  Brian Dessent <brian AT dessent DOT net>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
# Version History:
# 23-Jun-2004:  1.0     Initial version.
#
#
#
#

$main::VERSION = "1.0";

use strict;
use warnings;
no warnings qw/void/;  # to work aroud "Useless use of a variable in void context at /usr/local/lib/perl/5.8.3/IPTables/IPv4.pm line 5."
use Pod::Usage;
use Net::IP;
use LWP::Simple;
use IPTables::IPv4;
use Getopt::Std;


# suppress: Name "Getopt::Std::STANDARD_HELP_VERSION" used only once: possible typo at ./linblock.pl line 41.
$Getopt::Std::STANDARD_HELP_VERSION = 0;
$Getopt::Std::STANDARD_HELP_VERSION = 1;


# read command line stuff
our ($opt_c, $opt_u, $opt_p, $opt_l, $opt_r, $opt_f, $opt_q, $opt_i);
getopts('c:u:i:p:lrfq') || pod2usage(2);

pod2usage("Error: -u and -i cannot both be specified.") if($opt_u && $opt_i);

my $chain_name = $opt_c || "antip2p";
my $url = $opt_u || "http://www.bluetack.co.uk/config/antip2p.txt";
my $log_prefix = $opt_p || "antip2p";
my $do_logging = $opt_l ? 1 : 0;
my $jump_target = $opt_r ? "REJECT" : "DROP";

# sanitize the chain name
$chain_name =~ tr/a-zA-Z0-9_//cd;

$| = 1 unless $opt_q;

print "\nConnecting to IPTables interface..." unless $opt_q;
# initialize connection to kernel
my $table = IPTables::IPv4::init('filter');
if(!defined($table)) {
    die("Error: Could not connect to iptables interface: $!");
}

# remove chain from INPUT 
foreach my $rule ( $table->list_rules('INPUT') ) {
    if( $rule->{'jump'} eq $chain_name ) {
        $table->delete_entry('INPUT', $rule) or die("Error: Couldn't remove chain '$chain_name' from INPUT chain: $!");
    }
}

# flush only, i.e. disable filtering
if($opt_f) {
    print "\nFlushing chains..." unless $opt_q;
    flushdelete($table, $chain_name);
    flushdelete($table, "${chain_name}_log");
    $table->commit() or die("Error: Unable to commit changes to iptables rules: $!");
    print "\n" unless $opt_q;
    exit(0);
}

# create our chain
flushcreate($table, $chain_name);

# are we doing logging?
if( $do_logging ) {
    
    # we need to create a second chain for the logging
    flushcreate($table, "${chain_name}_log");
    
    # sanitize prefix: word characters only
    $log_prefix =~ tr/a-zA-Z0-9_ //cd; 
    append($table, "${chain_name}_log", { 'jump' => 'LOG', 'log-prefix' => "$log_prefix " });
    append($table, "${chain_name}_log", { 'jump' => $jump_target });

    # the new jump target will be this chain
    $jump_target = "${chain_name}_log";
}



# fetch the antip2p list
print "\nFetching antip2p list..." unless $opt_q;
my $antip2p;
if($opt_i) {
    open(FH, "<", $opt_i) or die("Error: Couldn't open file '$opt_i': $!");
    local $/;   # slurp whole file
    $antip2p = <FH>;
    close(FH);
} else {   
    $antip2p = get($url) or die("Error: Couldn't fetch '$url': $!");
}

# store the prefixes by their size, i.e. $prefixes{'32'} = [ "1.2.3.4/32", "2.3.4.5/32", ...];
my %prefixes;

my ($ranges, $cidr) = (0, 0);

# process the entries
print "\nParsing and converting:\n" unless $opt_q;
foreach ( split(/\n/, $antip2p) ) {
    if( m/^\s*$/ ) {
        next;        
	} elsif ( m/^(.*):(\d+\.\d+\.\d+\.\d+)\-(\d+\.\d+\.\d+\.\d+)\s*?$/ ) {
		if(($ranges % 500) == 0) {
		    printf("\r%-10d", $ranges) unless $opt_q;
		}		
		$ranges++;
		my $ip = new Net::IP ("$2 - $3");

        # loop through the prefixes
        foreach my $p ($ip->find_prefixes()) {
            if($p =~ m!/(\d+)$!) {
                $cidr++;
                push @{$prefixes{$1}}, $p;
            }
        }
	} else {
	    print "\r           \n";
	    print STDERR "Warning: Couldn't parse the following line:\n$_\n";
	}
	
}

print "\r$ranges lines read and converted to $cidr ranges; adding rules.\n" unless $opt_q;

# add the rules, in widest - shortest order
foreach my $slash ( sort { $a <=> $b } keys %prefixes ) {
    printf("\r" . " " x 25 . "\r/%d - %d rules", $slash, scalar @{$prefixes{$slash}}) unless $opt_q;
    foreach my $r ( @{$prefixes{$slash}} ) {
        append($table, $chain_name, { 'source' => $r, 'jump' => $jump_target });
    }
}

# insert at the beginning of INPUT chain
$table->insert_entry('INPUT', { 'jump' => $chain_name }, 0) or die("Error: Unable to insert rule into INPUT chain: $!");

# commit changes and exit
$table->commit() or die("Error: Unable to commit changes to iptables rules: $!");
print "\r" . " " x 50 . "\rAll done!\n" unless $opt_q;

exit(0);





# flush chain if it exists, otherwise create it
sub flushcreate {
    my ($table, $chain) = @_;

    if( $table->is_chain($chain) ) {
        $table->flush_entries($chain) or die("Error: Couldn't flush chain '$chain': $!");
    } else {
        $table->create_chain($chain) or die("Error: Couldn't create chain '$chain': $!");
    }
}


# append and check for error
sub append {
    my ($table, $chain, $href) = @_;
    
    $table->append_entry($chain, $href) or die("Error: Couldn't append rule to chain '$chain': $!");
}


# flush and delete a chain if it exists
sub flushdelete {
    my ($table, $chain) = @_;
    
    if( $table->is_chain($chain) ) {
        $table->flush_entries($chain) or die("Error: Couldn't flush chain '$chain': $!");
        $table->delete_chain($chain) or die("Error: Couldn't delete chain '$chain': $!");
    }
}


sub main::HELP_MESSAGE {
# arguments are the output file handle, the name of option-processing package, its version, and the switches string
#    pod2usage( { -exitval => "1", -output => $_[0], -verbose => 1} );
    pod2usage(1);
}

sub main::VERSION_MESSAGE {
    my $fh = shift;
    print $fh "linblock.pl version $main::VERSION - Copyright 2004 Brian Dessent\n";
}


__END__

=head1 NAME

linblock.pl - Automatically download antip2p blacklist and install into Linux's IPTables interface

=head1 SYNOPSIS

./linblock.pl [ -c I<chain> ] [ -u I<url> | -i I<file> ] [ -p I<prefix> ] [ -l ] [ -r ] [ -f ] [ -q ] [ --help ] [ --version ]

=head1 DESCRIPTION

linblock.pl downloads a list of IP address ranges in the "PeerGuardian" format, and installs
them into the Linux kernel using the IPTables interface.  This effectively
blocks access to the machine from any address listed in the blacklist file.  When run it first
clears the chain created by previous execution of the command, so it is suitable to be scheduled
for automatic updates by 'cron' or similar.

=head1 OPTIONS

All command line options are optional.

=over

=item -u I<url>

Specifies the URL from which to retrieve the blacklist data.  The default is C<http://www.bluetack.co.uk/config/antip2p.txt>.
The URL should point to a text file that contains IP ranges in the "PeerGuardian" format.

=item -i I<file>

As an alternative to B<-u>, you can specify a local file with this option from which to read the 
blacklist data.  B<-u> and B<-i> are mutually exclusive.

=item -l

Enable logging of packets rejected by the antip2p blacklist.  If not specified, there will be no
entry in the system logs for dropped/rejected packets.

=item -f

Flush the antip2p chains and exit.  This will remove all blacklist rules managed by this script, 
while leaving the rest of the configured IPTables rules intact.  After running C<linblock.pl -f> the
IPTables configuration will return to the state it was in before any invocation of the script.  Note:
If you specify a non-default chain name when installing the rules you must specify it when flushing them
as well.

=item -q

Be quiet.  The script will not produce any output except warnings and fatal errors.

=item -r

Reject rather than Drop packets.  The default action is to silently drop packets meeting the blacklist
rules, which causes the remote connection to see no sign of a host -- the connection attempt will eventually time out.
However, if Reject is chosen, an ICMP "Host unreachable" message will be immediately sent and the remote connection
will immediately receive a "connection refused" message instead.

=item -p I<prefix>

If logging is enabled (see B<-l>) then this specifies the prefix to use in the logs.  The default
is 'antip2p'.  Logging is handled by the kernel, so you will see reject/drop log entries in your
C</var/log/syslog> or C</var/log/messages> file.

=item -c I<chain>

Specifies the name of the chain to install.  The default is C<antip2p>.  The chain's name 
has no effect on its functionality, other than the fact that it must be unique.

=item --help

Print command line options summary.  For more detailed help, type C<perldoc -F linblock.pl>.

=item --version

Prints the version information.

=back

=head1 INSTALLATION

B<Note: You must be root for all of the module installation procedures in this section.>

After downloading the script, make sure it has the "x" bits set: C<'chmod 755 linblock.pl'> or equivalent.

This script requires the Perl modules B<Net::IP>, B<IPTables::IPv4>, and B<LWP::Simple>.  You must install them from CPAN
if they are not installed on your system already.  To check if a module is installed, use the following command:

=over

=item perl -MNet::IP -e 1

=back

If the B<Net::IP> module is not installed on your system you will get an error message, otherwise the command will silently complete.

To install a module from CPAN, use the following command:

=over

=item perl -MCPAN -e 'install Net::IP'

=back

This will launch CPAN and attempt to install the B<Net::IP> module.  If this is the first time that you have used CPAN, it will
ask you a number of questions.  You can simply press return to accept the default for most of them.  The only questions that require
interaction are selecting your continent and selecting a mirror site to download from.  Repeat the above command for the rest
of the modules you lack.  Note: To install B<LWP::Simple> use C<'install LWP'>.

If you have the C<'cpan'> command installed on your system you can try the following to install all the modules at once:

=over

=item cpan -i LWP Net::IP IPTables::IPv4

=back

If you have problems with CPAN not being able to retrieve things, and your firewall uses NAT or IP masquerading, then try setting
the B<FTP_PASSIVE> environment variable before running CPAN:

=over

=item FTP_PASSIVE=1; export FTP_PASSIVE

=back

If you find that this causes CPAN to work then you should either add that statement to your startup scripts, or select only http mirrors
to avoid the issue.  You can re-do the initial mirror selection process by running C<'o conf init'> from the CPAN shell, which you can run
by supplying C<'-e shell'> on the command line in place of C<'-e install ...'>.

If some tests fail then CPAN will not install the module by default.  Usually you can force the install and get a working module.
To instruct CPAN to ignore failing tests, use C<'force install ...'> instead of C<'install ...'> in the command line.  For more information
about how to use CPAN, try C<'perldoc CPAN.pm'>.

Finally, if you cannot make CPAN work at all, you can install the modules by hand, as follows:

=over

=item *

Download the module package from CPAN.  You can obtain its URL by loading B<search.cpan.org> in your browser and searching on the module
name.  Click on the distribution name (e.g. B<Net-IP-1.20>) and there will be a "download" link for the .tar.gz package.  Then execute
the following sequence of commands.  You would substitute the URL and name of the package you are installing, and if you downloaded the .tar.gz
file with your browser you can skip the wget step.

=item *

wget http://search.cpan.org/CPAN/authors/id/M/MA/MANU/Net-IP-1.20.tar.gz

=item *

tar zxvf Net-IP-1.20.tar.gz

=item *

cd Net-IP-1.20/

=item *

perl Makefile.PL

=item *

make install

=back

Repeat this procedure for the rest of the required modules.

=head1 AUTOMATIC UPDATES

linblock.pl was designed to run automatically for frequent updates.  The easiest way to accomplish this is with the 'cron' utility
found on most Linux systems.  The script requires root privileges to modify the IPTables rules, thus it should be run from root's crontab.
Log in as root (or type C<'su'> and supply the root password) and then type C<'crontab -e'>.  This will bring up the crontab file in 
an editor.  If you have not previously installed anything in this crontab, it will probably be blank.

To run the update once a day at midnight, add a line similar to the following:

=over

0 0 * * * /usr/local/sbin/linblock.pl -q

=back

The first five words on the line control when the job is run.  In this case it means that it should be run on the 0th minute of the 0th hour
of every day of every month -- i.e. daily at midnight.  The command then follows on the rest of the line.  You should replace the path in the
example with the path where you've placed the script on your local machine, and supply the command-line parameters that you have chosen.
B<-q> is suggested, which will suppress the normal program output, instead only warnings and errors will be printed.  'cron' expects that all
is successfull if there is no output, and will send you an email if there was any output.

Save the file and exit the editor, and you should see crontab report that it has installed the crontab file.

=head1 AUTHOR

=over

=item Brian Dessent <brian AT dessent DOT net>

=item See also: L<http://dessent.net/linblock/>

=back

=head1 LICENSE

Copyright (C) 2004  Brian Dessent <brian AT dessent DOT net>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

=cut                


