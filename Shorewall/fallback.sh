#!/bin/sh
#
# Script to back out the installation of Shoreline Firewall and to restore the previous version of
# the program
#
#     This program is under GPL [http://www.gnu.org/copyleft/gpl.htm]
#
#     (c) 2001,2002,2003 - Tom Eastep (teastep@shorewall.net)
#
#       Shorewall documentation is available at http://seattlefirewall.dyndns.org
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of Version 2 of the GNU General Public License
#       as published by the Free Software Foundation.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA
#
#    Usage:
#
#       You may only use this script to back out the installation of the version
#       shown below. Simply run this script to revert to your prior version of
#       Shoreline Firewall.

VERSION=1.4.10a

usage() # $1 = exit status
{
    echo "usage: `basename $0`"
    exit $1
}

restore_file() # $1 = file to restore
{
    if [ -f ${1}-${VERSION}.bkout -o -L ${1}-${VERSION}.bkout ]; then
	if (mv -f ${1}-${VERSION}.bkout $1); then
	    echo
	    echo "$1 restored"
        else
	    echo "ERROR: Could not restore $1"
	    exit 1
        fi
    fi
}

if [ ! -f /usr/share/shorewall/version-${VERSION}.bkout ]; then
    echo "Shorewall Version $VERSION is not installed"
    exit 1
fi

echo "Backing Out Installation of Shorewall $VERSION"

if [ -L /usr/share/shorewall/init ]; then
    FIREWALL=`ls -l /usr/share/shorewall/firewall | sed 's/^.*> //'`
    restore_file $FIREWALL
    restore_file /usr/share/shorewall/firewall
elif [ -L /usr/lib/shorewall/firewall ]; then
    FIREWALL=`ls -l /usr/lib/shorewall/firewall | sed 's/^.*> //'`
    restore_file $FIREWALL
elif [ -L /var/lib/shorewall/firewall ]; then
    FIREWALL=`ls -l /var/lib/shorewall/firewall | sed 's/^.*> //'`
    restore_file $FIREWALL
elif [ -L /usr/lib/shorewall/init ]; then
    FIREWALL=`ls -l /usr/lib/shorewall/init | sed 's/^.*> //'`
    restore_file $FIREWALL
    restore_file /usr/lib/shorewall/firewall
fi

restore_file /sbin/shorewall

[ -f /etc/shorewall.conf.$VERSION ] && rm -f /etc/shorewall.conf.$VERSION

restore_file /etc/shorewall/shorewall.conf

restore_file /etc/shorewall/functions
restore_file /usr/share/shorewall/functions
restore_file /usr/share/shorewall/firewall
restore_file /usr/lib/shorewall/functions
restore_file /var/lib/shorewall/functions
restore_file /usr/lib/shorewall/firewall
restore_file /usr/lib/shorewall/help

restore_file /etc/shorewall/common.def

restore_file /etc/shorewall/icmp.def

restore_file /etc/shorewall/zones

restore_file /etc/shorewall/policy

restore_file /etc/shorewall/interfaces

restore_file /etc/shorewall/hosts

restore_file /etc/shorewall/rules

restore_file /etc/shorewall/nat

restore_file /etc/shorewall/params

restore_file /etc/shorewall/proxyarp

restore_file /etc/shorewall/routestopped

restore_file /etc/shorewall/maclist

restore_file /etc/shorewall/masq

restore_file /etc/shorewall/modules

restore_file /etc/shorewall/tcrules

restore_file /etc/shorewall/tos

restore_file /etc/shorewall/tunnels

restore_file /etc/shorewall/blacklist

restore_file /etc/shorewall/whitelist

restore_file /etc/shorewall/rfc1918

restore_file /etc/shorewall/init

restore_file /etc/shorewall/start

restore_file /etc/shorewall/stop

restore_file /etc/shorewall/stopped

restore_file /etc/shorewall/ecn

restore_file /etc/shorewall/accounting

restore_file /etc/shorewall/usersets

restore_file /etc/shorewall/users

restore_file /etc/shorewall/actions

restore_file /etc/shorewall/action.template

if [ -f /usr/share/shorewall/version-${VERSION}.bkout ]; then
    restore_file /usr/share/shorewall/version
    oldversion="`cat /usr/share/shorewall/version`"
elif [ -f /usr/lib/shorewall/version-${VERSION}.bkout ]; then
    restore_file /usr/lib/shorewall/version
    oldversion="`cat /usr/lib/shorewall/version`"
elif [ -f /var/lib/shorewall/version-${VERSION}.bkout ]; then
    restore_file /var/lib/shorewall/version
    oldversion="`cat /var/lib/shorewall/version`"
else
    restore_file /etc/shorewall/version
    oldversion="`cat /etc/shorewall/version`"
fi

echo "Shorewall Restored to Version $oldversion"


