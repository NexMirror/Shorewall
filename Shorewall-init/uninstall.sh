#!/bin/sh
#
# Script to back uninstall Shoreline Firewall Init
#
#     (c) 2000-2016 - Tom Eastep (teastep@shorewall.net)
#
#       Shorewall documentation is available at http://shorewall.sourceforge.net
#
#       This program is part of Shorewall.
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by the
#       Free Software Foundation, either version 2 of the license or, at your
#       option, any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, see <http://www.gnu.org/licenses/>.
#
#    Usage:
#
#       You may only use this script to uninstall the version
#       shown below. Simply run this script to remove Shorewall Firewall

VERSION=xxx # The Build script inserts the actual version
PRODUCT=shorewall-init
Product="Shorewall Init"

usage() # $1 = exit status
{
    ME=$(basename $0)
    echo "usage: $ME [ <option> ] [ <shorewallrc file> ]"
    echo "where <option> is one of"
    echo "  -h"
    echo "  -v"
    echo "  -n"
    exit $1
}

#
# Change to the directory containing this script
#
cd "$(dirname $0)"

#
# Source common functions
#
. ./lib.uninstaller || { echo "ERROR: Can not load common functions." >&2; exit 1; }

#
# Parse the run line
#
finished=0
configure=1

while [ $finished -eq 0 ]; do
    option=$1

    case "$option" in
	-*)
	    option=${option#-}

	    while [ -n "$option" ]; do
		case $option in
		    h)
			usage 0
			;;
		    v)
			echo "$Product Firewall Installer Version $VERSION"
			exit 0
			;;
		    n*)
			configure=0
			option=${option#n}
			;;
		    *)
			usage 1
			;;
		esac
	    done

	    shift
	    ;;
	*)
	    finished=1
	    ;;
    esac
done

#
# Read the RC file
#
if [ $# -eq 0 ]; then
    if [ -f ./shorewallrc ]; then
        . ./shorewallrc || fatal_error "Can not load the RC file: ./shorewallrc"
    elif [ -f ~/.shorewallrc ]; then
        . ~/.shorewallrc || fatal_error "Can not load the RC file: ~/.shorewallrc"
    elif [ -f /usr/share/shorewall/shorewallrc ]; then
        . /usr/share/shorewall/shorewallrc || fatal_error "Can not load the RC file: /usr/share/shorewall/shorewallrc"
    else
	fatal_error "No configuration file specified and /usr/share/shorewall/shorewallrc not found"
    fi
elif [ $# -eq 1 ]; then
    file=$1
    case $file in
	/*|.*)
	    ;;
	*)
	    file=./$file || exit 1
	    ;;
    esac

    . $file || fatal_error "Can not load the RC file: $file"
else
    usage 1
fi

if [ -f ${SHAREDIR}/$PRODUCT/version ]; then
    INSTALLED_VERSION="$(cat ${SHAREDIR}/$PRODUCT/version)"
    if [ "$INSTALLED_VERSION" != "$VERSION" ]; then
	echo "WARNING: $Product Version $INSTALLED_VERSION is installed"
	echo "         and this is the $VERSION uninstaller."
	VERSION="$INSTALLED_VERSION"
    fi
else
    echo "WARNING: $Product Version $VERSION is not installed"
    VERSION=""
fi

echo "Uninstalling $Product $VERSION"

[ -n "$SANDBOX" ] && configure=0

[ -n "${LIBEXEC:=${SHAREDIR}}" ]

remove_file  ${SBINDIR}/$PRODUCT

FIREWALL=${CONFDIR}/init.d/$PRODUCT

if [ -f "$FIREWALL" ]; then
    if [ $configure -eq 1 ]; then
	if [ $HOST = openwrt ] ; then
	    if /etc/init.d/$PRODUCT enabled; then
		/etc/init.d/$PRODUCT disable
	    fi
	elif mywhich insserv ; then
            insserv -r $FIREWALL
	elif mywhich update-rc.d ; then
	    update-rc.d ${PRODUCT} remove
	elif mywhich chkconfig ; then
	    chkconfig --del $(basename $FIREWALL)
	fi
    fi

    remove_file $FIREWALL
fi

[ -z "${SERVICEDIR}" ] && SERVICEDIR="$SYSTEMD"

if [ -n "$SERVICEDIR" ]; then
    [ $configure -eq 1 ] && systemctl disable ${PRODUCT}.service
    remove_file $SERVICEDIR/${PRODUCT}.service
fi

if [ $HOST = openwrt ]; then
    [ "$(readlink -q ${SBINDIR}/ifup-local)"   = ${SHAREDIR}/$PRODUCT ] && remove_file ${SBINDIR}/ifup-local
    [ "$(readlink -q ${SBINDIR}/ifdown-local)" = ${SHAREDIR}/$PRODUCT ] && remove_file ${SBINDIR}/ifdown-local
else
    [ "$(readlink -m -q ${SBINDIR}/ifup-local)"   = ${SHAREDIR}/$PRODUCT ] && remove_file ${SBINDIR}/ifup-local
    [ "$(readlink -m -q ${SBINDIR}/ifdown-local)" = ${SHAREDIR}/$PRODUCT ] && remove_file ${SBINDIR}/ifdown-local
fi

remove_file ${CONFDIR}/default/$PRODUCT
remove_file ${CONFDIR}/sysconfig/$PRODUCT

remove_file ${CONFDIR}/NetworkManager/dispatcher.d/01-shorewall

remove_file ${CONFDIR}/network/if-up.d/shorewall
remove_file ${CONFDIR}/network/if-down.d/shorewall
remove_file ${CONFDIR}/network/if-post-down.d/shorewall

remove_file ${CONFDIR}/sysconfig/network/if-up.d/shorewall
remove_file ${CONFDIR}/sysconfig/network/if-down.d/shorewall

if [ -d ${CONFDIR}/ppp ]; then
    for directory in ip-up.d ip-down.d ipv6-up.d ipv6-down.d; do
	remove_file ${CONFDIR}/ppp/$directory/shorewall
    done

    for file in if-up.local if-down.local; do
	if [ -f ${CONFDIR}/ppp/$file ]; then
	    if grep -qF Shorewall-based ${CONFDIR}/ppp/$FILE; then
		remove_file ${CONFDIR}/ppp/$FILE
	    fi
	fi
    done
fi

remove_directory ${SHAREDIR}/$PRODUCT
remove_directory ${LIBEXECDIR}/$PRODUCT
remove_file  ${CONFDIR}/logrotate.d/$PRODUCT

#
# Report Success
#
echo "$Product $VERSION Uninstalled"
