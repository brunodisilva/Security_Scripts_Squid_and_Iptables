#!/usr/local/bin/perl
### -------------------------------------------------------------------- ###
#
# ip2fqdn.pl: converts logs with IP numbers in the first line position
#             to fully qualified domain names
#
# usage: ip2fqdn.pl < logfile > new-logfile
#
# Author: Martin Gleeson, July 1996.  Public domain.
#
# Bug fixes: Neil Murray <neil@aone.com.au>
#            - The wrong FQDN given to an IP address if the IP address
#            had only 1 digit in the first two sections of the dotted quad.
#
### -------------------------------------------------------------------- ###
#   The program looks up IP numbers, and keeps the returned IP names in
#   an associative array, indexed by IP number. This means only one DNS
#   lookup is made for each distinct IP number, making the whole operation
#   *reasonably* fast (hey, it's perl, not C :-).
### -------------------------------------------------------------------- ###

$address_type=2;

while( <STDIN> )
{
    chop;
    ($host, $rest) = /^(\S+) (.+)$/;

    # no need to look it up if it's already been done.
    if( $hosts{$host} )
    {
        $name = $hosts{$host};
    }
    else
    {
        # new IP number - look for its IP name
        if($host =~ /\d+\.\d+\.\d+\.\d+/)
        {
            @address = split(/\./,$host);
            $addpacked = pack('C4',@address);
            ($name,$aliases,$addrtype,$length,@addrs) =
                gethostbyaddr($addpacked,$address_type);
        }
        # if nothing returned, then no IP name exists for the IP number
        $name = $host if ($name eq "");

        # make the IP name lowercase for uniformity
        $name = "\L$name";

        # add the IP name to the associative array
        $hosts{$host} = $name;
    }

    print "$name $rest\n";
}

exit(0);
