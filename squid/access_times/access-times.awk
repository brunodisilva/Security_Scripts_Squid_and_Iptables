#!/bin/awk -f

#From:    Andrew Richards <andrew@tic.ch>
#To:      "'squid-users@nlanr.net'" <squid-users@nlanr.net>
#Date:    Mon, 02 Sep 1996 19:25:59
#==============================================================================
#
#Hi all,
#
#Someone helpfully pointed me in the direction of the release notes for Squid,
#so I've hacked together a quick awk script to get the stats out of Squid
#that I've come to expect, after using Netscape proxy. So what I've written
#gives you output like this,
#
#        local cache     remote cache    remote proxied  no proxy,cache  other
#Number:   1255             522            2994             965             177
#         21.2%            8.8%           50.6%           16.3%            3.0%
#Time:     1.0s            1.7s            6.1s            3.7s           15.9s
#
#which seems to nicely complement the existing stats scripts provided at nlanr.
#It's written for nawk (for awk it probably needs a few formatting changes).
#
#Here's the source - what I'd like now is if any of you use it, to check
#whether I'm interpreting the logfile entries properly - in particular
#the FIRST_PARENT_MISS entry. I say this because the results above are
#real results and look peculiar to me - that the proxied time is longer
#than the direct time. Am I doing something wrong?
#
#The script is written for Squid's native logfile format (now I know
#what that switch emulate_httpd_log and the -f switch for the nlanr
#stats script means....)
#
#Setting some variables to one and subtracting one in other places
#is just a cheap hacky trick to avoid having divide-by-zero errors.
#The accuracy of the results should hardly be impaired. Of course a
#good programmer would test for zero before the division...
#
#Any improvements to this program will be most welcome
#- please mail me as well as the list.
#
#cheers,
#
#Andrew Richards.
#
#==============================================================================
#
# Modifications by: Hyunchul Kim <hckim@cosmos.kaist.ac.kr>
#
# I gave a quick minor change on the script - access-times.awk, formerly
# written by Andrew Richards.
#
#	* partitioned remote_caches into sibing_hit & parent_hit,
#	* accounts for how much was hit by local, siblings, parent explicitly.
#
#==============================================================================


BEGIN {
        clientcache=1; t_clientcache=0;  b_clientcache = 0;
           localhit=1;    t_localhit=0;  b_localhit = 0;
        neighborhit=1; t_neighborhit=0;  b_neighborhit = 0;
          parenthit=1;   t_parenthit=0;  b_parenthit = 0;
         parentmiss=1;  t_parentmiss=0;  b_parentmiss = 0;
             direct=1;      t_direct=0;  b_direct = 0; 
               deny=1;        t_deny=0;  b_deny = 0;
               fail=1;        t_fail=0;  b_fail = 0;
}

/LOG_NONE/      { next }
/UDP_/          { next }
/ERR_/          { fail++;       t_fail += $2; b_fail += $5; next}
/IFMODSINCE/ && /304/ {clientcache++;   t_clientcache += $2; b_clientcache += $5;  next};
/TCP_HIT/       { localhit++;   t_localhit += $2;  b_localhit += $5;     next};
/TCP_DENIED/    { deny++;       t_deny += $2;      b_deny += $5;     next};
/DIRECT/        { direct++;     t_direct += $2;    b_direct += $5;    next};
/NEIGHBOR_HIT/  { neighborhit++; t_neighborhit += $2; b_neighborhit += $5;next};
/PARENT_HIT/    { parenthit++;  t_parenthit += $2; b_parenthit += $5;     next};
/PARENT_MISS/   { parentmiss++; t_parentmiss += $2; b_parentmiss += $5;    next};

END             { localcache = localhit + clientcache;
		  b_localcache = b_localhit + b_clientcache;
                  t_localcache = t_localhit + t_clientcache;
                  othercache = neighborhit + parenthit;
		  b_othercache = b_neighborhit + b_parenthit;
                  t_othercache = t_neighborhit + t_parenthit;
                  other = fail + deny; t_other = t_fail + t_deny;
		  b_other = b_fail + b_deny;
                  all = fail + clientcache + localhit + deny + \
                  direct + neighborhit + parenthit + parentmiss;
		  b_all = b_other + b_clientcache + b_localhit + b_deny + \
		  b_direct + b_neighborhit + b_parenthit + b_parentmiss;

                  printf "\tlocal hit   sibling  hit   parent hit   remote proxied   direct   other\n";
                  printf "Counts:\t%6d     %6d        %6d         %6d        %6d    %6d\n", localcache-2, neighborhit-1, parenthit-1, parentmiss-1, direct-1, other-2;
                  printf "\t%5.1f%%     %5.1f%%        %5.1f%%         %5.1f%%        %5.1f%%     %5.1f%%\n", localcache/all*100, neighborhit/all*100, parenthit/all*100, parentmiss/all*100, direct/all*100, other/all*100;
                  printf "MBytes:\t%5.2f     %6.2f        %6.2f         %6.2f        %6.2f   %6.1f\n", b_localcache/1024/1024, b_neighborhit/1024/1024, b_parenthit/1024/1024, b_parentmiss/1024/1024, b_direct/1024/1024, b_other/1024/1024;
                  printf "\t%5.1f%%     %5.1f%%        %5.1f%%         %5.1f%%        %5.1f%%     %5.1f%%\n", b_localcache/b_all*100, b_neighborhit/b_all*100, b_parenthit/b_all*100, b_parentmiss/b_all*100, b_direct/b_all*100, b_other/b_all*100;
                  printf "Secs:\t%5.1fs     %5.1fs        %5.1fs         %5.1fs        %5.1fs     %5.1fs\n", t_localcache/localcache/1000, t_neighborhit/neighborhit/1000, t_parenthit/parenthit/1000, t_parentmiss/parentmiss/1000, t_direct/direct/1000, t_other/other/1000;
}
