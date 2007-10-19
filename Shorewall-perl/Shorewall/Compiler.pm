#! /usr/bin/perl -w
#
#     The Shoreline Firewall4 (Shorewall-perl) Packet Filtering Firewall Compiler - V4.0
#
#     This program is under GPL [http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt]
#
#     (c) 2007 - Tom Eastep (teastep@shorewall.net)
#
#	Complete documentation is available at http://shorewall.net
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of Version 2 of the GNU General Public License
#	as published by the Free Software Foundation.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

package Shorewall::Compiler;
require Exporter;
use Shorewall::Config;
use Shorewall::Chains;
use Shorewall::Zones;
use Shorewall::Policy;
use Shorewall::Nat;
use Shorewall::Providers;
use Shorewall::Tc;
use Shorewall::Tunnels;
use Shorewall::Actions;
use Shorewall::Accounting;
use Shorewall::Rules;
use Shorewall::Proc;
use Shorewall::Proxyarp;

our @ISA = qw(Exporter);
our @EXPORT = qw( compiler EXPORT TIMESTAMP DEBUG );
our @EXPORT_OK = qw( $export );
our $VERSION = 4.0.4;

our $export;

our $reused = 0;

use constant { EXPORT => 0x01 ,
	       TIMESTAMP => 0x02 ,
	       DEBUG => 0x04 };

#
# Reinitilize the package-globals in the other modules
#
sub reinitialize() {
    Shorewall::Config::initialize;
    Shorewall::Chains::initialize;
    Shorewall::Zones::initialize;
    Shorewall::Policy::initialize;
    Shorewall::Nat::initialize;
    Shorewall::Providers::initialize;
    Shorewall::Tc::initialize;
    Shorewall::Actions::initialize;
    Shorewall::Accounting::initialize;
    Shorewall::Rules::initialize;
    Shorewall::Proxyarp::initialize;
}

#
# First stage of script generation.
#
#    Copy the prog.header to the generated script.
#    Generate the various user-exit jacket functions.
#    Generate the 'initialize()' function.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the object file.

sub generate_script_1() {

    my $date = localtime;

    emit "#!/bin/sh\n#\n# Compiled firewall script generated by Shorewall-perl $globals{VERSION} - $date\n#";

    copy $globals{SHAREDIRPL} . 'prog.header';

    for my $exit qw/init isusable start tcclear started stop stopped clear refresh refreshed/ {
	emit "\nrun_${exit}_exit() {";
	push_indent;
	append_file $exit or emit 'true';
	pop_indent;
	emit '}';
    }

    emit ( '',
	   '#',
	   '# This function initializes the global variables used by the program',
	   '#',
	   'initialize()',
	   '{',
	   '    #',
	   '    # These variables are required by the library functions called in this script',
	   '    #'
	   );

    push_indent;

    if ( $export ) {
	emit ( 'SHAREDIR=/usr/share/shorewall-lite',
	       'CONFDIR=/etc/shorewall-lite',
	       'PRODUCT="Shorewall Lite"'
	       );
    } else {
	emit ( 'SHAREDIR=/usr/share/shorewall',
	       'CONFDIR=/etc/shorewall',
	       'PRODUCT=\'Shorewall\'',
	       );
    }

    emit( '[ -f ${CONFDIR}/vardir ] && . ${CONFDIR}/vardir' );

    if ( $export ) {
	emit ( 'CONFIG_PATH="/etc/shorewall-lite:/usr/share/shorewall-lite"' ,
	       '[ -n "${VARDIR:=/var/lib/shorewall-lite}" ]' );
    } else {
	emit ( qq(CONFIG_PATH="$config{CONFIG_PATH}") ,
	       '[ -n "${VARDIR:=/var/lib/shorewall}" ]' );
    }

    emit 'TEMPFILE=';

    propagateconfig;

    emit ( '[ -n "${COMMAND:=restart}" ]',
	   '[ -n "${VERBOSE:=0}" ]',
	   qq([ -n "\${RESTOREFILE:=$config{RESTOREFILE}}" ]),
	   '[ -n "$LOGFORMAT" ] || LOGFORMAT="Shorewall:%s:%s:"',
	   qq(VERSION="$globals{VERSION}") ,
	   qq(PATH="$config{PATH}") ,
	   'TERMINATOR=fatal_error' ,
	   ''
	   );

    if ( $config{IPTABLES} ) {
	emit( qq(IPTABLES="$config{IPTABLES}"),
	      '[ -x "$IPTABLES" ] || startup_error "IPTABLES=$IPTABLES does not exist or is not executable"',
	      );
    } else {
	emit( '[ -z "$IPTABLES" ] && IPTABLES=$(mywhich iptables) # /sbin/shorewall exports IPTABLES',
	      '[ -n "$IPTABLES" -a -x "$IPTABLES" ] || startup_error "Can\'t find iptables executable"'
	      );
    }

    emit( 'IPTABLES_RESTORE=${IPTABLES}-restore',
	  '[ -x "$IPTABLES_RESTORE" ] || startup_error "$IPTABLES_RESTORE does not exist or is not executable"' );

    append_file 'params' if $config{EXPORTPARAMS};

    emit ( '',
	   "STOPPING=",
	   '',
	   '#',
	   '# The library requires that ${VARDIR} exist',
	   '#',
	   '[ -d ${VARDIR} ] || mkdir -p ${VARDIR}'
	   );

    emit ( '',
	   '#',
	   '# Recent kernels are difficult to configure -- we see state match omitted a lot so we check for it here',
	   '#',
	   'qt $IPTABLES -N foox1234',
	   'qt $IPTABLES -A foox1234 -m state --state ESTABLISHED,RELATED -j ACCEPT',
	   'result=$?',
	   'qt $IPTABLES -F foox1234',
	   'qt $IPTABLES -X foox1234',
	   '[ $result = 0 ] || startup_error "Your kernel/iptables do not include state match support. No version of Shorewall will run on this system"',
	   '' );

    pop_indent;

    emit "}\n"; # End of initialize()

}

sub compile_stop_firewall() {

    emit <<'EOF';
#
# Stop/restore the firewall after an error or because of a 'stop' or 'clear' command
#
stop_firewall() {

    deletechain() {
	qt $IPTABLES -L $1 -n && qt $IPTABLES -F $1 && qt $IPTABLES -X $1
    }

    deleteallchains() {
	$IPTABLES -F
	$IPTABLES -X
    }

    setcontinue() {
	$IPTABLES -A $1 -m state --state ESTABLISHED,RELATED -j ACCEPT
    }

    delete_nat() {
	$IPTABLES -t nat -F
	$IPTABLES -t nat -X

	if [ -f ${VARDIR}/nat ]; then
	    while read external interface; do
		del_ip_addr $external $interface
	    done < ${VARDIR}/nat

	    rm -f ${VARDIR}/nat
	fi
    }

    case $COMMAND in
	stop|clear|restore)
	    ;;
	*)
	    set +x

            case $COMMAND in
	        start)
	            logger -p kern.err "ERROR:$PRODUCT start failed"
	            ;;
	        restart)
	            logger -p kern.err "ERROR:$PRODUCT restart failed"
	            ;;
	        restore)
	            logger -p kern.err "ERROR:$PRODUCT restore failed"
	            ;;
            esac

            if [ "$RESTOREFILE" = NONE ]; then
                COMMAND=clear
                clear_firewall
                echo "$PRODUCT Cleared"

	        kill $$
	        exit 2
            else
	        RESTOREPATH=${VARDIR}/$RESTOREFILE

	        if [ -x $RESTOREPATH ]; then

		    if [ -x ${RESTOREPATH}-ipsets ]; then
		        progress_message2 Restoring Ipsets...
		        #
		        # We must purge iptables to be sure that there are no
		        # references to ipsets
		        #
		        for table in mangle nat filter; do
			    $IPTABLES -t $table -F
			    $IPTABLES -t $table -X
		        done

		        ${RESTOREPATH}-ipsets
		    fi

		    echo Restoring ${PRODUCT:=Shorewall}...

		    if $RESTOREPATH restore; then
		        echo "$PRODUCT restored from $RESTOREPATH"
		        set_state "Started"
		    else
		        set_state "Unknown"
		    fi

	            kill $$
	            exit 2
	        fi
            fi
	    ;;
    esac

    set_state "Stopping"

    STOPPING="Yes"

    TERMINATOR=

    deletechain shorewall

    run_stop_exit
EOF

    if ( $capabilities{MANGLE_ENABLED} ) {
	emit <<'EOF';
    run_iptables -t mangle -F
    run_iptables -t mangle -X
    for chain in PREROUTING INPUT FORWARD POSTROUTING; do
	qt $IPTABLES -t mangle -P $chain ACCEPT
    done
EOF
    }

    if ( $capabilities{RAW_TABLE} ) {
	emit <<'EOF';
    run_iptables -t raw -F
    run_iptables -t raw -X
    for chain in PREROUTING OUTPUT; do
	qt $IPTABLES -t raw -P $chain ACCEPT
    done
EOF
    }

    if ( $capabilities{NAT_ENABLED} ) {
	emit <<'EOF';
    delete_nat
    for chain in PREROUTING POSTROUTING OUTPUT; do
        qt $IPTABLES -t nat -P $chain ACCEPT
    done
EOF
    }

    emit <<'EOF';
    if [ -f ${VARDIR}/proxyarp ]; then
	while read address interface external haveroute; do
	    qt arp -i $external -d $address pub
	    [ -z "${haveroute}${NOROUTES}" ] && qt ip route del $address dev $interface
	    f=/proc/sys/net/ipv4/conf/$interface/proxy_arp
	    [ -f $f ] && echo 0 > $f
	done < ${VARDIR}/proxyarp
    fi

    rm -f ${VARDIR}/proxyarp
EOF

    push_indent;

    emit 'delete_tc1' if $config{CLEAR_TC};

    emit( 'undo_routing',
	  'restore_default_route'
	  );

    my $criticalhosts = process_criticalhosts;

    if ( @$criticalhosts ) {
	if ( $config{ADMINISABSENTMINDED} ) {
	    emit ( 'for chain in INPUT OUTPUT; do',
		    '    setpolicy $chain ACCEPT',
		    'done',
		    '',
		    'setpolicy FORWARD DROP',
		    '',
		    'deleteallchains',
		    ''
		    );

	    for my $hosts ( @$criticalhosts ) {
                my ( $interface, $host ) = ( split /:/, $hosts );
                my $source = match_source_net $host;
		my $dest   = match_dest_net $host;

		emit( "\$IPTABLES -A INPUT  -i $interface $source -j ACCEPT",
		      "\$IPTABLES -A OUTPUT -o $interface $dest   -j ACCEPT"
		      );
	    }

	    emit( '',
		  'for chain in INPUT OUTPUT; do',
		  '    setpolicy $chain DROP',
		  "done\n"
		  );
	  } else {
	    emit( '',
		  'for chain in INPUT OUTPUT; do',
		  '    setpolicy \$chain ACCEPT',
		  'done',
		  '',
		  'setpolicy FORWARD DROP',
		  '',
		  "deleteallchains\n"
		  );

	    for my $hosts ( @$criticalhosts ) {
                my ( $interface, $host ) = ( split /:/, $hosts );
                my $source = match_source_net $host;
		my $dest   = match_dest_net $host;

		emit(  "\$IPTABLES -A INPUT  -i $interface $source -j ACCEPT",
		       "\$IPTABLES -A OUTPUT -o $interface $dest   -j ACCEPT"
		       );
	    }

	    emit( "\nsetpolicy INPUT DROP",
		  '',
		  'for chain in INPUT FORWARD; do',
		  '    setcontinue $chain',
		  "done\n"
		  );
	}
    } elsif ( $config{ADMINISABSENTMINDED} ) {
	emit( 'for chain in INPUT FORWARD; do',
	      '    setpolicy $chain DROP',
	      'done',
	      '',
	      'setpolicy OUTPUT ACCEPT',
	      '',
	      'deleteallchains',
	      '',
	      'for chain in INPUT FORWARD; do',
	      '    setcontinue $chain',
	      "done\n",
	      );
    } else {
	emit( 'for chain in INPUT OUTPUT FORWARD; do',
	      '    setpolicy $chain DROP',
	      'done',
	      '',
	      "deleteallchains\n"
	      );
    }

    process_routestopped;

    emit( '$IPTABLES -A INPUT  -i lo -j ACCEPT',
	  '$IPTABLES -A OUTPUT -o lo -j ACCEPT'
	  );

    emit '$IPTABLES -A OUTPUT -o lo -j ACCEPT' unless $config{ADMINISABSENTMINDED};

    my $interfaces = find_interfaces_by_option 'dhcp';

    for my $interface ( @$interfaces ) {
	emit "\$IPTABLES -A INPUT  -p udp -i $interface --dport 67:68 -j ACCEPT";
	emit "\$IPTABLES -A OUTPUT -p udp -o $interface --dport 67:68 -j ACCEPT" unless $config{ADMINISABSENTMINDED};
	#
	# This might be a bridge
	#
	emit "\$IPTABLES -A FORWARD -p udp -i $interface -o $interface --dport 67:68 -j ACCEPT";
    }

    emit '';

    if ( $config{IP_FORWARDING} eq 'on' ) {
	emit( 'echo 1 > /proc/sys/net/ipv4/ip_forward',
	      'progress_message2 IP Forwarding Enabled' );
    } elsif ( $config{IP_FORWARDING} eq 'off' ) {
	emit( 'echo 0 > /proc/sys/net/ipv4/ip_forward',
	      'progress_message2 IP Forwarding Disabled!'
	      );
    }

    emit 'run_stopped_exit';

    pop_indent;

    emit '
    set_state "Stopped"

    logger -p kern.info "$PRODUCT Stopped"

    case $COMMAND in
    stop|clear)
	;;
    *)
	#
	# The firewall is being stopped when we were trying to do something
	# else. Kill the shell in case we\'re running in a subshell
	#
	kill $$
	;;
    esac
}
';

}

#
# Second Phase of Script Generation
#
#    copies the 'prog.functions' file into the script, generates
#    clear_routing_and_traffic_shaping() and the first part of
#    'setup_routing_and_traffic_shaping()'
#
#    The bulk of that function is produced by the various config file
#    parsing routines that are called directly out of 'compiler()'.
#
#    We create two separate functions rather than one so that the
#    define_firewall() shell function can set global IP configuration variables
#    after the old config has been cleared and before we start instantiating
#    the new config. That way, the variables reflect the way that the
#    distribution's tools have configured IP without any Shorewall
#    modifications and the firewall configuration is the same after
#    'restart' as it is after 'start'.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the object file.
#
sub generate_script_2 () {

    copy $globals{SHAREDIRPL} . 'prog.functions';

    emit(  '',
	   '#',
	   '# Clear Routing and Traffic Shaping',
	   '#',
	   'clear_routing_and_traffic_shaping() {'
	   );

    push_indent;

    save_progress_message 'Initializing...';

    if ( $export ) {
	my $fn = find_file 'modules';

	if ( $fn ne "$globals{SHAREDIR}/modules" && -f $fn ) {
	    emit 'echo MODULESDIR="$MODULESDIR" > ${VARDIR}/.modulesdir';
	    emit 'cat > ${VARDIR}/.modules << EOF';
	    open_file $fn;
	    while ( read_a_line ) {
		emit_unindented $currentline;
	    }
	    emit_unindented 'EOF';
	    emit 'reload_kernel_modules < ${VARDIR}/.modules';
	} else {
	    emit 'load_kernel_modules Yes';
	}
    } else {
	emit 'load_kernel_modules Yes';
    }

    emit '';

    for my $interface ( @{find_interfaces_by_option 'norfc1918'} ) {
	emit ( "addr=\$(ip -f inet addr show $interface 2> /dev/null | grep 'inet\ ' | head -n1)",
		'if [ -n "$addr" ]; then',
		'    addr=$(echo $addr | sed \'s/inet //;s/\/.*//;s/ peer.*//\')',
		'    for network in 10.0.0.0/8 176.16.0.0/12 192.168.0.0/16; do',
		'        if in_network $addr $network; then',
		"            error_message \"WARNING: The 'norfc1918' option has been specified on an interface with an RFC 1918 address. Interface:$interface\"",
		'        fi',
		'    done',
		"fi\n" );
    }

    emit ( '[ "$COMMAND" = refresh ] && run_refresh_exit || run_init_exit',
	    '',
	    'qt $IPTABLES -L shorewall -n && qt $IPTABLES -F shorewall && qt $IPTABLES -X shorewall',
	    '',
	    'delete_proxyarp',
	    ''
	    );

    if ( $capabilities{NAT_ENABLED} ) {
	emit(  'if [ -f ${VARDIR}/nat ]; then',
	       '    while read external interface; do',
	       '        del_ip_addr $external $interface',
	       '    done < ${VARDIR}/nat',
	       '',
	       '    rm -f ${VARDIR}/nat',
	       "fi\n" );
    }

    emit "delete_tc1\n"            if $config{CLEAR_TC};
    emit "disable_ipv6\n"          if $config{DISABLE_IPV6};

    pop_indent;

    emit "}\n";

    emit(  '#',
	   '# Setup Routing and Traffic Shaping',
	   '#',
	   'setup_routing_and_traffic_shaping() {'
	   );

    push_indent;

}

#
# Third (final) stage of script generation.
#
#    Generate the end of 'setup_routing_and_traffic_shaping()':
#        Generate code for loading the various files in /var/lib/shorewall[-lite]
#        Generate code to add IP addresses under ADD_IP_ALIASES and ADD_SNAT_ALIASES
#
#    Generate the 'setup_netfilter()' function that runs iptables-restore.
#    Generate the 'define_firewall()' function.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the object file.
#
sub generate_script_3($) {

    emit 'cat > ${VARDIR}/proxyarp << __EOF__';
    dump_proxy_arp;
    emit_unindented '__EOF__';

    emit( '',
	  'if [ "$COMMAND" != refresh ]; then' );

    push_indent;

    emit 'cat > ${VARDIR}/chains << __EOF__';
    dump_rule_chains;
    emit_unindented '__EOF__';

    emit 'cat > ${VARDIR}/zones << __EOF__';
    dump_zone_contents;
    emit_unindented '__EOF__';

    pop_indent;

    emit "fi\n";

    emit '> ${VARDIR}/nat';

    add_addresses;

    pop_indent;

    emit "}\n";

    progress_message2 "Creating iptables-restore input...";
    create_netfilter_load;
    create_chainlist_reload( $_[0] );

    emit "#\n# Start/Restart the Firewall\n#";
    emit 'define_firewall() {';
    push_indent;

    emit "\nclear_routing_and_traffic_shaping";

    set_global_variables;

    emit '';

    emit<<'EOF';
setup_routing_and_traffic_shaping

if [ $COMMAND = restore ]; then
    iptables_save_file=${VARDIR}/$(basename $0)-iptables
    if [ -f $iptables_save_file ]; then
        cat $iptables_save_file | $IPTABLES_RESTORE # Use this nonsensical form to appease SELinux
    else
        fatal_error "$iptables_save_file does not exist"
    fi
    set_state "Started"
else
    if [ $COMMAND = refresh ]; then
        chainlist_reload
        run_refreshed_exit
        $IPTABLES -N shorewall
        set_state "Started"
    else
        setup_netfilter
        restore_dynamic_rules
        run_start_exit
        $IPTABLES -N shorewall
        set_state "Started"
        run_started_exit
    fi

    cp -f $(my_pathname) ${VARDIR}/.restore
fi

date > ${VARDIR}/restarted

case $COMMAND in
    start)
        logger -p kern.info "$PRODUCT started"
        ;;
    restart)
        logger -p kern.info "$PRODUCT restarted"
        ;;
    refresh)
        logger -p kern.info "$PRODUCT refreshed"
        ;;
    restore)
        logger -p kern.info "$PRODUCT restored"
        ;;
esac
EOF

    pop_indent;

    emit "}\n";

    copy $globals{SHAREDIRPL} . 'prog.footer';
}

#
#  The Compiler.
#
#    If the first argument is non-null, it names the script file to generate.
#    Otherwise, this is a 'check' command and no script is produced.
#
sub compiler( $$$$$ ) {

    my ( $objectfile, $directory, $verbosity, $options , $chains ) = @_;

    $export = 0;

    reinitialize if $reused++;

    if ( $directory ne '' ) {
	fatal_error "$directory is not an existing directory" unless -d $directory;
	set_shorewall_dir( $directory );
    }

    set_verbose( $verbosity ) unless $verbosity eq '';
    $export = 1               if $options & EXPORT;
    set_timestamp( 1 )        if $options & TIMESTAMP;
    set_debug( 1 )            if $options & DEBUG;
    #
    # Get shorewall.conf and capabilities.
    #
    get_configuration( $export );

    report_capabilities;

    require_capability( 'MULTIPORT'       , "Shorewall-perl $globals{VERSION}" , 's' );
    require_capability( 'RECENT_MATCH'    , 'MACLIST_TTL' , 's' )           if $config{MACLIST_TTL};
    require_capability( 'XCONNMARK'       , 'HIGH_ROUTE_MARKS=Yes' , 's' )  if $config{HIGH_ROUTE_MARKS};
    require_capability( 'MANGLE_ENABLED'  , 'Traffic Shaping' , 's'      )  if $config{TC_ENABLED};
    require_capability( 'CONNTRACK_MATCH' , 'RFC1918_STRICT=Yes' , 's'   )  if $config{RFC1918_STRICT};

    set_command( 'check', 'Checking', 'Checked' ) unless $objectfile;

    initialize_chain_table;

    unless ( $command eq 'check' ) {
	create_temp_object( $objectfile );
	generate_script_1;
    }

    #
    # Process the zones file.
    #
    determine_zones;
    #
    # Process the interfaces file.
    #
    validate_interfaces_file ( $export );
    #
    # Process the hosts file.
    #
    validate_hosts_file;
    #
    # Report zone contents
    #
    zone_report;
    #
    # Do action pre-processing.
    #
    process_actions1;
    #
    # Process the Policy File.
    #
    validate_policy;
    #
    # Compile the 'stop_firewall()' function
    #
    compile_stop_firewall;
    #
    # Start Second Part of script
    #
    generate_script_2 unless $command eq 'check';
    #
    # Set up MSS rules
    #
    setup_mss;
    #
    # Do all of the zone-independent stuff
    #
    add_common_rules;
    #
    # /proc stuff
    #
    setup_arp_filtering;
    setup_route_filtering;
    setup_martian_logging;
    setup_source_routing;
    setup_forwarding;
    #
    # Proxy Arp
    #
    setup_proxy_arp;
    #
    # Handle MSS setings in the zones file
    #
    setup_zone_mss;
    #
    # [Re-]establish Routing
    #
    setup_providers;
    #
    # TOS
    #
    process_tos;
    #
    # ECN
    #
    setup_ecn;
    #
    # Setup Masquerading/SNAT
    #
    setup_masq;
    #
    # MACLIST Filtration
    #
    setup_mac_lists 1;
    #
    # Process the rules file.
    #
    process_rules;
    #
    # Add Tunnel rules.
    #
    setup_tunnels;
    #
    # Post-rules action processing.
    #
    process_actions2;
    process_actions3;
    #
    # MACLIST Filtration again
    #
    setup_mac_lists 2;
    #
    # Apply Policies
    #
    apply_policy_rules;
    #
    # TCRules and Traffic Shaping
    #
    setup_tc;
    #
    # Setup Nat
    #
    setup_nat;
    #
    # Setup NETMAP
    #
    setup_netmap;
    #
    # Accounting.
    #
    setup_accounting;
    #
    # We generate the matrix even though we don't write out the rules. That way, we insure that
    # a compile of the script won't blow up during that step.
    #
    generate_matrix;

    if ( $command eq 'check' ) {
	progress_message3 "Shorewall configuration verified";
    } else {
	#
	# Finish the script.
	#
	generate_script_3( $chains );
	finalize_object ( $export );
	#
	# And generate the auxilary config file
	#
	generate_aux_config if $export;
    }

    1;
}

1;
