#!/bin/bash
#
# The Linux Firewall Project Graphical Installation Utility
# Version 1.1 -- 1/21/03
# http://projectfiles.com/firewall/ 
#
# Linux Firewall
# Copyright (C) 2001-2002 Scott Bartlett <srb@mnsolutions.com>
#
# Graphical Installation Utility
# Copyright (C) 2002 Vincent Rivellino <var@mnsolutions.com>
#                    and Scott Bartlett <srb@mnsolutions.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.html
#
#
##############################################
# -- Administrative Configuration Options -- #
##############################################
#
# LONG_NETWORK_NAME below should be a character string to be displayed
# by the installer as an explanation of the list of networks and/or
# hosts defined in LOCAL_NETWORK. SHORT_NETWORK_NAME should be a single
# word that will be used when highlighting your choice of networks.
# The LOCAL_NETWORK variable should consist of a space
# delimited list of networks and hosts with netmasks between 0 and 32
# in the format: <host or network address>[/<netmask>]
# WARNING: None of these options are checked for input errors.  Please
# enter information carefully.

LONG_NETWORK_NAME=""
SHORT_NETWORK_NAME=""
LOCAL_NETWORK=""

###########################################################
# -- Nothing below this point should need modification -- #
###########################################################

# Set version information.

GUI_VERSION="1.1"
FW_VERSION="2.0rc9"

# Set PATH explicitly.

export PATH="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin"

# Set variables.

TMPFILE="/tmp/firewall.temp$$"
FW_TMPFILE="/tmp/rc.firewall"
FW_INSTALL="/etc/rc.d/rc.firewall"
FW_PERM="750"
permit_opt=""
int_iface_opt=""
dyn_iface_opt=""
status="welcome"

if [ "$1" == "fast" ]; then
  INIT="fast"
else
  INIT="start"
fi

# Make sure we are root.

if [ "$EUID" != "0" ]; then
  echo "You must have root privileges to run this utility!!!"
  exit 1
fi

# remove the TMPFILE ...
rm -rf $TMPFILE > /dev/null 2>&1

# Define a default LONG_NETWORK_NAME if none exists.  This will be ignored if
# there is no corresponding LOCAL_NETWORK.

if [ -z "$LONG_NETWORK_NAME" ]; then
  LONG_NETWORK_NAME="predefined network"
fi

# Do the same for SHORT_NETWORK_NAME.

if [ -z "$SHORT_NETWORK_NAME" ]; then
  SHORT_NETWORK_NAME="local"
fi

# Define exit subroutine.

goodbye()
{
  rm -f $TMPFILE > /dev/null 2>&1
  clear
  echo "Configuration terminated.  Goodbye."
  exit
}

# Convert a provided netmask of 255.255.252.0 to /24 notation if necessary.

make_mask()
{
  if [ "X$1" == "X" ]; then
    echo -1
    return
  fi

  if [ "X`echo $1 | cut -s -f 1 -d '.'`" == "X" ]; then
    if [ "$1" -ge "32" ]; then
      echo -1
    else
      echo $1
    fi
    return
  fi
  MASK=$1

  LAST=1
  for OCTET in 1 2 3 4; do
    BINARY=`echo "$MASK" | cut -s -d . -f $OCTET`
    if [ "X$BINARY" == "X" ]; then
      echo -1
      exit
    fi
    for SUBTRACT in 128 64 32 16 8 4 2 1; do
      if [ "$((BINARY - SUBTRACT))" -ge "0" ]; then
        BINARY=$((BINARY - SUBTRACT))
        STROKE=$((STROKE + 1))
        if [ "$LAST" != "1" ]; then
          echo -1
          exit
        fi
      else
        LAST=0
      fi
    done
  done
  echo $STROKE
}

# Given a servicename, return a string to add to the PERMIT option.

get_pstr()
{
  case "$1" in
  '"ftp"')
    echo "21/tcp"
    ;;
  '"ssh"')
    echo "22/tcp"
    ;;
  '"smtp"')
    echo "25/tcp"
    ;;
  '"dns"')
    echo "53"
    ;;
  '"finger"')
    echo "79/tcp"
    ;;
  '"http"')
    echo "80/tcp"
    ;;
  '"pop3"')
    echo "110/tcp"
    ;;
  '"auth"')
    echo "113/tcp"
    ;;
  '"imap"')
    echo "143/tcp"
    ;;
  '"https"')
    echo "443/tcp"
    ;;
  '"syslog"')
    echo "514/udp"
    ;;
  '"lpd"')
    echo "515/tcp"
    ;;
  '"imaps"')
    echo "993/tcp"
    ;;
  '"pop3s"')
    echo "995/tcp"
    ;;
  *)
    echo "other"
  esac
}

# Given a port from PERMIT, return a service name.

get_sstr()
{
  case "$1" in
  '21/tcp')
    echo "FTP [21/tcp]"
    ;;
  '22/tcp')
    echo "SSH [22/tcp]"
    ;;
  '25/tcp')
    echo "SMTP [25/tcp]"
    ;;
  '53')
    echo "DNS [53/udp 53/tcp]"
    ;;
  '79/tcp')
    echo "FINGER [79/tcp]"
    ;;
  '80/tcp')
    echo "HTTP [80/tcp]"
    ;;
  '110/tcp')
    echo "POP3 [110/tcp]"
    ;;
  '113/tcp')
    echo "AUTH [113/tcp]"
    ;;
  '143/tcp')
    echo "IMAP [143/tcp]"
    ;;
  '443/tcp')
    echo "HTTPS [443/tcp]"
    ;;
  '514/udp')
    echo "SYSLOG [514/udp]"
    ;;
  '515/tcp')
    echo "LPD [515/tcp]"
    ;;
  '993/tcp')
    echo "IMAPS [993/tcp]"
    ;;
  '995/tcp')
    echo "POP3S [995/tcp]"
    ;;
  *)
    echo "PORT $1" # other
  esac
}

# Check dialog version.

if (( `which dialog 2>&1 | grep -c "which: no dialog in"` )); then
  echo "Required program 'dialog' not found."
  exit 1
fi

DIALOG_VERSION=`dialog --version 2>&1`
if (( `echo "$DIALOG_VERSION" | grep -c "0.9b"` )); then
  DEFAULT_NO="--defaultno"
  NO_CANCEL="--nocancel"
  CANCEL_BACK="--cancel-label Back"
  CANCEL_QUIT="--cancel-label Quit"
elif (( `echo "$DIALOG_VERSION" | grep -c "0.9a"` )); then
  DEFAULT_NO="--defaultno"
  NO_CANCEL="--nocancel"
  CANCEL_BACK=""
  CANCEL_QUIT=""
else
  DEFAULT_NO=""
  NO_CANCEL=""
  CANCEL_BACK=""
  CANCEL_QUIT=""
fi

# Begin installer.

while [ "$status" != "exit" ]; do

  case "$status" in

  'welcome')
   dialog --title "Linux Firewall Configuration Utility" $CANCEL_QUIT \
      --menu "Welcome to installer version $GUI_VERSION for Linux Firewall version $FW_VERSION.  You can abort this installation at any time by pressing the [ESC] key.  Please select your desired installation type below.  The default installation will close all ports so that no services will be available to remote hosts.  A custom installation will allow you to configure remote access and provide an opportunity to enable Internet connection sharing for hosts on an attached private network." 18 55 2 \
      "default" "Default Installation" \
      "custom" "Custom Installation" 2> $TMPFILE

    if [ $? != 0 ]; then goodbye; fi
    if [ "`cat $TMPFILE`" == "default" ]; then
      status="writefile"
    else
      status="portlist"
    fi
    ;;

  'portlist')
  dialog --title "Open Ports" --checklist "Below is a list of common services available on Linux systems.  Using the space bar, select the services ** running on this machine ** you wish to make available to remote hosts.  In the next section you will be given a chance to specify who is allowed to connect to each service.  Afterwards you will be given an opportunity to specify hosts and networks allowed to bypass the firewall altogether." 25 55 10 \
      "ftp" "File Transfer Protocol [21/tcp]" off \
      "ssh" "Secure Shell [22/tcp]" on \
      "smtp" "Incoming Email (sendmail) [25/tcp]" off \
      "dns" "Domain Name Service [53/udp & 53/tcp]]" off \
      "finger" "Finger Service [79/tcp]" off \
      "http" "Web Server [80/tcp]" off \
      "pop3" "POP3 mail server [110/tcp]" off \
      "auth" "Ident Auth service [113/tcp]" off \
      "imap" "IMAP mail server [143/tcp]" off \
      "https" "Secure Web Server [443/tcp]" off \
      "syslog" "Remote System Logging [514/udp]" off \
      "lpd" "LPR Print Spooler [515/tcp]" off \
      "imaps" "Secure IMAP mail server [993/tcp]" off \
      "pop3s" "Secure POP3 mail server [995/tcp]" off \
      "other" "other port(s) not listed" off 2> $TMPFILE

    status=$?

    if [ "$status" == "255" ]; then goodbye
    elif [ "$status" == "0" ]; then
      permit_opt=""
      for option in `cat $TMPFILE` ; do
        option=`get_pstr $option`
        if [ "$option" == "other" ]; then
          status="otherports"
        else
          permit_opt="$permit_opt $option"
        fi
      done

      if [ "$status" != "otherports" ]; then
        status="openports"
      fi
    else
      status="natquestion"
    fi
    ;;

  'otherports')
    dialog $CANCEL_BACK --title "Specify Open Ports" --inputbox "Numerically list additional ports or port ranges available to other connecting hosts.  In the next section you will be given a chance to specify who is allowed to connect to each port or port range.  Protocols 'tcp' and 'udp' can optionally be specified here.  If no protocol is specified, then connections to either protocol will be accepted.  Format: <port or port-range>[/<protocol>]  Example: \"901/tcp 92 2400-2500/tcp\"  This will open up TCP port 901, port 92 for both TCP and UDP, and TCP ports 2400 through 2500." \
    19 55 2> $TMPFILE

    status=$?
    if [ "$status" == "255" ]; then goodbye
    elif [ "$status" == "0" ]; then
      status="openports"
      permit_opt="$permit_opt `cat $TMPFILE`"
    else
      status="portlist"
    fi
    ;;

  'openports')
    option=""
    portnum=`echo $permit_opt | wc`
    portnum=`echo $portnum | cut -f 2 -d ' '`
    curport=0
    for port in $permit_opt ; do
      curport=`expr $curport + 1`
      portstr=`get_sstr $port`
      if [ -n "$LOCAL_NETWORK" ]; then

	dialog $NO_CANCEL --title "Port $curport of $portnum - $portstr" --menu "Who can access $portstr?" 10 55 3 \
	  "any" "Allow from anywhere" \
	  "$SHORT_NETWORK_NAME" "Allow from $LONG_NETWORK_NAME" \
	  "specify" "Specify Access" 2> $TMPFILE

      else

	dialog $NO_CANCEL --title "Port $curport of $portnum - $portstr" --menu "Who can access $portstr?" 9 55 2 \
	  "any" "Allow from anywhere" \
	  "specify" "Specify Access" 2> $TMPFILE

      fi
      status=$?
      if [ "$status" == "255" ]; then goodbye
      elif [ "$status" == "0" ]; then
        case "`cat $TMPFILE`" in
        'any')
          option="$option $port"
          ;;
        "$SHORT_NETWORK_NAME")
          for net in $LOCAL_NETWORK ; do
            option="$option $net:$port"
          done
          ;;
        'specify')
          status="loop"
          while [ "$status" == "loop" ]; do
            dialog $NO_CANCEL --title "Specify access to $portstr" --inputbox "Please specify which hosts and/or networks may connect to $portstr by entering a space-delimited list of hosts and/or networks.  Format: <host or network address>[/<netmask>]  Example: \"207.198.61.33 198.82.0.0/16\"" \
            13 55 2> $TMPFILE

            status=$?
            if [ "$status" == "255" ]; then goodbye
            elif [ "$status" == "0" ]; then
              for combo in `cat $TMPFILE` ; do
                if [ "X`echo $combo | cut -s -f 1 -d '/'`" == "X" ]; then
                  option="$option $combo:$port"
                  status="not a loop"
                else
                  host=`echo $combo | cut -s -f 1 -d '/'`
                  mask=`echo $combo | cut -s -f 2 -d '/'`
                  newmask=`make_mask $mask`
                  if [ "$newmask" == "-1" ]; then
                    dialog --title "Invalid Bitmask" --msgbox "The host/netmask you specified (${host}/${mask}) was invalid.  Re-enter the full list of hosts and/or networks for port ${portstr}." \
                    7 55
                    status=$?
                    if [ "$status" == "255" ]; then goodbye
                    else
                      status="loop"
                    fi
                  else
                    option="$option ${host}/${newmask}:$port"
                    status="not a loop"
                  fi
                fi
              done
            fi
          done
          ;;
        *)
        esac
      fi
    done
    permit_opt=`echo $option`
    status="natquestion"
    ;;

  'natquestion')
    dialog --title "Internet Connection Sharing" $DEFAULT_NO --yesno "Do you wish to share your Internet connection with a private internal network?" \
    6 55

    status=$?
    if [ "$status" == "255" ]; then goodbye
    elif [ "$status" == "0" ]; then
      dialog $CANCEL_BACK --title "List Internal Interfaces" --inputbox "Enter one or more ethernet interfaces connected to private internal networks in a space delimited list. Example: \"eth1 eth2\"" \
      9 55 2> $TMPFILE
      status=$?

      if [ "$status" == "255" ]; then goodbye
      elif [ "$status" == "0" ]; then
        int_iface_opt=`cat $TMPFILE`

	if [ -n "$int_iface_opt" ]; then
	  dialog --title "Dial-up Information" $DEFAULT_NO --yesno "Does this system access the Internet through a telephone dial-up modem?  This information is required in order to configure Internet connection sharing and will not effect your Internet access in any way." \
	  9 55
      
	  status=$?
	  if [ "$status" == "255" ]; then goodbye
	  elif [ "$status" == "0" ]; then
	    dyn_iface_opt="ppp0"
	  fi
	fi
        status="trustednet"
      else
        status="natquestion"
      fi
    else
      status="trustednet"
    fi
    ;;

  'trustednet')
    if [ "X$int_iface_opt" == "X" ]; then
      xtratxt=""
      height="14"
    else
      xtratxt=" (besides existing private internal networks)"
      height="15"
    fi
    status="loop"
    while [ "$status" == "loop" ]; do
      dialog --title "Trusted Networks" --inputbox "If there are any hosts or networks${xtratxt} that should be able to bypass the firewall altogether and connect to any services running on this system, please list them here.  This might include hosts allowed to connect here for administrative purposes.  Format: <host or network address>[/<netmask>]  Example: \"207.198.61.33 128.173.0.0/16\"" \
    $height 55 2> $TMPFILE

      status=$?
      if [ "$status" == "255" ]; then goodbye
      elif [ "$status" == "0" ]; then
	for combo in `cat $TMPFILE` ; do
	  if [ "X`echo $combo | cut -s -f 1 -d '/'`" == "X" ]; then
	    option="$permit_opt $combo"
	    permit_opt=`echo $option`
	    status="not a loop"
	  else
	    host=`echo $combo | cut -s -f 1 -d '/'`
	    mask=`echo $combo | cut -s -f 2 -d '/'`
	    newmask=`make_mask $mask`
	    if [ "$newmask" == "-1" ]; then
	      dialog --title "Invalid Bitmask" --msgbox "The host/netmask you specified (${host}/${mask}) was invalid.  Re-enter the complete full-access list." \
	      7 55
	      status=$?
	      if [ "$status" == "255" ]; then goodbye
		status="loop"
	      fi
	    else
	      option="$permit_opt ${host}/${newmask}"
	      permit_opt=`echo $option`
	      status="not a loop"
	    fi
	  fi
	done
      fi
    done
    status="writefile"
    ;;

  'debug')
    echo "PERMIT: $permit_opt"
    echo "INTERNAL_INTERFACES: $int_iface_opt"
    echo "DYNAMIC_INTERFACES: $dyn_iface_opt"
    read junk
    status="writefile"
    ;;

  'test')
  dialog --title "System Configuration Testing" --yesno "Your firewall is now ready to be installed.  Would you like to verify your system configuration first?  This is a recommended step if this is the first time you are installing a firewall on this host.  The testing procedure will not modify your current firewall configuration.  Note that this opperation may take some time depending on the speed of your computer and the complexity of your firewall configuration." \
    13 55

    status=$?
    if [ "$status" == "255" ]; then goodbye
    elif [ "$status" == "0" ]; then
      clear
      echo "Running './rc.firewall check'.  Output will follow ..."
      echo
      sh $FW_TMPFILE check
      status=$?

      if [ "$status" != "0" ]; then
	echo
	echo "Errors were detected in your system configuration."
	echo "See the output above for specific details."
	echo
	echo "A copy of the Linux Firewall initialization script preconfigured by this"
	echo "program is located in $FW_TMPFILE"
	echo
	rm -f $TMPFILE > /dev/null 2>&1
	exit 1
      fi

      echo
      echo -n "Press any key to continue ... "
      read -rsn1
    fi
    status="install"
  ;;

  'install')
  dialog --title "Firewall Installation" --yesno "The firewall is now ready to be enabled.  Your system configuration will also be modified so that the firewall will be started each time your computer is booted.  If you choose not to continue, a copy of the Linux Firewall initialization script, preconfigured by this program, can be found here: '$FW_TMPFILE'.  Would you like to continue?" \
    12 55
    
    status=$?
    if [ "$status" == "255" ]; then goodbye
    elif [ "$status" == "0" ]; then
      if [ -f $FW_INSTALL ]; then
        mv $FW_INSTALL ${FW_INSTALL}.old
      fi

      mv $FW_TMPFILE $FW_INSTALL
      status=$?
      if [ "$status" != "0" ]; then
	clear
	echo "INSTALLATION FAILED with the following message:"
	echo
	echo "\"Unable to write file to $FW_INSTALL.\""
	echo "A copy of the Linux Firewall initialization script preconfigured by this"
	echo "program is located in $FW_TMPFILE."
	echo
	rm -f $TMPFILE > /dev/null 2>&1
	exit 1
      fi

      if [ -f /etc/rc.d/rc.local ]; then
        grep $FW_INSTALL /etc/rc.d/rc.local > /dev/null 2>&1 || cat << EOF >> /etc/rc.d/rc.local

if [ -x $FW_INSTALL ]; then
  $FW_INSTALL $INIT
fi
EOF
	clear
	if [ "$INIT" == "fast" ]; then
	  echo "$FW_INSTALL save"
	  echo
	  $FW_INSTALL save
	  echo
	fi
	echo "$FW_INSTALL $INIT"
	echo
	$FW_INSTALL $INIT
	echo
	echo "                         *** Installation Complete ***"
	echo
	echo "The firewall is now running on your system.  The firewall initialization"
	echo "script has been installed here: $FW_INSTALL"
	echo "and will run each time you boot your system.  Advanced users can modify their"
	echo "firewall configuration by configuring the above file with any text editor."
	echo "After making changes you will need to run the rc.firewall script again for"
	echo "changes to take effect."
	echo
	echo "For more information, please visit:"
	echo
	echo "   http://projectfiles.com/firewall/"
	echo
	rm -f $TMPFILE > /dev/null 2>&1
	exit
      else
	clear
	echo "INSTALLATION FAILED with the following message:"
	echo
	echo "\"Unable to write information to /etc/rc.d/rc.local.  If your distribution does"
	echo "not have an /etc/rc.d/rc.local (e.i. debian) then bug us to add support for"
	echo "your distribution.\""
	echo
	echo "A copy of the Linux Firewall initialization script preconfigured by this"
	echo "program is located in $FW_TMPFILE."
	echo
	rm -f $TMPFILE > /dev/null 2>&1
	exit 1
      fi
    fi
    status="exit"
  ;;

  'writefile')

    ### FOR INTERNAL USE.
    ### Place the following AFTER the escaped firewall script ...
     #FIREWALL_END_OF_FILE
     #  
     #  chmod $FW_PERM $FW_TMPFILE
     #  status="test"
     #  ;;
     #
     #  *)
     #    goodbye
     #  esac
     #done
     #
     #goodbye
    ### Add in the following variables in the config section:
    ### permit_opt, int_iface_opt, and dyn_iface_opt

    cat << FIREWALL_END_OF_FILE > $FW_TMPFILE
#!/bin/bash
#
# rc.firewall Linux Firewall version 2.0rc9 -- 05/02/03
# http://projectfiles.com/firewall/                                
#
# Copyright (C) 2001-2003 Scott Bartlett <srb@mnsolutions.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.          
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details:
# http://www.gnu.org/licenses/gpl.html
#
#####################################
# -- Basic Configuration Options -- #
#####################################
#
# NOTE: All lists are delimited by single spaces, eg "eth0 eth1 ppp0".
#
# The PERMIT option below allows remote access to this machine in the three
# ways listed below.  Note that by default hosts in internal networks are
# already allowed to connect to all services on the firewall.
# 1.) Listed PORTS will be open to ANY connecting host.  Protocols 'tcp' and
# 'udp' can optionally be specified.  If no protocol is specified, then
# connections using either protocol will be accepted on the given port(s).
# Format: <port or port-range>[/<protocol>]
# Example: PERMIT="80/tcp 53 2400-2500/tcp"
# 2.) Listed NETWORKS or HOSTS will be allowed to connect to ANY service
# on the firewall itself.  This option should be used to specify machines
# allowed to connect for administrative purposes.
# Format: <host or network address>[/<netmask>]
# Example: PERMIT="207.198.61.33 128.173.0.0/16"
# NOTE (for advanced users):  These networks and hosts will also be allowed to
# bypass DENY_OUTBOUND and ALLOW_INBOUND restrictions for Linux routers.
# 3.) Connections can be allowed from specific networks to specific ports by
# listing entries in the following format:
# Format:<host or network address>[/<netmask>]:<port or port-range>[/<protocol>]
# Example: PERMIT="198.82.0.0/16:80/tcp" -- (Allow web traffic from 198.82.*.*)

PERMIT="$permit_opt"

# List internal (private) interfaces here to allow this machine to act as a
# router.  All interfaces NOT listed here are considered external (public) 
# and will be automatically protected by the firewall.
# Example: INTERNAL_INTERFACES="eth1 eth2 brg0"

INTERNAL_INTERFACES="$int_iface_opt"

# List dial-up and other interfaces without a static IP address here.
# Interfaces configured to obtain an IP address automatically (DHCP) do not
# need to be listed here unless for some reason your DHCP client does not
# receive the same address each time it renews the lease.
# Example: DYNAMIC_INTERFACES="ppp0"

DYNAMIC_INTERFACES="$dyn_iface_opt"

# Most users do not need to change anything below this point.

########################################
# -- Advanced Configuration Options -- #
########################################

# ** DO NOT ** modify anything below unless you know what you are doing!!
# See online documentation at: http://projectfiles.com/firewall/config.html

DENY_OUTBOUND=""
ALLOW_INBOUND=""
BLACKLIST=""
STATIC_INSIDE_OUTSIDE=""
PORT_FORWARDS=""
PORT_FWD_ALL="yes"
PORT_FWD_ROUTED_NETWORKS="yes"
ADDITIONAL_ROUTED_NETWORKS=""
TRUST_ROUTED_NETWORKS="yes"
SHARED_INTERNAL="yes"
FIREWALL_IP=""
TRUST_LOCAL_EXTERNAL_NETWORKS="no"
DMZ_INTERFACES=""
NAT_EXTERNAL="yes"
ADDITIONAL_NAT_INTERFACES=""
IGNORE_INTERFACES=""
LOGGING="no"
REQUIRE_EXTERNAL_CONFIG="no"

############################################
# -- Advanced Firewall Behavior Options -- #
############################################

# The default settings provide the suggested firewall configuration.

NO_RP_FILTER_INTERFACES=""
INTERNAL_DHCP="yes"
RFC_1122_COMPLIANT="yes"
DROP_NEW_WITHOUT_SYN="no"
DUMP_TCP_ON_INIT="no"
TTL_STEALTH_ROUTER="no"
LOG_LIMIT="1/minute"
LOG_BURST="5"
LOG_LEVEL="notice"

###########################################################
# -- Nothing below this point should need modification -- #
###########################################################

# Set version information.

VERSION="2.0rc9"
COMPATIBLE_VERSIONS="2.0rc9"

# Welcome!

echo "-> Projectfiles.com Linux Firewall version \$VERSION running."

# Set PATH explicitly.

export PATH="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin"

# Tell everyone if we are loading data from an external configuration file.

if [ "\$1" == "update" ] || [ "\$1" == "load" ] || [ "\$1" == "fast" ] || \\
   [ "\$1" == "save" ] || [ "\$REQUIRE_EXTERNAL_CONFIG" == "yes" ] || \\
   ( [ "\$1" == "check" ] && [ -n "\$2" ] ); then
  if [ -z "\$2" ]; then
    CONFIG="/etc/firewall.conf"
  else
    CONFIG=\`echo \$2 | sed s#^\\./#\$PWD/#\`
  fi
  if [ "\$1" != "save" ]; then
    echo "-> Loading configuration from \$CONFIG."
  fi
fi

# Define exit/failure function.

exit_failure() {
  echo " [ FAILED ]"
  echo "-> FATAL: \$FAILURE" 1>&2
  if [ "\$1" != "check" ]; then
    echo "-> Firewall configuration ** ABORTED **." 1>&2
  fi
  exit 1
}

# Sanity checking section

echo -n "-> Performing sanity checks."

# Make sure we are running the script with root privileges.

if [ "\$EUID" != "0" ]; then
  FAILURE="You must have root privileges to configure the firewall."
  exit_failure \$1
fi

# Make sure we have iptables installed.

if (( \`iptables -V 2>&1 | grep -c "command not found"\` )); then
  FAILURE="Cannot find 'iptables' command.  Did you forget to install iptables?"
  exit_failure \$1
fi

# Add SysV style initialization support. (start and restart are the same as running the script without any arguments)

if [ "\$1" == "stop" ] || [ "\$1" == "clear" ]; then
  echo " [ PASSED ]" 
  iptables -t filter -F > /dev/null 2>&1
  iptables -t filter -X > /dev/null 2>&1
  iptables -t nat -F > /dev/null 2>&1
  iptables -t nat -X > /dev/null 2>&1
  iptables -t mangle -F > /dev/null 2>&1
  iptables -t mangle -X > /dev/null 2>&1
  iptables -t filter -P INPUT ACCEPT > /dev/null 2>&1
  iptables -t filter -P OUTPUT ACCEPT > /dev/null 2>&1
  iptables -t filter -P FORWARD ACCEPT > /dev/null 2>&1
  iptables -t nat -P PREROUTING ACCEPT > /dev/null 2>&1
  iptables -t nat -P POSTROUTING ACCEPT > /dev/null 2>&1
  iptables -t nat -P OUTPUT ACCEPT  > /dev/null 2>&1
  iptables -t mangle -P POSTROUTING ACCEPT > /dev/null 2>&1
  iptables -t mangle -P OUTPUT ACCEPT > /dev/null 2>&1
  iptables -t mangle -P PREROUTING ACCEPT > /dev/null 2>&1
  iptables -t mangle -P INPUT ACCEPT > /dev/null 2>&1
  iptables -t mangle -P FORWARD ACCEPT > /dev/null 2>&1
  if !(( \`which modprobe 2>&1 | grep -c "which: no modprobe in"\` )) && [ -a "/proc/modules" ]; then
    for MODULE in ipt_TTL iptable_mangle ipt_mark ipt_MARK ipt_MASQUERADE \\
                  ip_nat_irc ip_nat_ftp ipt_LOG ipt_limit ipt_REJECT \\
		  ip_conntrack_irc ip_conntrack_ftp ipt_state iptable_nat \\
		  iptable_filter ip_tables; do
      if (( \`lsmod | grep -c "\$MODULE"\` )); then
	rmmod \$MODULE > /dev/null 2>&1
      fi
    done
  fi
  echo "-> Firewall disabled."
  exit
fi

# Cleanup tcp session dump rules.  Note that ESTABLISHED TCP session can take up to 5 days to expire.

if [ "\$1" == "cleanup" ]; then
  echo " [ PASSED ]" 
  COUNT=\`iptables -nL INPUT | grep -c "tcp-reset"\`
  TAB=\$COUNT
  while [ "\$((COUNT--))" -gt "0" ]; do
    iptables -D INPUT 1
  done
  COUNT=\`iptables -nL FORWARD | grep -c "tcp-reset"\`
  while [ "\$((COUNT--))" -gt "0" ]; do
    iptables -D FORWARD 1
  done
  echo "-> Old TCP session dump rules expunged ( \$TAB )...."
  exit
fi

# Check external configuration file.

if [ "\$1" == "update" ] || [ "\$1" == "load" ] || [ "\$1" == "fast" ] || \\
 ( [ "\$REQUIRE_EXTERNAL_CONFIG" == "yes" ] && [ "\$1" != "save" ] ) || \\
 ( [ "\$1" == "check" ] && [ -n "\$2" ] ); then
  if [ -r "\$CONFIG" ]; then
    if (( \`head -1 "\$CONFIG" | grep -c "# Linux Firewall configuration -- http://projectfiles.com/firewall/"\` )); then
    CONFIG_VERSION='echo \`head -4 "\$CONFIG" | tail -1 | cut -d\\\\" -f2\`'
      if [ "\$1" == "update" ] || (( \$(echo "\$COMPATIBLE_VERSIONS" | grep -c "\`eval \$CONFIG_VERSION\`" ) )); then
	. \$CONFIG
      else
	if [ "\$CONFIG" == "/etc/firewall.conf" ]; then
	  CONFIG=""
	else
	  CONFIG=" \$CONFIG"
	fi
	FAILURE="Configuration file outdated.  Please run '\$0 update\$CONFIG'."
	exit_failure \$1
      fi
    else
      FAILURE="The configuration file '\$CONFIG' does not appear to be associated with this program.  Refusing to load data."
      exit_failure \$1
    fi
  else
    FAILURE="Cannot read from file '\$CONFIG'.  Did you forget to save your configuration with './rc.firewall save' or has the file moved?"
    exit_failure \$1
  fi
fi

# Make sure we have proc filesystem support.

if ! [ -a "/proc/version" ]; then
  FAILURE="proc filesystem support required.  Please mount /proc or add proc filesystem support in your kernel."
  exit_failure \$1
fi

# Create DUMP_TCP_ON_INIT function

dump_tcp() {
  echo -n "-> Dumping current TCP sessions...."
  if [ "\$1" != "fast" ]; then
   sleep 1	# Allow a few moments for that last message to be delivered before we reset remote connections.
  fi
  COUNT=10
  TAB=0
  NET=\`cat /proc/net/ip_conntrack | grep "^tcp" | grep ESTABLISHED | awk '{ gsub(/\\ /,"\\n"); print }'\`
  for ADDRESS in \`echo "\$NET" | sed -n \$COUNT~20p | cut -d= -f2\`; do
    if !(( \`echo \$INTERNAL_ADDRESSES \$EXTERNAL_ADDRESSES | grep -c "\$ADDRESS"\` )); then
      DEST=\`echo "\$NET" | sed -n \$((COUNT+1))~20p | cut -d= -f2 | head -1\`
      PORTS=\`echo "\$NET" | sed -n \$((COUNT+2))~20p | cut -d= -f2 | head -1\`
      DPORTS=\`echo "\$NET" | sed -n \$((COUNT+3))~20p | cut -d= -f2 | head -1\`
      iptables -I INPUT -s \$ADDRESS -d \$DEST -p tcp --sport \$PORTS --dport \$DPORTS -j REJECT --reject-with tcp-reset
      if [ "\$IS_ROUTER" == "yes" ]; then
	iptables -I FORWARD -s \$ADDRESS -d \$DEST -p tcp --sport \$PORTS --dport \$DPORTS -j REJECT --reject-with tcp-reset
      fi
      TAB=\$((TAB+1))
    fi
    COUNT=\$((COUNT+20))
  done
  echo "( \$TAB dumped )"
}

# Handle 'fast' argument.

if [ "\$1" == "fast" ]; then
  if (( \`which iptables-restore 2>&1 | grep -c "which: no iptables-restore in"\` )); then
    FAILURE="Required program 'iptables-restore' not found."
    exit_failure \$1
  fi
  echo " [ SKIPPED ]"
  echo "1" > /proc/sys/net/ipv4/conf/all/rp_filter
  for INTERFACE in \$NO_RP_FILTER_INTERFACES; do
    echo "0" > /proc/sys/net/ipv4/conf/\$INTERFACE/rp_filter
  done
  cat \$CONFIG | sed -n 40~1p | iptables-restore
  if [ -n "\$DYNAMIC_INTERFACES" ]; then
    echo "1" > /proc/sys/net/ipv4/ip_dynaddr
  else
    echo "0" > /proc/sys/net/ipv4/ip_dynaddr
  fi
  if [ "\$LOGGING" == "yes" ]; then
    echo "1" > /proc/sys/net/ipv4/conf/all/log_martians
  fi
  if [ -n "\$INTERNAL_INTERFACES" ] || [ -n "\$PORT_FORWARDS" ]; then
    echo "1" > /proc/sys/net/ipv4/ip_forward
  else
    echo "0" > /proc/sys/net/ipv4/ip_forward
  fi
  echo "-> Firewall configuration complete.  No sanity checking was performed."
  if [ "\$DUMP_TCP_ON_INIT" == "yes" ]; then
    dump_tcp fast
  fi
  exit
fi

# Create a few sanity checking functions.

check_network() {	# Checks NET variable.
  FAILURE=""
  HOST=\`echo "\$NET/" | cut -d/ -f1\`
  MASK=\`echo "\$NET/" | cut -d/ -f2\`	# Optional: Netfilter assumes /32 if not defined.
  if (( \`echo "\$NET/" | cut -d/ -f3 | grep -c "."\` )); then
    FAILURE="Syntax error"
    return 1
  fi
  if [ -z "\$HOST" ]; then
    FAILURE="Syntax error"
    return 1
  fi
  for OCTET in 1 2 3 4; do
    OCTET=\`echo "\$HOST." | cut -d. -f\$OCTET --output-delimiter=" "\`
    if [ -z "\$OCTET" ] || (( \`echo "\$OCTET" | grep -c "[^[:digit:]]"\` )) || [ "\$OCTET" -lt "0" ] || [ "\$OCTET" -gt "255" ]; then
      FAILURE="Network addresses must be in dotted decimal format"
      return 1
    fi
  done
  if (( \`echo "\$HOST." | cut -d. -f5 | grep -c "."\` )); then
    FAILURE="Network address must be in dotted decimal format"
    return 1
  fi
  if [ -n "\$MASK" ]; then
    if (( \`echo "\$MASK" | grep -c "[^[:digit:]]"\` )) || [ "\$MASK" -lt "0" ] || [ "\$MASK" -gt "32" ]; then
      FAILURE="Network mask must be between '/0' (0.0.0.0) and '/32' (255.255.255.255) inclusive"
      return 1
    fi
  else
    if (( \`echo "\$NET" | grep -c "/"\` )); then
      FAILURE="Mask expected but not found"
      return 1
    fi
  fi
}

check_ports() {		# Checks PORTS variable.
  FAILURE=""
  RANGE=\`echo "\$PORTS/" | cut -d/ -f1\`
  PROTOCOL=\`echo "\$PORTS/" | cut -d/ -f2\`
  if (( \`echo "\$PORTS/" | cut -d/ -f3 | grep -c "."\` )); then
    FAILURE="Syntax error"
    return 1
  fi
  if [ -z "\$RANGE" ]; then
    FAILURE="Syntax error"
    return 1
  fi
  if (( \`echo "\$RANGE" | grep -c "[^[:digit:]]"\` )) || [ "\$RANGE" -lt "1" ] || [ "\$RANGE" -gt "65535" ]; then
    for PORT in \`echo "\$RANGE-" | cut -d- -f1,2 --output-delimiter=" "\`; do
      if (( \`echo "\$PORT" | grep -c "[^[:digit:]]"\` )) || [ "\$PORT" -lt "1" ] || [ "\$PORT" -gt "65535" ]; then
	FAILURE="Valid port numbers must be between 1 and 65535"
	return 1
      fi
    done
    if (( \`echo "\$RANGE-" | cut -d- -f3 | grep -c "."\` )); then
      FAILURE="Syntax error"
      return 1
    fi
  fi
  if [ -n "\$PROTOCOL" ]; then
    if ! ( [ "\$PROTOCOL" == "tcp" ] || [ "\$PROTOCOL" == "udp" ] ); then
      FAILURE="Invalid protocol"
      return 1
    fi
  else
    if (( \`echo "\$PORTS" | grep -c "/"\` )); then
      FAILURE="Protocol expected but not found"
      return 1
    fi
  fi
}

xbits() {       # Set XBITS to the number of network bits that two addresses NET and NET1 are the same.
  XBITS=0
  for NUM in 1 2 3 4; do
    OCTET=\`echo "\$NET./" | cut -d/ -f1 | cut -d. -f\$NUM\`
    OCTET1=\`echo "\$NET1./" | cut -d/ -f1 | cut -d. -f\$NUM\`
    if [ "\$OCTET" == "\$OCTET1" ]; then
      XBITS=\$((XBITS + 8))
      continue
    fi
    for SUBTRACT in 128 64 32 16 8 4 2 1; do
      if [ "\$((OCTET - SUBTRACT))" -ge "0" ] && [ "\$((OCTET1 - SUBTRACT))" -ge "0" ]; then
        XBITS=\$((XBITS + 1))
        OCTET=\$((OCTET - SUBTRACT))
        OCTET1=\$((OCTET1 - SUBTRACT))
      elif [ "\$((OCTET - SUBTRACT))" -lt "0" ] && [ "\$((OCTET1 - SUBTRACT))" -lt "0" ]; then
        XBITS=\$((XBITS + 1))
      else
        return
      fi
    done
  done
}

# Save selected variable settings if we are going to back up our configuration.

if [ "\$1" == "save" ] || [ "\$1" == "update" ]; then
  if (( \`which iptables-save 2>&1 | grep -c "which: no iptables-save in"\` )); then
    FAILURE="iptables-save not found; required for '\$1' argument."
    exit_failure \$1
  fi
  if [ "\$1" == "update" ]; then
    PERMIT=\`echo \$PERMIT \$TRUSTED_NETWORKS \$OPEN_PORTS\`
    OPEN_PORTS=""
  fi
  ORIG_PERMIT="\$PERMIT"
  ORIG_INTERNAL_INTERFACES="\$INTERNAL_INTERFACES"
  ORIG_PORT_FORWARDS="\$PORT_FORWARDS"
  ORIG_ALLOW_INBOUND="\$ALLOW_INBOUND"
  ORIG_DENY_OUTBOUND="\$DENY_OUTBOUND"
  ORIG_DYNAMIC_INTERFACES="\$DYNAMIC_INTERFACES"
  ORIG_STATIC_INSIDE_OUTSIDE="\$STATIC_INSIDE_OUTSIDE"
fi

# Add DMZ interfaces to list of internal interfaces.

if [ -n "\$DMZ_INTERFACES" ]; then
  INTERNAL_INTERFACES="\$INTERNAL_INTERFACES \$DMZ_INTERFACES"
fi
  
# Remove duplicate internal interfaces.

if [ -n "\$INTERNAL_INTERFACES" ]; then
  for INTERFACE in \$INTERNAL_INTERFACES; do
    if !(( \`echo "\$MOD_INTERFACES" | grep -c "\$INTERFACE"\` )); then
      MOD_INTERFACES="\$MOD_INTERFACES \$INTERFACE"
    fi
  done
  INTERNAL_INTERFACES=\`echo \$MOD_INTERFACES\`
fi

# Determine if we are a router.

if [ -n "\$INTERNAL_INTERFACES" ] || [ -n "\$PORT_FORWARDS" ]; then
  IS_ROUTER="yes"
fi

# Sanity check PERMIT and BLACKLIST.

for PARAM in PERMIT BLACKLIST; do
  if [ "\$PARAM" == "PERMIT" ]; then
    ITEM="\$PERMIT"
  else
    ITEM="\$BLACKLIST"
  fi
  for NETWORK in \$ITEM; do
    NET=\`echo "\$NETWORK:" | cut -d: -f1\`
    PORTS=\`echo "\$NETWORK:" | cut -d: -f2\`
    if (( \`echo "\$NETWORK:" | cut -d: -f3 | grep -c "."\` )); then
      FAILURE="Syntax error in \$PARAM."
      exit_failure \$1
    fi
    if ! check_network; then
      PORTS="\$NET"
      FAIL="\$FAILURE in \$PARAM."
      if ! check_ports; then
	FAILURE="\$FAIL"
	exit_failure \$1
      fi
    fi
    if [ -n "\$PORTS" ]; then
      if ! check_ports; then
	FAILURE="\$FAILURE in \$PARAM."
	exit_failure \$1
      fi
    fi
  done
done

echo -n "."

# Remove entries with ports and put them in their own variable.

if [ -n "\$PERMIT" ]; then
  for NETWORK in \$PERMIT; do
    NET=\`echo "\$NETWORK:" | cut -d: -f1\`
    PORTS=\`echo "\$NETWORK:" | cut -d: -f2\`
    if [ -z "\$PORTS" ]; then
      if ! check_network; then
        OPEN_PORTS="\$OPEN_PORTS \$NET"
      else
        TEMP_PERMIT="\$TEMP_PERMIT \$NET"
      fi
    else
      PROTOCOL=\`echo "\$PORTS/" | cut -d/ -f2\`
      if [ "\$PROTOCOL" == "tcp" ] || [ "\$PROTOCOL" == "udp" ]; then
        TRUSTED_PORTS="\$TRUSTED_PORTS \$NET:\$PORTS/\$PROTOCOL"
      else
        TRUSTED_PORTS="\$TRUSTED_PORTS \$NET:\$PORTS/tcp"
        TRUSTED_PORTS="\$TRUSTED_PORTS \$NET:\$PORTS/udp"
      fi
    fi
  done
  PERMIT=\`echo \$TEMP_PERMIT\`
  TRUSTED_PORTS=\`echo \$TRUSTED_PORTS\`
  OPEN_PORTS=\`echo \$OPEN_PORTS\`
fi

# Sanity check additional routed networks.

if [ -n "\$INTERNAL_INTERFACES" ]; then
  for NET in \$ADDITIONAL_ROUTED_NETWORKS; do
    if ! check_network; then
      FAILURE="\$FAILURE in ADDITIONAL_ROUTED_NETWORKS."
      exit_failure \$1
    fi
  done
fi

# Sanity check port forwarding definitions.  Protocol and destination ports are optional.

if [ -n "\$PORT_FORWARDS" ]; then
  for FORWARD in \$PORT_FORWARDS; do
    if (( \`echo "\$FORWARD:" | cut -d: -f5 | grep -c "."\` )); then
      FAILURE="Syntax error in PORT_FORWARDS."
      exit_failure \$1
    fi
    PROTOCOL=\`echo "\$FORWARD:" | cut -d: -f1\`
    if [ "\$PROTOCOL" != "tcp" ] && [ "\$PROTOCOL" != "udp" ]; then
      COUNT="1"
      MOD_FORWARDS="\$MOD_FORWARDS tcp:\$FORWARD udp:\$FORWARD"
      PROT=""
    else
      COUNT="0"
      MOD_FORWARDS="\$MOD_FORWARDS \$FORWARD"
      PROT="/\$PROTOCOL"
    fi
    PORTS=\`echo "\$FORWARD:" | cut -d: -f\$((2-COUNT))\`
    FAILURE="Invalid syntax "
    if ! check_ports || [ -n "\$PROTOCOL" ]; then
      FAILURE="\$FAILURE in PORT_FORWARDS."
      exit_failure \$1
    fi
    if [ "\$PORT_FWD_ALL" == "yes" ]; then
      for TAB in NULL; do
	for PORT in \$OPEN_PORTS; do
	  if [ "\$PORT" == "\${PORTS}\$PROT" ]; then
	    break 2
	  fi
	done
	OPEN_PORTS="\$OPEN_PORTS \${PORTS}\$PROT"
      done
    fi
    NET=\`echo "\$FORWARD:" | cut -d: -f\$((3-COUNT))\`
    FAILURE="Destination must be a single host"
    if ! check_network || [ -n "\$MASK" ]; then
      FAILURE="\$FAILURE in PORT_FORWARDS."
      exit_failure \$1
    fi
    PORTS=\`echo "\$FORWARD:" | cut -d: -f\$((4-COUNT))\`
    if [ -n "\$PORTS" ]; then
      FAILURE="Invalid syntax"
      if ! check_ports || [ -n "\$PROTOCOL" ]; then
	FAILURE="\$FAILURE in PORT_FORWARDS."
	exit_failure \$1
      fi
    fi
  done
  PORT_FORWARDS=\`echo \$MOD_FORWARDS\`
  OPEN_PORTS=\`echo \$OPEN_PORTS\`
fi

# Sanity check open ports.  Expand undefined protocols into tcp and udp.

if [ -n "\$OPEN_PORTS" ]; then
  for PORTS in \$OPEN_PORTS; do
    if ! check_ports; then
      FAILURE="\$FAILURE in OPEN_PORTS."
      exit_failure \$1
    fi
    if [ "\$PROTOCOL" == "tcp" ] || [ "\$PROTOCOL" == "udp" ]; then
      MOD_PORTS="\$MOD_PORTS \$PORTS"
    else
      MOD_PORTS="\$MOD_PORTS \$PORTS/tcp \$PORTS/udp"
    fi
  done
  OPEN_PORTS=\`echo \$MOD_PORTS\`
fi

# Sanity check static inside,outside translations.

if [ -n "\$STATIC_INSIDE_OUTSIDE" ]; then
  MOD_STATIC=""
  for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
    if (( \`echo "\$FORWARD:" | cut -d: -f3 | grep -c "."\` )); then
      FAILURE="Syntax error in STATIC_INSIDE_OUTSIDE."
      exit_failure \$1
    fi
    NET=\`echo "\$FORWARD:" | cut -d: -f1\`
    if ! check_network; then
      FAILURE="\$FAILURE in STATIC_INSIDE_OUTSIDE."
      exit_failure \$1
    fi
    NET1=\`echo \$NET | cut -d\\/ -f1\`
    STROKE="\$MASK"
    NET=\`echo "\$FORWARD:" | cut -d: -f2\`
    if ! check_network; then
      FAILURE="\$FAILURE in STATIC_INSIDE_OUTSIDE."
      exit_failure \$1
    fi
    if [ -n "\$MASK" ]; then
      if [ "\$STROKE" != "\$MASK" ]; then
	FAILURE="If outside address in STATIC_INSIDE_OUTSIDE has a netmask, it must be the same as the inside address."
	exit_failure \$1
      fi
      if [ "\$MASK" -lt "24" ]; then
	FAILURE="Networks larger than class C (254 hosts) are not supported on the OUTSIDE address of STATIC_INSIDE_OUTSIDE."
	exit_failure \$1
      fi
      TAB="1"
      NET=\`echo \$NET | cut -d\\/ -f1\`
      COUNT=\`echo \$NET | cut -d. -f4\`
      if [ "\$COUNT" -ne "\`echo \$NET1 | cut -d. -f4\`" ]; then
	FAILURE="When using a subnet mask on the OUTSIDE address in STATIC_INSIDE_OUTSIDE, last octet of both inside and outside addresses must be the same."
	exit_failure \$1
      fi
      NET1=\`echo \$NET1 | cut -d. -f1,2,3\`
      NET=\`echo \$NET | cut -d. -f1,2,3\`
      while [ "\$MASK" -lt "32" ]; do
	TAB=\$((TAB * 2))
	MASK=\$((MASK+1))
      done
      STROKE="\$TAB"
      while [ "\$TAB" -gt "0" ]; do
	TAB=\$((TAB-1))
	OCTET=\$((COUNT-(COUNT%STROKE)+TAB))
	if [ "\$OCTET" != "0" ] && [ "\$OCTET" != "255" ]; then
	  MOD_STATIC="\$MOD_STATIC \$NET1.\$OCTET:\$NET.\$OCTET"
	fi
      done
    else
      MOD_STATIC="\$MOD_STATIC \$FORWARD"
    fi
  done
  STATIC_INSIDE_OUTSIDE=\`echo \$MOD_STATIC\`
fi

# Sanity check FIREWALL_IP.

for ADDRESS in \$FIREWALL_IP; do
  if (( \`echo "\$ADDRESS:" | cut -d: -f3 | grep -c "."\` )); then
    FAILURE="Syntax error in FIREWALL_IP."
    exit_failure \$1
  fi
  NET=\`echo "\$ADDRESS:" | cut -d: -f1\`
  if ! check_network; then
    FAILURE="\$FAILURE in FIREWALL_IP."
    exit_failure \$1
  fi
  if [ -n "\$MASK" ]; then
    FAILURE="FIREWALL_IP may not contain network masks."
    exit_failure \$1
  fi
  NET=\`echo "\$ADDRESS:" | cut -d: -f2\`
  if ! check_network; then
    FAILURE="\$FAILURE in FIREWALL_IP."
    exit_failure \$1
  fi
  if [ -n "\$MASK" ]; then
    FAILURE="FIREWALL_IP may not contain network masks."
    exit_failure \$1
  fi
done

# Make sure dynamic, nat, and rp_filter interface definitions do not use IP aliases.

if (( \`echo "\$INTERNAL_INTERFACES \$DYNAMIC_INTERFACES \$NO_RP_FILTER_INTERFACES \$ADDITIONAL_NAT_INTERFACES" | grep -c ":"\` )); then
  FAILURE="Definitions cannot contain IP aliases."
  exit_failure \$1
fi
  
# Obtain list of external interfaces.

EXTERNAL_INTERFACES=\`ifconfig | grep "^[[:alpha:]]" | cut -d\\  -f1 | sed s/^lo.*//\`
PARAM=\`echo \$EXTERNAL_INTERFACES\`
for INTERFACE in \$INTERNAL_INTERFACES; do
  EXTERNAL_INTERFACES=\`echo "\$EXTERNAL_INTERFACES" | sed s/^\$INTERFACE//\`
done
for INTERFACE in \$PARAM; do
  if !(( \`echo "\$EXTERNAL_INTERFACES \$INTERNAL_INTERFACES" | grep -c "\$INTERFACE"\` )); then
    INTERNAL_INTERFACES="\$INTERNAL_INTERFACES \$INTERFACE"
  fi
done
EXTERNAL_INTERFACES=\`echo \$EXTERNAL_INTERFACES | sed 's/[^0-9]\\:[0-9]\\+//g'\`	# Cleanup.
for INTERFACE in \$IGNORE_INTERFACES; do
  if !(( \`echo "\$EXTERNAL_INTERFACES" | grep -c "\$INTERFACE"\` )); then
    FAILURE="Interface specified to IGNORE was not found.  Check the configuration."
    exit_failure \$1
  else
    EXTERNAL_INTERFACES=\`echo \$EXTERNAL_INTERFACES | sed s#\$INTERFACE##g\`
  fi
done
EXTERNAL_INTERFACES=\`echo \$EXTERNAL_INTERFACES\`	# Remove whitespace.

echo -n "."

# Divide internal and external interfaces into static and dynamic groups.

for INTERFACE in \$INTERNAL_INTERFACES; do
  if (( \`echo "\$DYNAMIC_INTERFACES" | grep -c "\$INTERFACE"\` )); then
    if [ -n "\$DMZ_INTERFACES" ]; then
      FAILURE="Cannot have dynamic internal interfaces with a DMZ."
      exit_failure \$1
    fi
    DYNAMIC_INTERNAL_INTERFACES="\$DYNAMIC_INTERNAL_INTERFACES \$INTERFACE"
  else
    STATIC_INTERNAL_INTERFACES="\$STATIC_INTERNAL_INTERFACES \$INTERFACE"
  fi
done
for INTERFACE in \$EXTERNAL_INTERFACES; do
  if (( \`echo "\$DYNAMIC_INTERFACES" | grep -c "\$(echo \$INTERFACE | cut -d: -f1)"\` )); then
    if !(( \`echo "\$INTERFACE" | grep -c ":"\` )); then
      DYNAMIC_EXTERNAL_INTERFACES="\$DYNAMIC_EXTERNAL_INTERFACES \$INTERFACE"
    fi
  else
    STATIC_EXTERNAL_INTERFACES="\$STATIC_EXTERNAL_INTERFACES \$INTERFACE"
  fi
done
for INTERFACE in \$DYNAMIC_INTERFACES; do
  if !(( \`echo "\$INTERNAL_INTERFACES \$EXTERNAL_INTERFACES" | grep -c "\$INTERFACE"\` )); then
    DYNAMIC_EXTERNAL_INTERFACES="\$DYNAMIC_EXTERNAL_INTERFACES \$INTERFACE"
  fi
done
DYNAMIC_INTERNAL_INTERFACES=\`echo \$DYNAMIC_INTERNAL_INTERFACES\`
DYNAMIC_EXTERNAL_INTERFACES=\`echo \$DYNAMIC_EXTERNAL_INTERFACES\`
STATIC_INTERNAL_INTERFACES=\`echo \$STATIC_INTERNAL_INTERFACES\`
STATIC_EXTERNAL_INTERFACES=\`echo \$STATIC_EXTERNAL_INTERFACES\`

# If we are configured to be a router, then make sure we have somewhere to route traffic.

if [ -n "\$INTERNAL_INTERFACES" ] && ( [ -z "\$STATIC_EXTERNAL_INTERFACES" ] && [ -z "\$DYNAMIC_EXTERNAL_INTERFACES" ] ); then
  if (( \`echo "\$INTERNAL_INTERFACES" | wc -w | grep -c "1"\` )); then
    FAILURE="Routing enabled, with no place to route traffic!  Did you forget to ifconfig an interface, or list DYNAMIC_INTERFACES?"
    exit_failure \$1
  fi
fi

# Obtain list of interfaces to NAT outbound connections

if [ "\$IS_ROUTER" == "yes" ]; then
  if [ "\$NAT_EXTERNAL" == "yes" ]; then
    for INTERFACE in \$STATIC_EXTERNAL_INTERFACES; do
      if !(( \`echo "\$INTERFACE" | grep -c ":"\` )); then
	STATIC_NAT_INTERFACES="\$STATIC_NAT_INTERFACES \$INTERFACE"
      fi
    done
    for INTERFACE in \$DYNAMIC_EXTERNAL_INTERFACES; do
      if !(( \`echo "\$INTERFACE" | grep -c ":"\` )); then
	DYNAMIC_NAT_INTERFACES="\$DYNAMIC_NAT_INTERFACES \$INTERFACE"
      fi
    done
  fi
  for INTERFACE in \$ADDITIONAL_NAT_INTERFACES; do
    if (( \`echo "\$DYNAMIC_INTERFACES" | grep -c "\$INTERFACE"\` )); then
      DYNAMIC_NAT_INTERFACES="\$DYNAMIC_NAT_INTERFACES \$INTERFACE"
    else
      STATIC_NAT_INTERFACES="\$STATIC_NAT_INTERFACES \$INTERFACE"
    fi
  done
fi

# If we are a router, check that all static internal interfaces are up.

for INTERFACE in \$STATIC_INTERNAL_INTERFACES; do
  if !(( \`ifconfig | grep -c "^\$INTERFACE\\ "\` )); then
    FAILURE="A static internal interface is down.  Did you forgot to configure interfaces before running the firewall?"
    exit_failure \$1
  fi
done

# Obtain list of NAT addresses if we are a router doing nat.

if [ -n "\$STATIC_NAT_INTERFACES" ]; then
  for INTERFACE in \$STATIC_NAT_INTERFACES; do
    ADDRESS=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "inet" | cut -d: -f2 | cut -d\\  -f1 | head -1\`
    if [ -z "\$ADDRESS" ]; then
      echo " [ WAIT ]"
      echo -n "-> \$INTERFACE has no IP address.  Waiting for DHCP"
      for COUNT in 1 2 3 4 5 6 7 8 9 10; do
	sleep 1
	echo -n "."
	ADDRESS=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "inet" | cut -d: -f2 | cut -d\\  -f1 | head -1\`
	if [ -n "\$ADDRESS" ]; then
	  echo " [ FOUND ]"
	  break
	else
	  if [ "\$COUNT" == "10" ]; then
	    echo " [ MISSING ]"
	    echo "-> WARNING: IP address for \$INTERFACE not found.  Coverting to dynamic interface."
	    DYNAMIC_EXTERNAL_INTERFACES="\$DYNAMIC_EXTERNAL_INTERFACES \$INTERFACE"
	    DYNAMIC_INTERFACES="\$DYNAMIC_INTERFACES \$INTERFACE"
	    if [ "\$NAT_EXTERNAL" == "yes" ]; then
	      DYNAMIC_NAT_INTERFACES="\$DYNAMIC_NAT_INTERFACES \$INTERFACE"
	    fi
	    for INT in \$STATIC_EXTERNAL_INTERFACES; do
	      if [ "\$INTERFACE" != "\$INT" ]; then
		MOD_STATIC_EXTERNAL_INTERFACES="\$MOD_STATIC_EXTERNAL_INTERFACES \$INTERFACE"
	      fi
	    done
	    STATIC_EXTERNAL_INTERFACES=\`echo \$MOD_STATIC_EXTERNAL_INTERFACES\`
	  fi
	fi
      done
      echo -n "-> Continuing sanity checks.."
    else
      MOD_STATIC_NAT_INTERFACES="\$MOD_STATIC_NAT_INTERFACES \$INTERFACE"
      if [ -n "\$FIREWALL_IP" ]; then
	for FORWARD in \$FIREWALL_IP; do
	  if [ \`echo "\$FORWARD" | cut -d: -f1\` == "\$ADDRESS" ]; then
	    ADDRESS=\`echo "\$FORWARD" | cut -d: -f2\`
	  fi
	done
      fi
      NAT_ADDRESSES="\$NAT_ADDRESSES \$ADDRESS"
    fi
  done
  STATIC_NAT_INTERFACES=\`echo \$MOD_STATIC_NAT_INTERFACES\`
  NAT_ADDRESSES=\`echo \$NAT_ADDRESSES\`
fi

echo -n "."

# Determine if this is a modular kernel, if so modprobe the required modules.

if !(( \`which modprobe 2>&1 | grep -c "which: no modprobe in"\` )) && [ -a "/proc/modules" ]; then
  if (( \`lsmod | grep -c "ipchains"\` )); then
    rmmod ipchains > /dev/null 2>&1
  fi
  REQUIRED_MODULES="ip_tables ip_conntrack ipt_state iptable_filter ip_conntrack_irc ip_conntrack_ftp"
  if [ "\$RFC_1122_COMPLIANT" == "yes" ]; then
    REQUIRED_MODULES="\$REQUIRED_MODULES ipt_REJECT"
  fi
  if [ "\$LOGGING" == "yes" ]; then
    REQUIRED_MODULES="\$REQUIRED_MODULES ipt_LOG ipt_limit"
  fi
  if [ "\$IS_ROUTER" == "yes" ]; then
    if [ -n "\$STATIC_NAT_INTERFACES" ] || [ -n "\$DYNAMIC_NAT_INTERFACES" ] || \\
       [ -n "\$PORT_FORWARDS" ] || [ -n "\$STATIC_INSIDE_OUTSIDE" ]; then
      REQUIRED_MODULES="\$REQUIRED_MODULES iptable_nat ip_nat_irc ip_nat_ftp"
      if [ -n "\$DYNAMIC_NAT_INTERFACES" ] || \\
	 ( [ -n "\$DYNAMIC_INTERFACES" ] && ( [ -n "\$PORT_FORWARDS" ] || [ -n "\$STATIC_INSIDE_OUTSIDE" ] ) ); then
	REQUIRED_MODULES="\$REQUIRED_MODULES ipt_MASQUERADE"
      fi
    fi
    if [ -n "\$PORT_FORWARDS" ] || [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
      REQUIRED_MODULES="\$REQUIRED_MODULES iptable_mangle"
    fi
    if [ -n "\$PORT_FORWARDS" ]; then
      REQUIRED_MODULES="\$REQUIRED_MODULES ipt_mark ipt_MARK"
    fi
    if [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
      REQUIRED_MODULES="\$REQUIRED_MODULES ipt_TTL"
    fi
  fi
  for MODULE in \$REQUIRED_MODULES; do
    if (( \`modprobe -l | grep -c "\$MODULE"\` )); then
      modprobe \$MODULE > /dev/null 2>&1
    fi
  done
fi

# Obtain list of internal networks with subnet masks corresponding to internal interfaces.

if [ -n "\$STATIC_INTERNAL_INTERFACES" ]; then
  for INTERFACE in \$STATIC_INTERNAL_INTERFACES; do
    STROKE="0"
    MASK=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "Mask" | cut -d: -f4 | head -1\`
    for OCTET in 1 2 3 4; do
      BINARY=\`echo "\$MASK" | cut -d. -f\$OCTET\`
      for SUBTRACT in 128 64 32 16 8 4 2 1; do
	if [ "\$((BINARY - SUBTRACT))" -ge "0" ]; then
	  BINARY=\$((BINARY - SUBTRACT))
	  STROKE=\$((STROKE + 1))
	fi
     done
    done
    ADDRESS=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "inet" | cut -d: -f2 | cut -d\\  -f1 | head -1\`
    INTERNAL_ADDRESSES="\$INTERNAL_ADDRESSES \$ADDRESS"
    INTERNAL_NETWORKS="\$INTERNAL_NETWORKS \$ADDRESS/\$STROKE"
    if [ -z "\$DMZ_INTERFACES" ] || !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$INTERFACE"\` )); then
      NAT_NETWORKS="\$NAT_NETWORKS \$ADDRESS/\$STROKE"
    fi
  done
  INTERNAL_ADDRESSES=\`echo \$INTERNAL_ADDRESSES\`
  INTERNAL_NETWORKS=\`echo \$INTERNAL_NETWORKS\`
  NAT_NETWORKS=\`echo \$NAT_NETWORKS\`
fi

# Obtain a list of external addresses.

if [ -n "\$STATIC_EXTERNAL_INTERFACES" ]; then
  for INTERFACE in \$STATIC_EXTERNAL_INTERFACES; do
    STROKE="0"
    MASK=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "Mask" | cut -d: -f4 | head -1\`
    for OCTET in 1 2 3 4; do
      BINARY=\`echo "\$MASK" | cut -d. -f\$OCTET\`
      for SUBTRACT in 128 64 32 16 8 4 2 1; do
	if [ "\$((BINARY - SUBTRACT))" -ge "0" ]; then
	  BINARY=\$((BINARY - SUBTRACT))
	  STROKE=\$((STROKE + 1))
	fi
     done
    done
    ADDRESS=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "inet" | cut -d: -f2 | cut -d\\  -f1 | head -1\`
    EXTERNAL_ADDRESSES="\$EXTERNAL_ADDRESSES \$ADDRESS"
    EXTERNAL_NETWORKS="\$EXTERNAL_NETWORKS \$ADDRESS/\$STROKE"
  done
  EXTERNAL_ADDRESSES=\`echo \$EXTERNAL_ADDRESSES\`
  EXTERNAL_NETWORKS=\`echo \$EXTERNAL_NETWORKS\`
fi

# Make a table of interfaces for marking packets based on their incoming interface for port forwarding.

if [ -n "\$PORT_FORWARDS" ]; then
  COUNT="0"
  TAB="1"
  for INTERFACE in \$STATIC_INTERNAL_INTERFACES \$STATIC_EXTERNAL_INTERFACES; do
    COUNT=\$((COUNT + 1))
    ADDRESS=\`echo \$INTERNAL_ADDRESSES \$EXTERNAL_ADDRESSES | cut -d\\  -f\$COUNT\`
    # Do not forward packets destined for an address in STATIC_INSIDE_OUTSIDE.
    if !(( \`echo "\$STATIC_INSIDE_OUTSIDE" | awk '{ gsub(/\\ /,"\\n"); print }' | \\
            cut -d: -f2 | grep -c "\$ADDRESS"\` )); then
      if [ -n "\$FIREWALL_IP" ]; then
	# Nobody will ever use the address of the private network between us and our gateway for port forwarding.
	if (( \`echo "\$FIREWALL_IP" | awk '{ gsub(/\\ /,"\\n"); print }' | \\
	       cut -d: -f2 | grep -c "\$ADDRESS"\` )); then
	  continue
	fi
	if (( \`echo "\$FIREWALL_IP" | awk '{ gsub(/\\ /,"\\n"); print }' | \\
	       cut -d: -f1 | grep -c "\$ADDRESS"\` )); then
	  ADDRESS=\`echo "\$FIREWALL_IP" | awk '{ gsub(/\\ /,"\\n"); print }' | \\
	           grep "\$ADDRESS" | cut -d: -f2\`
	fi
      fi
      INTERFACE=\`echo "\$INTERFACE" | cut -d: -f1\`
      INTERFACE_TAB[\$TAB]="\$INTERFACE"
      ADDRESS_TAB[\$TAB]="\$ADDRESS"
      PORT_FORWARD_ADDRESSES="\$PORT_FORWARD_ADDRESSES \$ADDRESS"
      if [ "\$PORT_FWD_ROUTED_NETWORKS" == "yes" ]; then
	if (( \`echo "\$STATIC_INTERNAL_INTERFACES" | grep -c "\$INTERFACE"\` )); then
	  NETWORK_TAB[\$TAB]="\$ADDITIONAL_ROUTED_NETWORKS \`echo "\$INTERNAL_NETWORKS" | cut -d\\  -f\$COUNT\`"
	fi
      fi
      TAB=\$((TAB + 1))
    fi
  done
  for INTERFACE in \$DYNAMIC_INTERNAL_INTERFACES \$DYNAMIC_EXTERNAL_INTERFACES; do
    INTERFACE_TAB[\$TAB]="\$INTERFACE"
    TAB=\$((TAB + 1))
  done
  PORT_FORWARD_ADDRESSES=\`echo \$PORT_FORWARD_ADDRESSES\`
fi

# Obtain broadcast list if we are doing logging (so that we will not log them).
# We have to do this before we hax0r STATIC_INTERNAL_INTERFACES.

if [ "\$LOGGING" == "yes" ]; then
  BCAST_LIST="255.255.255.255"
  for INTERFACE in \$STATIC_INTERNAL_INTERFACES \$STATIC_EXTERNAL_INTERFACES; do 
    BROADCAST=\`ifconfig | grep "^\$INTERFACE\\ " -A1 | grep "Bcast" | cut -d: -f3 | cut -d\\  -f1 | head -1\`
    if !(( \`echo "\$BCAST_LIST" | grep -c "\$BROADCAST"\` )); then
      BCAST_LIST="\$BCAST_LIST \$BROADCAST"
    fi
  done
fi

# Remove redundant networks from INTERNAL_INTERFACES, STATIC_INTERNAL_INTERFACES, and INTERNAL_NETWORKS.

if [ -n "\$INTERNAL_NETWORKS" ]; then
  CHANGE=1
  until [ "\$CHANGE" == "0" ]; do
    COUNT=0
    CHANGE=0
    for NET in \$INTERNAL_NETWORKS; do
      TAB=0
      COUNT=\$((COUNT + 1))
      INTERFACE=\`echo "\$STATIC_INTERNAL_INTERFACES" | cut -d\\  -f\$COUNT\`
      STROKE=\`echo "\$NET" | cut -d/ -f2\`
      for NET1 in \$INTERNAL_NETWORKS; do
	TAB=\$((TAB + 1))
	INTERFACE1=\`echo "\$STATIC_INTERNAL_INTERFACES" | cut -d\\  -f\$TAB\`
	if [ "\$INTERFACE" == "\$INTERFACE1" ]; then
	  continue	# Obviously we don't want to compare a network to itself.
	fi
	PARAM=\`echo "\$INTERFACE1" | cut -d: -f1\`
	if !(( \`echo "\$INTERFACE" | cut -d: -f1 | grep -c "\$PARAM"\` )); then
	  continue	# We only want to compare networks attached to the same interface.
	fi
	MASK=\`echo "\$NET1/" | cut -d/ -f2\`
	xbits
	if [ "\$STROKE" -le "\$MASK" ]; then	# Then NET defines a larger network than NET1.
	  if [ "\$XBITS" -ge "\$STROKE" ]; then	# Then delete the second one if they are the same up to STROKE.
	    INTERNAL_NETWORKS=\`echo "\$INTERNAL_NETWORKS" | sed s#\$NET1##\`
	    INTERNAL_NETWORKS=\`echo \$INTERNAL_NETWORKS\`
	    STATIC_INTERNAL_INTERFACES=\`echo "\$STATIC_INTERNAL_INTERFACES" | sed s#\$INTERFACE1##\`
	    STATIC_INTERNAL_INTERFACES=\`echo \$STATIC_INTERNAL_INTERFACES\`
	    if [ -z "\$DMZ_INTERFACES" ] || !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$PARAM"\` )); then
	      NAT_NETWORKS=\`echo "\$NAT_NETWORKS" | sed s#\$NET1##\`
	      NAT_NETWORKS=\`echo \$NAT_NETWORKS\`
	    fi
	    CHANGE=1
	    continue 3
	  fi
	elif [ "\$XBITS" -ge "\$MASK" ]; then	# Else delete the first one (provided it is still the same interface).
	  INTERNAL_NETWORKS=\`echo "\$INTERNAL_NETWORKS" | sed s#\$NET##\`
	  INTERNAL_NETWORKS=\`echo \$INTERNAL_NETWORKS\`
	  STATIC_INTERNAL_INTERFACES=\`echo "\$STATIC_INTERNAL_INTERFACES" | sed s#\$INTERFACE##\`
	  STATIC_INTERNAL_INTERFACES=\`echo \$STATIC_INTERNAL_INTERFACES\`
	  if [ -z "\$DMZ_INTERFACES" ] || !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$PARAM"\` )); then
	    NAT_NETWORKS=\`echo "\$NAT_NETWORKS" | sed s#\$NET##\`
	    NAT_NETWORKS=\`echo \$NAT_NETWORKS\`
	  fi
	  CHANGE=1
	  continue 3
	fi
      done
    done
  done
fi

echo -n "."

# Sanity check ALLOW_INBOUND and DENY_OUTBOUND and compare against INTERNAL_NETWORKS.

if [ -n "\$ALLOW_INBOUND" ] || [ -n "\$DENY_OUTBOUND" ]; then
  for PARAM in DENY_OUTBOUND ALLOW_INBOUND;  do
    if [ "\$PARAM" == "DENY_OUTBOUND" ]; then
      LIST="\$DENY_OUTBOUND"
    else
      LIST="\$ALLOW_INBOUND"
    fi
    for FORWARD in \$LIST; do
      for TEMP in NULL; do	# You'll see why.
	if (( \`echo "\$FORWARD:" | cut -d: -f4 | grep -c "."\` )); then
	  FAILURE="Too many parameters in \$PARAM."
	  exit_failure \$1
	fi
	NET=\`echo "\$FORWARD:" | cut -d: -f1\`
	if [ -n "\$NET" ] && ! check_network; then
	  PORTS="\$NET"
	  if ! check_ports; then
	    FAILURE="Syntax error in \$PARAM."
	    exit_failure \$1
	  else
	    eval TEMP_\$PARAM="any:any:\$PORTS"
	    break
	  fi
	elif [ -z "\$NET" ]; then
	  NET="any"
	else
	  if [ "\$PARAM" == "DENY_OUTBOUND" ]; then
	    STROKE=\`echo "\$NET/" | cut -d/ -f2\`
	    if [ -z "\$STROKE" ]; then
	      STROKE=32
	    fi
	    for TAB in NULL; do
	      for NET1 in \$INTERNAL_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS; do
		MASK=\`echo "\$NET1/" | cut -d/ -f2\`
		if [ -z "\$MASK" ]; then
		  MASK=32
		fi
		xbits
		# Is this host/network from one of our internal networks?
		if [ "\$STROKE" -lt "\$MASK" ]; then
		  continue	# Can't tell
		elif [ "\$XBITS" -ge "\$MASK" ]; then
		  break 2		# Yes!
		fi		# Can't tell
	      done
	      FAILURE="Source host from DENY_OUTBOUND not found in an internal network."
	      exit_failure \$1
	    done
	  fi
	fi
	NET2="\$NET"
	NET=\`echo "\$FORWARD:" | cut -d: -f2\`
	if [ -n "\$NET" ] && ! check_network; then
	  PORTS="\$NET"
	  if ! check_ports; then
	    FAILURE="Syntax error in \$PARAM."
	    exit_failure \$1
	  else
	    eval TEMP_\$PARAM="\$NET2:any:\$PORTS"
	    break
	  fi
	elif [ -z "\$NET" ]; then
	  eval TEMP_\$PARAM="\$NET2:any:any"
	  break
	fi
	if [ "\$PARAM" == "ALLOW_INBOUND" ]; then
	  STROKE=\`echo "\$NET/" | cut -d/ -f2\`
	  if [ -z "\$STROKE" ]; then
	    STROKE=32
	  fi
	  for TAB in NULL; do
	    for NET1 in \$INTERNAL_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS; do
	      MASK=\`echo "\$NET1/" | cut -d/ -f2\`
	      if [ -z "\$MASK" ]; then
		MASK=32
	      fi
	      xbits
	      # Is this host/network from one of our internal networks?
	      if [ "\$STROKE" -lt "\$MASK" ]; then
		continue		# Can't tell on this network
	      elif [ "\$XBITS" -ge "\$MASK" ]; then
		break 2		# Yes!
	      fi			# Can't tell
	    done
	    FAILURE="Destination host in ALLOW_INBOUND not found in an internal network."
	    exit_failure \$1
	  done
	fi
	PORTS=\`echo "\$FORWARD:" | cut -d: -f3\`
	if [ -z "\$PORTS" ]; then
	  eval TEMP_\$PARAM="\$NET2:\$NET:any"
	  break
	else
	  if ! check_ports; then
	    FAILURE="\$FAILURE in \$PARAM."
	    exit_failure \$1
	  else
	    eval TEMP_\$PARAM="\$NET2:\$NET:\$PORTS"
	    break
	  fi
	fi
      done
      if [ "\$PARAM" == "ALLOW_INBOUND" ]; then
	MOD_ALLOW_INBOUND="\$MOD_ALLOW_INBOUND \$TEMP_ALLOW_INBOUND"
      else
	MOD_DENY_OUTBOUND="\$MOD_DENY_OUTBOUND \$TEMP_DENY_OUTBOUND"
      fi
    done
  done
  ALLOW_INBOUND=\`echo \$MOD_ALLOW_INBOUND\`
  DENY_OUTBOUND=\`echo \$MOD_DENY_OUTBOUND\`
fi

# Remove duplicate external addresses, for example those created when using channel bonding.

if [ -n "\$EXTERNAL_ADDRESSES" ]; then
  MOD_ADDRESSES=""
  for ADDRESS in \$EXTERNAL_ADDRESSES; do
    if !(( \`echo "\$MOD_ADDRESSES" | grep -c "\$ADDRESS"\` )); then
      MOD_ADDRESSES="\$MOD_ADDRESSES \$ADDRESS"
    fi
  done
  EXTERNAL_ADDRESSES=\`echo \$MOD_ADDRESSES\`
fi

# Make sure we own the addresses that we are staticly mapping through the firewall, and verify internal hosts are actually from internal networks.

if [ -n "\$STATIC_INSIDE_OUTSIDE" ]; then
  for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
    NET1=\`echo "\$FORWARD:" | cut -d: -f1\` 
    OUTSIDE=\`echo "\$FORWARD:" | cut -d: -f2\` 
    for TAB in NULL; do
      for ADDRESS in \$EXTERNAL_ADDRESSES \$INTERNAL_ADDRESSES; do
	if [ "\$ADDRESS" == "\$OUTSIDE" ]; then
	  break 2
	fi
      done
      FAILURE="Could not find an interface with address given in STATIC_INSIDE_OUTSIDE."
      exit_failure \$1
    done
    STROKE=\`echo "\$NET1/" | cut -d/ -f2\`
    if [ -z "\$STROKE" ]; then
      STROKE=32
    fi
    for TAB in NULL; do
      for NET in \$INTERNAL_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS; do
	MASK=\`echo "\$NET/" | cut -d/ -f2\`
	if [ -z "\$MASK" ]; then
	  MASK=32
	fi
	xbits
	# Is this host/network from one of our internal networks?
	if [ "\$STROKE" -lt "\$MASK" ]; then
	  continue	# Can't tell
	elif [ "\$XBITS" -ge "\$MASK" ]; then
	  break 2	# Yes!
	fi		# Can't tell
      done
      FAILURE="Internal host from STATIC_INSIDE_OUTSIDE not found in an internal network."
      exit_failure \$1
    done
  done
fi

# For FIREWALL_IP, make sure that our source address is on an external interface and our destination address is on an internal interface.

for ADDRESS in \$FIREWALL_IP; do
    OUTSIDE=\`echo "\$ADDRESS:" | cut -d: -f1\` 
    INSIDE=\`echo "\$ADDRESS:" | cut -d: -f2\` 
  for TAB in NULL; do
    for ADDRESS in \$EXTERNAL_ADDRESSES; do
      if [ "\$ADDRESS" == "\$OUTSIDE" ]; then
	break 2
      fi
    done
    FAILURE="Source address given in FIREWALL_IP must be configured on an *external* interface."
    exit_failure \$1
  done
  for TAB in NULL; do
    for ADDRESS in \$INTERNAL_ADDRESSES; do
      if [ "\$ADDRESS" == "\$INSIDE" ]; then
	break 2
      fi
    done
    FAILURE="Destination address given in FIREWALL_IP must be configured on an *internal* interface."
    exit_failure \$1
  done
done

# If we do not trust routed networks then add internal interfaces as "secured" addresses in the exit message.

if [ -n "\$STATIC_INTERNAL_INTERFACES" ] && [ "\$TRUST_ROUTED_NETWORKS" != "yes" ]; then
  EXTERNAL_ADDRESSES="\$EXTERNAL_ADDRESSES \$INTERNAL_ADDRESSES"
fi

echo -n "."

# Check that rp_filter interfaces are valid.

for INTERFACE in \$NO_RP_FILTER_INTERFACES; do
  if ! [ -w "/proc/sys/net/ipv4/conf/\$INTERFACE/rp_filter" ]; then
    FAILURE="Cannot write to /proc/sys/net/ipv4/conf/\$INTERFACE/rp_filter.  Is the interface definition valid?"
    exit_failure \$1
  fi
done

# Check for Local Loopback interface.

if !(( \`ifconfig | grep -A1 "^lo" | grep "127\\." | grep -c "255\\.0\\.0\\.0"\` )); then
  FAILURE="Local Loopback interface (lo) required but not found."
  exit_failure \$1
fi

# Make sure the filter table exists.

if (( \`iptables -t filter -nL 2>&1 | grep -c "Table does not exist"\` )) || (( \`iptables -t filter -nL 2>&1 | grep -c "can't initialize iptables table"\` )); then
  FAILURE="Could not find 'filter' table.  Did you compile support for all necessary modules?"
  exit_failure \$1
fi

# Check for the REJECT target if RFC 1122 compliance is enabled.

if [ "\$RFC_1122_COMPLIANT" == "yes" ]; then
  if ((\`iptables -t filter -i lo -o lo -I FORWARD -j REJECT 2>&1 | grep -c "No chain/target/match by that name"\`)); then
    FAILURE="Could not find 'REJECT' target.  Did you compile support for all necessary modules?"
    exit_failure \$1
  else
    iptables -t filter -D FORWARD 1
  fi
fi

# If logging is enabled check for LOG and limit targets.

if [ "\$LOGGING" == "yes" ]; then
  if (( \`iptables -t filter -i lo -o lo -I FORWARD -m limit 2>&1 | \\
	 grep -c "No chain/target/match by that name"\` )); then
    FAILURE="Could not find 'limit' target.  Did you compile support for all necessary modules?"
    exit_failure \$1
  else
    iptables -t filter -D FORWARD 1
  fi
  if (( \`iptables -t filter -i lo -o lo -I FORWARD -j LOG 2>&1 | grep -c "No chain/target/match by that name"\` )); then
    FAILURE="Could not find 'LOG' target.  Did you compile support for all necessary modules?"
    exit_failure \$1
  else
    iptables -t filter -D FORWARD 1
  fi
fi

# Check for the nat table if we need it.

if [ -n "\$STATIC_NAT_INTERFACES" ] || [ -n "\$DYNAMIC_NAT_INTERFACES" ] || [ -n "\$PORT_FORWARDS" ]; then
  if (( \`iptables -t nat -nL 2>&1 | grep -c "Table does not exist"\` )) || (( \`iptables -t nat -nL 2>&1 | grep -c "can't initialize iptables table"\` )); then
    FAILURE="Could not find 'nat' table.  Did you compile support for all necessary modules?"
    exit_failure \$1
  fi
fi

# Determine if we need the MASQUERADE target.

if [ -n "\$DYNAMIC_NAT_INTERFACES" ] || ( [ -n "\$DYNAMIC_INTERFACES" ] && [ -n "\$PORT_FORWARDS" ] ); then
  if ((\`iptables -t nat -I POSTROUTING -o lo -j MASQUERADE 2>&1 | grep -c "No chain/target/match by that name"\`)); then
    FAILURE="Could not find 'MASQUERADE' target.  Did you compile support for all necessary modules?"
    exit_failure \$1
  else
    iptables -t nat -D POSTROUTING 1
  fi
fi

# Check for state match module.

if (( \`iptables -t filter -I OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>&1 | \\
       grep -c "No chain/target/match by that name"\` )); then
  FAILURE="Failed to load state match module.  Did you compile support for all necessary modules?"
  exit_failure \$1
else
  iptables -t filter -D OUTPUT 1
fi

# Check for various port forwarding and ttl_stealth_router requirements.

if [ -n "\$PORT_FORWARDS" ] || [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
  if (( \`iptables -t mangle -nL 2>&1 | grep -c "Table does not exist"\` )) || (( \`iptables -t mangle -nL 2>&1 | grep -c "can't initialize iptables table"\` )); then
    FAILURE="Could not find 'mangle' table, required for port forwarding and TTL stealth router mode.  Did you compile support for all necessary modules?"
    exit_failure \$1
  fi
  if [ -n "\$PORT_FORWARDS" ]; then
    if (( \`iptables -t mangle -I OUTPUT -j MARK --set-mark "1" 2>&1 | grep -c "No chain/target/match by that name"\` )); then
      FAILURE="Failed to load MARK target, required for port forwarding.  Did you compile support for all necessary modules?"
      exit_failure \$1
    else
      iptables -t mangle -D OUTPUT 1
    fi
    if (( \`iptables -t mangle -I OUTPUT -m mark --mark "1" -j ACCEPT 2>&1 | grep -c "No chain/target/match by that name"\` )); then
      FAILURE="Failed to netfilter MARK match module, required for port forwarding.  Did you compile support for all necessary modules?"
      exit_failure \$1
    else
      iptables -t mangle -D OUTPUT 1
    fi
  fi
  if [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
    if (( \`iptables -t mangle -I FORWARD -j ACCEPT 2>&1 | grep -c "No chain/target/match by that name"\` )); then
      FAILURE="Linux kernel 2.4.18 or newer required for TTL_STEALTH_ROUTER mode."
      exit_failure \$1
    else
      iptables -t mangle -D FORWARD 1
    fi
  fi
fi

# Test for ipt_TTL support.

if [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
  if (( \`iptables -t mangle -I FORWARD -j TTL --ttl-inc "1" 2>&1 | grep -c "No chain/target/match by that name"\` )); then
    FAILURE="TTL_STEALTH_ROUTER mode requires a patched kernel.  See http://projectfiles.com/firewall/ for details."
    exit_failure \$1
  else
    iptables -t mangle -D FORWARD 1
  fi
fi

# System and configuration approved.

echo " [ PASSED ]"

# Exit if we only want to do sanity checking.

if [ "\$1" == "check" ]; then
  exit
fi

##########################
# -- Firewall Section -- #
##########################

echo -n "-> Building firewall."

# Let no packets slip by while we are configuring the firewall.

echo "0" > /proc/sys/net/ipv4/ip_forward

# Enable kernel level reverse path filtering.

echo "1" > /proc/sys/net/ipv4/conf/all/rp_filter
for INTERFACE in \$NO_RP_FILTER_INTERFACES; do
  echo "0" > /proc/sys/net/ipv4/conf/\$INTERFACE/rp_filter
done

# Enable kernel level dynamic address handling.

if [ -n "\$DYNAMIC_INTERFACES" ]; then
  echo "1" > /proc/sys/net/ipv4/ip_dynaddr
else
  echo "0" > /proc/sys/net/ipv4/ip_dynaddr
fi

# Set default policies.

iptables -t filter -F
iptables -t filter -X
iptables -t filter -P INPUT DROP
iptables -t filter -P FORWARD DROP
iptables -t filter -P OUTPUT ACCEPT

if !(( \`iptables -t nat -F 2>&1 | grep -c "Table does not exist"\` )); then
  iptables -t nat -X
  iptables -t nat -P PREROUTING ACCEPT
  iptables -t nat -P POSTROUTING ACCEPT
  iptables -t nat -P OUTPUT ACCEPT
fi

if !(( \`iptables -t mangle -F 2>&1 | grep -c "Table does not exist"\` )); then
  iptables -t mangle -F
  iptables -t mangle -X
  iptables -t mangle -P PREROUTING ACCEPT
  iptables -t mangle -P OUTPUT ACCEPT
  iptables -t mangle -P POSTROUTING ACCEPT > /dev/null 2>&1	# New 2.4.18 builtin mangle chains
  iptables -t mangle -P INPUT ACCEPT > /dev/null 2>&1
  iptables -t mangle -P FORWARD ACCEPT > /dev/null 2>&1
fi

# Drop traffic to and from blacklisted networks.

for NETWORK in \$BLACKLIST; do
  NET=\`echo "\$NETWORK:" | cut -d: -f1\`
  if ! check_network; then
    PORTS="\$NET"
    NET="0.0.0.0/0"
  else
    PORTS=\`echo "\$NETWORK:" | cut -d: -f2\`
  fi
  if [ -n "\$PORTS" ]; then
    PROTOCOL=\`echo "\$PORTS/" | cut -d/ -f2\`
    PORT="--dport \`echo "\$PORTS/" | cut -d/ -f1 | cut -d- -f1,2 --output-delimiter=":"\`"
    if [ "\$PROTOCOL" == "tcp" ] || [ -z "\$PROTOCOL" ]; then
      if [ "\$IS_ROUTER" == "yes" ]; then
	iptables -t filter -I FORWARD -s \$NET -p tcp \$PORT -j DROP
	iptables -t filter -I FORWARD -d \$NET -p tcp \$PORT -j DROP
      fi
      iptables -t filter -I INPUT -s \$NET -p tcp \$PORT -j DROP
      iptables -t filter -I INPUT -d \$NET -p tcp \$PORT -j DROP
      iptables -t filter -I OUTPUT -s \$NET -p tcp \$PORT -j DROP
      iptables -t filter -I OUTPUT -d \$NET -p tcp \$PORT -j DROP
    fi
    if [ "\$PROTOCOL" == "udp" ] || [ -z "\$PROTOCOL" ]; then
      if [ "\$IS_ROUTER" == "yes" ]; then
	iptables -t filter -I FORWARD -s \$NET -p udp \$PORT -j DROP
	iptables -t filter -I FORWARD -d \$NET -p udp \$PORT -j DROP
      fi
      iptables -t filter -I INPUT -s \$NET -p udp \$PORT -j DROP
      iptables -t filter -I INPUT -d \$NET -p udp \$PORT -j DROP
      iptables -t filter -I OUTPUT -s \$NET -p udp \$PORT -j DROP
      iptables -t filter -I OUTPUT -d \$NET -p udp \$PORT -j DROP
    fi
  else
    if [ "\$IS_ROUTER" == "yes" ]; then
      iptables -t filter -I FORWARD -s \$NET -j DROP
      iptables -t filter -I FORWARD -d \$NET -j DROP
    fi
    iptables -t filter -I INPUT -s \$NET -j DROP
    iptables -t filter -I INPUT -d \$NET -j DROP
    iptables -t filter -I OUTPUT -s \$NET -j DROP
    iptables -t filter -I OUTPUT -d \$NET -j DROP
  fi
done

# Initialize trusted chain

iptables -t filter -N TRUSTED
if [ "\$RFC_1122_COMPLIANT" == "yes" ]; then
  iptables -t filter -A TRUSTED -p icmp -j DROP	# ICMP will be permitted elsewhere.
  iptables -t filter -A TRUSTED -j REJECT
else
  iptables -t filter -A TRUSTED -j DROP
fi

# Reject state NEW without SYN flag set.  (paranoia setting)

if [ "\$DROP_NEW_WITHOUT_SYN" == "yes" ]; then
  if [ "\$LOGGING" == "yes" ]; then
      iptables -A INPUT -p tcp ! --syn -m state --state NEW -m limit --limit \$LOG_LIMIT \\
               --limit-burst \$LOG_BURST -j LOG --log-level \$LOG_LEVEL --log-prefix "firewall: "
  fi
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  if [ "\$IS_ROUTER" == "yes" ]; then
    if [ "\$LOGGING" == "yes" ]; then
      iptables -A FORWARD -p tcp ! --syn -m state --state NEW -m limit --limit \$LOG_LIMIT \\
               --limit-burst \$LOG_BURST -j LOG --log-level \$LOG_LEVEL --log-prefix "firewall: "
    fi
    iptables -A FORWARD -p tcp ! --syn -m state --state NEW -j DROP
  fi
fi

# Set logging preferences.  Do not log broadcasts.

if [ "\$LOGGING" == "yes" ]; then
  echo "1" > /proc/sys/net/ipv4/conf/all/log_martians
  iptables -t filter -N LOGME
  iptables -t filter -I TRUSTED -j LOGME
  for BROADCAST in \$BCAST_LIST; do
    iptables -t filter -I LOGME -d \$BROADCAST -j RETURN
  done
  iptables -t filter -A LOGME -p icmp -m limit --limit \$LOG_LIMIT --limit-burst \$LOG_BURST -j LOG --log-level \$LOG_LEVEL \\
         --log-prefix "firewall: "
  iptables -t filter -A LOGME -p tcp -m limit --limit \$LOG_LIMIT --limit-burst \$LOG_BURST -j LOG --log-level \$LOG_LEVEL \\
           --log-prefix "firewall: "
  iptables -t filter -A LOGME -p udp -m limit --limit \$LOG_LIMIT --limit-burst \$LOG_BURST -j LOG --log-level \$LOG_LEVEL \\
           --log-prefix "firewall: "
fi

echo -n "."

# Accept icmp-echo-request packets if RFC-1122 compliance option is enabled.  Limit logging of icmp packets.

if [ "\$RFC_1122_COMPLIANT" == "yes" ]; then
  if [ "\$LOGGING" == "yes" ]; then
    for ADDRESS in \$INTERNAL_ADDRESSES \$EXTERNAL_ADDRESSES; do
      iptables -t filter -I TRUSTED 2 -d \$ADDRESS -p icmp --icmp-type echo-request -j ACCEPT
    done
    for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
      ADDRESS=\`echo "\$FORWARD:" | cut -d: -f1\` 
      iptables -t filter -I TRUSTED 2 -d \$ADDRESS -p icmp --icmp-type echo-request -j ACCEPT
    done
    for ADDRESS in \$INTERNAL_ADDRESSES \$EXTERNAL_ADDRESSES; do
      iptables -t filter -I TRUSTED -d \$ADDRESS -p icmp --icmp-type echo-request -m limit --limit 2/second --limit-burst 10 -j ACCEPT
    done
    for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
      ADDRESS=\`echo "\$FORWARD:" | cut -d: -f1\` 
      iptables -t filter -I TRUSTED -d \$ADDRESS -p icmp --icmp-type echo-request -m limit --limit 2/second --limit-burst 10 -j ACCEPT
    done
    if [ "\$IS_ROUTER" != "yes" ] && [ -z "\$EXTERNAL_ADDRESSES" ]; then
      iptables -t filter -I TRUSTED 2 -p icmp --icmp-type echo-request -j ACCEPT
      iptables -t filter -I TRUSTED -p icmp --icmp-type echo-request -m limit --limit 2/second --limit-burst 10 -j ACCEPT
    elif [ -n "\$DMZ_INTERFACES" ]; then
      for INTERFACE in \$DMZ_INTERFACES; do
	iptables -t filter -I TRUSTED 2 -o \$INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
	iptables -t filter -I TRUSTED -o \$INTERFACE -p icmp --icmp-type echo-request -m limit --limit 2/second --limit-burst 10 -j ACCEPT
      done
    fi
  else
    for ADDRESS in \$INTERNAL_ADDRESSES \$EXTERNAL_ADDRESSES; do
      iptables -t filter -I TRUSTED -d \$ADDRESS -p icmp --icmp-type echo-request -j ACCEPT
    done
    for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
      ADDRESS=\`echo "\$FORWARD:" | cut -d: -f1\` 
      iptables -t filter -I TRUSTED -d \$ADDRESS -p icmp --icmp-type echo-request -j ACCEPT
    done
    if [ "\$IS_ROUTER" != "yes" ] && [ -z "\$EXTERNAL_ADDRESSES" ]; then
      iptables -t filter -I TRUSTED -p icmp --icmp-type echo-request -j ACCEPT
    elif [ -n "\$DMZ_INTERFACES" ]; then
      for INTERFACE in \$DMZ_INTERFACES; do
	iptables -t filter -I TRUSTED -o \$INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
      done
    fi
  fi
fi

# Insert trusted networks into trusted chain before everything else.

for NETWORK in \$PERMIT ; do
  iptables -t filter -I TRUSTED -s \$NETWORK -j ACCEPT
done

# Insert local external networks into the trusted chain if option is enabled.

if [ "\$TRUST_LOCAL_EXTERNAL_NETWORKS" == "yes" ]; then
  for NETWORK in \$EXTERNAL_NETWORKS; do
    iptables -t filter -I TRUSTED -s \$NETWORK -j ACCEPT
  done
fi

# Set default policy for ESTABLISHED and RELATED connections to ACCEPT on FORWARD chains.

iptables -t filter -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
if [ "\$IS_ROUTER" == "yes" ]; then
  iptables -t filter -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
fi

# Configure ALLOW_INBOUND and DENY_OUTBOUND.

if [ -n "\$INTERNAL_INTERFACES" ]; then
  for PARAM in ACCEPT TRUSTED; do
    if [ "\$PARAM" == "TRUSTED" ]; then
      LIST="\$DENY_OUTBOUND"
    else
      LIST="\$ALLOW_INBOUND"
    fi
    for ITEM in \$LIST; do
      NET="-s \`echo "\$ITEM:" | cut -d: -f1\`"
      if [ "\$NET" == "-s any" ]; then
	NET=""
      fi
      DEST="-d \`echo "\$ITEM:" | cut -d: -f2\`"
      if [ "\$DEST" == "-d any" ]; then
	DEST=""
      fi
      PORTS=\`echo "\$ITEM:" | cut -d: -f3\`
      PROTOCOL=\`echo "\$PORTS/" | cut -d/ -f2\`
      PORT="--dport \`echo "\$PORTS/" | cut -d/ -f1 | cut -d- -f1,2 --output-delimiter=":"\`"
      if [ -z "\$DEST" ] || [ -z "\$NET" ]; then
	if [ "\$PARAM" == "ACCEPT" ]; then
	  TAB="-o"	# (just to reuse the variable)  For ALLOW_INBOUND 
	else		# classify packets sent out on internal interfaces and
	  TAB="-i"	# for DENY_OUTBOUND, received by internal interfaces,
	fi		# unless both source and destination addresses are available.
	for INTERFACE in \$INTERNAL_INTERFACES; do
	  if !(( \`echo "\$INTERFACE" | grep -c ":"\` )); then
	    if [ "\$PORTS" == "any" ]; then
	      iptables -t filter -A FORWARD -m state --state NEW \$TAB \$INTERFACE \$NET \$DEST -j \$PARAM
	    else
	      if [ "\$PROTOCOL" == "tcp" ] || [ -z "\$PROTOCOL" ]; then
		iptables -t filter -A FORWARD -m state --state NEW \$TAB \$INTERFACE \$NET \$DEST -p tcp \$PORT -j \$PARAM
	      fi
	      if [ "\$PROTOCOL" == "udp" ] || [ -z "\$PROTOCOL" ]; then
		iptables -t filter -A FORWARD -m state --state NEW \$TAB \$INTERFACE \$NET \$DEST -p udp \$PORT -j \$PARAM
	      fi
	    fi
	  fi
	done
      else	# The exception where we have both source and destination addresses
	if [ "\$PORTS" == "any" ]; then
	  iptables -t filter -A FORWARD -m state --state NEW \$NET \$DEST -j \$PARAM
	else
	  if [ "\$PROTOCOL" == "tcp" ] || [ -z "\$PROTOCOL" ]; then
	    iptables -t filter -A FORWARD -m state --state NEW \$NET \$DEST -p tcp \$PORT -j \$PARAM
	  fi
	  if [ "\$PROTOCOL" == "udp" ] || [ -z "\$PROTOCOL" ]; then
	    iptables -t filter -A FORWARD -m state --state NEW \$NET \$DEST -p udp \$PORT -j \$PARAM
	  fi
	fi
      fi
    done
  done
fi

# For servers, only allow NEW connections to specified INPUT ports.  For port forwarding, allow on FORWARD chain.

for ITEM in \$OPEN_PORTS \$TRUSTED_PORTS; do
  NET=""
  if (( \`echo "\$ITEM:" | cut -d: -f2 | grep -c "."\` )); then
    NET="-s \`echo "\$ITEM:" | cut -d: -f1\`"
    ITEM=\`echo "\$ITEM:" | cut -d: -f2\`
  fi
  PORTS=\`echo "\$ITEM" | cut -d/ -f1\`
  PORTS=\`echo "\$PORTS" | cut -d- -f1,2 --output-delimiter=":"\`
  PROTOCOL=\`echo "\$ITEM" | cut -d/ -f2\`
  COUNT="0"
  for FORWARD in \$PORT_FORWARDS; do
    IN_PORTS=\`echo "\$FORWARD" | cut -d: -f2 | cut -d- -f1,2 --output-delimiter=":"\`
    if [ "\`echo "\$FORWARD" | cut -d: -f1\`" == "\$PROTOCOL" ] && [ "\$PORTS" == "\$IN_PORTS" ]; then
      DEST=\`echo "\$FORWARD" | cut -d: -f3\`
      DPORTS=\`echo "\$FORWARD" | cut -d: -f4 | cut -d- -f1,2 --output-delimiter=":"\`
      if [ -z "\$DPORTS" ]; then
	DPORTS="\$IN_PORTS"
      fi
      iptables -t filter -A FORWARD -m state --state NEW \$NET -d \$DEST -p \$PROTOCOL --dport \$DPORTS -j ACCEPT
      COUNT="1"
      if [ -z "\$NET" ]; then
	continue 2	# i.e. This port forward is open to everyone.
      fi
    fi
  done
  if [ "\$COUNT" == "0" ]; then
    iptables -t filter -A INPUT -m state --state NEW \$NET -p \$PROTOCOL --dport \$PORTS -j ACCEPT
  fi
done

echo -n "."

# For routers, allow routing of internal and routed networks on internal interfaces.  Fix traceroutes under DNAT info-leak-bug.

if [ "\$IS_ROUTER" == "yes" ]; then
  COUNT="0"
  TAB=""
  for INTERFACE in \$STATIC_INTERNAL_INTERFACES; do
    COUNT=\$((COUNT + 1))
    NETWORK=\`echo "\$INTERNAL_NETWORKS" | cut -d\\  -f\$COUNT\`
    INTERFACE=\`echo "\$INTERFACE" | cut -d: -f1\`
    iptables -t filter -A OUTPUT -o \$INTERFACE -d \$NETWORK -p icmp -j ACCEPT
    if [ -z "\$DMZ_INTERFACES" ] || !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$INTERFACE"\` )); then
      if [ "\$SHARED_INTERNAL" == "yes" ]; then
	iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -s \$NETWORK -j ACCEPT
      else
	for DEST in \$EXTERNAL_INTERFACES \$DMZ_INTERFACES; do
	  if !(( \`echo "\$DEST" | grep -c ":"\` )); then
	    iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -s \$NETWORK -o \$DEST -j ACCEPT
	  fi
	done
      fi
    else
      for DEST in \$EXTERNAL_INTERFACES; do
	if !(( \`echo "\$DEST" | grep -c ":"\` )); then
	  iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -s \$NETWORK -o \$DEST -j ACCEPT
	fi
      done
    fi
    if [ "\$TRUST_ROUTED_NETWORKS" == "yes" ] && ( [ -z "\$DMZ_INTERFACES" ] || \\
       !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$INTERFACE"\` )) ); then
      iptables -t filter -A INPUT -m state --state NEW -i \$INTERFACE -s \$NETWORK -j ACCEPT
    fi
    if [ "\$INTERNAL_DHCP" == "yes" ]; then
      if !(( \`echo "\$TAB" | grep -c "\$INTERFACE"\` )); then
	iptables -t filter -A INPUT -m state --state NEW -i \$INTERFACE -p udp --dport 67 -j ACCEPT
      fi
      TAB="\$TAB \$INTERFACE"
    fi
    if [ -z "\$DMZ_INTERFACES" ] || !(( \`echo "\$DMZ_INTERFACES" | grep -c "\$INTERFACE"\` )); then
      for NETWORK in \$ADDITIONAL_ROUTED_NETWORKS; do
	iptables -t filter -A OUTPUT -o \$INTERFACE -d \$NETWORK -p icmp -j ACCEPT
	if [ "\$SHARED_INTERNAL" == "yes" ]; then
	  iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -s \$NETWORK -j ACCEPT
	else
	  for DEST in \$EXTERNAL_INTERFACES \$DMZ_INTERFACES; do
	    if !(( \`echo "\$DEST" | grep -c ":"\` )); then
	      iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -s \$NETWORK -o \$DEST -j ACCEPT
	    fi
	  done
	fi
	if [ "\$TRUST_ROUTED_NETWORKS" == "yes" ]; then
	  iptables -t filter -A INPUT -m state --state NEW -i \$INTERFACE -s \$NETWORK -j ACCEPT
	fi
      done
    fi
  done
  for INTERFACE in \$DYNAMIC_INTERNAL_INTERFACES; do
    iptables -t filter -A OUTPUT -o \$INTERFACE -p icmp -j ACCEPT
    iptables -t filter -A FORWARD -m state --state NEW -i \$INTERFACE -j ACCEPT
    if [ "\$TRUST_ROUTED_NETWORKS" == "yes" ]; then
      iptables -t filter -A INPUT -m state --state NEW -i \$INTERFACE -j ACCEPT
    fi
  done
fi

# ICMP DNAT information leak workaround.

iptables -t filter -A OUTPUT -p icmp -m state --state INVALID -j DROP

# Set up static address translations.

if [ "\$IS_ROUTER" == "yes" ]; then
  for FORWARD in \$STATIC_INSIDE_OUTSIDE; do
    INSIDE=\`echo "\$FORWARD:" | cut -d: -f1\` 
    OUTSIDE=\`echo "\$FORWARD:" | cut -d: -f2\` 
    iptables -t nat -A POSTROUTING -s \$INSIDE -j SNAT --to-source \$OUTSIDE
    if !(( \`echo "\$INSIDE" | grep -c "/"\` )); then
      for ITEM in \$ALLOW_INBOUND; do
	NETWORK="-s \`echo "\$ITEM" | cut -d: -f1\`"	# Source
	if [ "\$NETWORK" == "-s any" ]; then
	  NETWORK=""
	fi
	NET=\`echo "\$ITEM" | cut -d: -f2\`		# Destination
	PORTS=\`echo "\$ITEM" | cut -d: -f3\`
	if [ -n "\$PORTS" ]; then
	  PORT="--dport \`echo "\$PORTS/" | cut -d/ -f1 | cut -d- -f1,2 --output-delimiter=":"\`"
	  PROTOCOL=\`echo "\$PORTS/" | cut -d/ -f2\`
	fi
	if [ "\$NET" != "any" ]; then	# If there is a specific destination --
	  NET1="\$INSIDE"		# Determine if this is part of it.
	  xbits
	  MASK=\`echo "\$NET/" | cut -d/ -f2\`
	  if [ -z "\$MASK" ]; then
	    MASK=32
	  fi
	fi
	if [ "\$NET" == "any" ] || [ "\$XBITS" -ge "\$MASK" ]; then
	  if [ "\$RFC_1122_COMPLIANT" == "yes" ]; then
	    iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE \\
	    -p icmp --icmp-type echo-request -j DNAT --to-destination \$INSIDE
	  fi
	  if [ "\$PORTS" == "any" ]; then
	    iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE -p tcp -j DNAT --to-destination \$INSIDE
	    iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE -p udp -j DNAT --to-destination \$INSIDE
	  else
	    if [ "\$PROTOCOL" == "tcp" ] || [ "\$PROTOCOL" == "udp" ]; then
	      iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE -p \$PROTOCOL \$PORT -j DNAT --to-destination \$INSIDE
	    else
	      iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE -p tcp \$PORT -j DNAT --to-destination \$INSIDE
	      iptables -t nat -A PREROUTING \$NETWORK -d \$OUTSIDE -p udp \$PORT -j DNAT --to-destination \$INSIDE
	    fi
	  fi
	fi
      done
      for NETWORK in \$PERMIT; do
	iptables -t nat -A PREROUTING -s \$NETWORK -d \$OUTSIDE -j DNAT --to-destination \$INSIDE
      done
      COUNT="0"
      NET1="\$INSIDE"
      for INTERFACE in \$STATIC_INTERNAL_INTERFACES; do
	COUNT=\$((COUNT + 1))
	NET=\`echo \$INTERNAL_NETWORKS | cut -d\\  -f\$COUNT\`
	INTERFACE=\`echo \$INTERFACE | cut -d: -f1\`
	iptables -t nat -A PREROUTING -s \$NET -d \$OUTSIDE -j DNAT --to-destination \$INSIDE
	xbits
	MASK=\`echo "\$NET/" | cut -d/ -f2\`
	if [ -z "\$MASK" ]; then
	  MASK=32
	fi
	ADDRESS=\`echo \$INTERNAL_ADDRESSES | cut -d\\  -f\$COUNT\`
	if [ "\$XBITS" -ge "\$MASK" ]; then
	  iptables -t nat -A POSTROUTING -s \$NET -o \$INTERFACE -d \$INSIDE -j SNAT --to-source \$ADDRESS
	fi
	for NET in \$ADDITIONAL_ROUTED_NETWORKS; do
	  xbits
	  if [ "\$XBITS" -ge "\$MASK" ]; then
	    iptables -t nat -A POSTROUTING -s \$NET -o \$INTERFACE -d \$INSIDE -j SNAT --to-source \$ADDRESS
	  fi
	  iptables -t nat -A PREROUTING -s \$NET -d \$OUTSIDE -j DNAT --to-destination \$INSIDE
	done
      done
      for INTERFACE in \$DYNAMIC_INTERNAL_INTERFACES; do
	iptables -t nat -A PREROUTING -s \$NETWORK -d \$OUTSIDE -j DNAT --to-destination \$INSIDE
      done
    fi
    # Lets not have people mistaking the router for the internal host.
    iptables -t filter -I INPUT -d \$OUTSIDE -j DROP
  done
fi

# Configure NAT.

if [ "\$IS_ROUTER" == "yes" ]; then
  COUNT="0"
  for INTERFACE in \$STATIC_NAT_INTERFACES; do
    COUNT=\$((COUNT + 1))
    ADDRESS=\`echo "\$NAT_ADDRESSES" | cut -d\\  -f\$COUNT\`
    if [ -n "\$DYNAMIC_INTERNAL_INTERFACES" ]; then
      iptables -t nat -A POSTROUTING -o \$INTERFACE -j SNAT --to-source \$ADDRESS
    else
      for NETWORK in \$NAT_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS; do
	iptables -t nat -A POSTROUTING -s \$NETWORK -o \$INTERFACE -j SNAT --to-source \$ADDRESS
      done
    fi
  done
  for INTERFACE in \$DYNAMIC_NAT_INTERFACES; do
    if [ -n "\$DYNAMIC_INTERNAL_INTERFACES" ]; then
      iptables -t nat -I POSTROUTING -o \$INTERFACE -j MASQUERADE
    else
      for NETWORK in \$NAT_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS; do
	iptables -t nat -I POSTROUTING -s \$NETWORK -o \$INTERFACE -j MASQUERADE
      done
    fi
  done
fi

echo -n "."

# Configure port forwarding.

for FORWARD in \$PORT_FORWARDS; do
  PROTOCOL=\`echo "\$FORWARD" | cut -d: -f1\`
  IN_PORTS=\`echo "\$FORWARD" | cut -d: -f2 | cut -d- -f1,2 --output-delimiter=":"\`
  DEST=\`echo "\$FORWARD" | cut -d: -f3\`
  PORTS=\`echo "\$FORWARD" | cut -d: -f4\`
  if [ -z "\$PORTS" ]; then
    PORTS="\$IN_PORTS"
  fi
  DPORTS=\`echo "\$PORTS" | cut -d- -f1,2 --output-delimiter=":"\`
  # Support DNAT for locally generated connections, new in iptables 1.2.6a and kernel 2.4.19 
  iptables -t nat -A OUTPUT -o lo -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS > /dev/null 2>&1
  COUNT="0"
  while (( \`echo "\${INTERFACE_TAB[\$((COUNT + 1))]}" | grep -c "."\` )); do
    COUNT=\$((COUNT + 1))
    if (( \`echo "\$DYNAMIC_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )); then
      iptables -t nat -I POSTROUTING -m mark --mark "\$COUNT" -o \${INTERFACE_TAB[\$COUNT]} -d \$DEST \\
	       -p \$PROTOCOL --dport \$DPORTS -j MASQUERADE
    else
      iptables -t nat -I POSTROUTING -m mark --mark "\$COUNT" -o \${INTERFACE_TAB[\$COUNT]} -d \$DEST \\
	       -p \$PROTOCOL --dport \$DPORTS -j SNAT --to-source \${ADDRESS_TAB[\$COUNT]}
    fi
    if (( \`echo "\$DYNAMIC_INTERNAL_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )) && \\
       [ "\$PORT_FWD_ROUTED_NETWORKS" == "yes" ]; then
      iptables -t nat -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} \\
	       -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
      iptables -t mangle -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} \\
	       -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
      continue	# We will accept anything on this interface.
    fi
    for ADDRESS in \$PORT_FORWARD_ADDRESSES; do
      for ITEM in \$OPEN_PORTS \$TRUSTED_PORTS; do
	if (( \`echo "\$ITEM:" | cut -d: -f2 | grep -c "."\` )); then
	  NET="-s \`echo "\$ITEM:" | cut -d: -f1\`"
	  ITEM=\`echo "\$ITEM:" | cut -d: -f2\`
	else
	  NET=""
	fi
	PORT=\`echo "\$ITEM/" | cut -d/ -f1\`
	PORT=\`echo "\$PORT" | cut -d- -f1,2 --output-delimiter=":"\`
	if [ "\$PROTOCOL" == "\`echo "\$ITEM/" | cut -d/ -f2\`" ] && [ "\$PORT" == "\$IN_PORTS" ]; then
	  if (( \`echo "\$DYNAMIC_NAT_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )); then
	    iptables -t nat -A PREROUTING \$NET -i \${INTERFACE_TAB[\$COUNT]} \\
		     -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	    iptables -t mangle -A PREROUTING \$NET -i \${INTERFACE_TAB[\$COUNT]} \\
		     -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	  else
	    iptables -t nat -A PREROUTING \$NET -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} \\
		     -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	    iptables -t mangle -A PREROUTING \$NET -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} \\
		     -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	  fi
	  if [ -z "\$NET" ]; then
	    continue 2	# This port forward is open to everyone.
	  fi
	fi
      done
      for NETWORK in \${NETWORK_TAB[\$COUNT]}; do
	if (( \`echo "\$DYNAMIC_NAT_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )); then
	  iptables -t nat -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		    -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	  iptables -t mangle -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	else
	  iptables -t nat -A PREROUTING -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		    -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	  iptables -t mangle -A PREROUTING -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	fi
      done
      for NETWORK in \$PERMIT; do
	if (( \`echo "\$DYNAMIC_NAT_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )); then
	  iptables -t nat -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	  iptables -t mangle -A PREROUTING -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	else
	  iptables -t nat -A PREROUTING -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j DNAT --to-destination \$DEST:\$PORTS
	  iptables -t mangle -A PREROUTING -d \$ADDRESS -i \${INTERFACE_TAB[\$COUNT]} -s \$NETWORK \\
		   -p \$PROTOCOL --dport \$IN_PORTS -j MARK --set-mark "\$COUNT"
	fi
      done	# Done with sources
      if (( \`echo "\$DYNAMIC_NAT_INTERFACES" | grep -c "\${INTERFACE_TAB[\$COUNT]}"\` )); then
	break
      fi
    done	# Done with destination addresses
  done		# Done with interfaces
done		# Done with forwards

# Source nat outbound connections generated by the local machine to address defined in FIREWALL_IP.

for ADDRESS in \$FIREWALL_IP; do
  OUTSIDE=\`echo "\$ADDRESS:" | cut -d: -f1\` 
  INSIDE=\`echo "\$ADDRESS:" | cut -d: -f2\` 
  iptables -t nat -A POSTROUTING -s \$OUTSIDE -j SNAT --to-source \$INSIDE
done

# Accept new connections from the loopback interface (localhost).

iptables -t filter -A INPUT -i lo -m state --state NEW -j ACCEPT

# Jump to the trusted chain if this packet establishes a NEW connection.

iptables -t filter -A INPUT -m state --state NEW -j TRUSTED
if [ "\$IS_ROUTER" == "yes" ]; then
  iptables -t filter -A FORWARD -m state --state NEW -j TRUSTED
fi

# Enable TTL stealth router mode.

if [ "\$TTL_STEALTH_ROUTER" == "yes" ]; then
  iptables -t mangle -I FORWARD -j TTL --ttl-inc "1"
fi

# Now that everything is configured we can enable ip_forward for routers.

if [ "\$IS_ROUTER" == "yes" ]; then
  echo "1" > /proc/sys/net/ipv4/ip_forward 
fi

# Print exit message.

echo " [ DONE ]"
if [ -n "\$EXTERNAL_ADDRESSES" ]; then
  echo "-> Successfully secured the following addresses: \`echo \$EXTERNAL_ADDRESSES | sed s/\\ /,\\ /g\`."
fi
if [ "\$IS_ROUTER" == "yes" ]; then
  if [ -n "\$DYNAMIC_EXTERNAL_INTERFACES" ]; then
    echo "-> Successfully secured the following external interfaces: \`echo \$DYNAMIC_EXTERNAL_INTERFACES | sed s/\\ /,\\ /g\`."
  fi
  if [ -n "\$INTERNAL_NETWORKS" ] || [ -n "\$ADDITIONAL_ROUTED_NETWORKS" ]; then
    echo "-> Routing is enabled for the following networks: \`echo \$INTERNAL_NETWORKS \$ADDITIONAL_ROUTED_NETWORKS | \\
    sed s/\\ /,\\ /g\`."
  fi
  if [ -n "\$DYNAMIC_INTERNAL_INTERFACES" ]; then
    echo "-> Alert!  Routing is enabled for ALL connections through: \`echo \$DYNAMIC_INTERNAL_INTERFACES \\
    | sed s/\\ /,\\ /g\`."
  fi
fi

# Write a configuration file if passed appropriate arguments.

if [ "\$1" == "save" ] || [ "\$1" == "update" ]; then
  if [ -a "\$CONFIG" ]; then
    if !(( \`head -1 "\$CONFIG" | grep -c "# Linux Firewall configuration -- http://projectfiles.com/firewall/"\` )); then
      echo "-> WARNING: The file \$CONFIG is associated with another program!"
      echo "->          Press any key to overwrite, or CTRL-C to abort."
      read -rsn1
    fi
  fi
cat << EOF > \$CONFIG
# Linux Firewall configuration -- http://projectfiles.com/firewall/
# Generated by '\`echo \$0 | sed s#^\\./#\$PWD/#\` \$1 \`echo \$2 | sed s#^\\./#\$PWD/#\`'
# on \`date\`.
# Generated with version: "\$VERSION".

PERMIT="\$ORIG_PERMIT"
INTERNAL_INTERFACES="\$ORIG_INTERNAL_INTERFACES"
DYNAMIC_INTERFACES="\$ORIG_DYNAMIC_INTERFACES"
DENY_OUTBOUND="\$ORIG_DENY_OUTBOUND"
ALLOW_INBOUND="\$ORIG_ALLOW_INBOUND"
BLACKLIST="\$BLACKLIST"
STATIC_INSIDE_OUTSIDE="\$ORIG_STATIC_INSIDE_OUTSIDE"
PORT_FORWARDS="\$ORIG_PORT_FORWARDS"
PORT_FWD_ALL="\$PORT_FWD_ALL"
PORT_FWD_ROUTED_NETWORKS="\$PORT_FWD_ROUTED_NETWORKS"
ADDITIONAL_ROUTED_NETWORKS="\$ADDITIONAL_ROUTED_NETWORKS"
TRUST_ROUTED_NETWORKS="\$TRUST_ROUTED_NETWORKS"
SHARED_INTERNAL="\$SHARED_INTERNAL"
FIREWALL_IP="\$FIREWALL_IP"
TRUST_LOCAL_EXTERNAL_NETWORKS="\$TRUST_LOCAL_EXTERNAL_NETWORKS"
DMZ_INTERFACES="\$DMZ_INTERFACES"
NAT_EXTERNAL="\$NAT_EXTERNAL"
ADDITIONAL_NAT_INTERFACES="\$ADDITIONAL_NAT_INTERFACES"
IGNORE_INTERFACES="\$IGNORE_INTERFACES"
LOGGING="\$LOGGING"
NO_RP_FILTER_INTERFACES="\$NO_RP_FILTER_INTERFACES"
INTERNAL_DHCP="\$INTERNAL_DHCP"
RFC_1122_COMPLIANT="\$RFC_1122_COMPLIANT"
DROP_NEW_WITHOUT_SYN="\$DROP_NEW_WITHOUT_SYN"
DUMP_TCP_ON_INIT="\$DUMP_TCP_ON_INIT"
TTL_STEALTH_ROUTER="\$TTL_STEALTH_ROUTER"
LOG_LIMIT="\$LOG_LIMIT"
LOG_BURST="\$LOG_BURST"
LOG_LEVEL="\$LOG_LEVEL"

return



EOF
  iptables-save >> \$CONFIG
  chown root:root \$CONFIG
  chmod 600 \$CONFIG
  echo "-> Firewall configuration saved to \$CONFIG"
fi

# Dump current TCP sessions if requested.

if [ "\$DUMP_TCP_ON_INIT" == "yes" ]; then
  dump_tcp
fi

# Done!
FIREWALL_END_OF_FILE
  
  chmod $FW_PERM $FW_TMPFILE
  status="test"
  ;;

  *)
    goodbye
  esac
done

goodbye
