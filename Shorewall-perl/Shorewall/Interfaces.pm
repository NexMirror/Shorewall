#
# Shorewall-perl 4.0 -- /usr/share/shorewall-perl/Shorewall/Interfaces.pm
#
#     This program is under GPL [http://www.gnu.org/copyleft/gpl.htm]
#
#     (c) 2007 - Tom Eastep (teastep@shorewall.net)
#
#       Complete documentation is available at http://shorewall.net
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
#   This Module contains the code for processing the /etc/shorewall/interfaces
#   file. It also exports 'add_group_to_zone()' which other modules call to
#   alter zone membership.
#

package Shorewall::Interfaces;
require Exporter;
use Shorewall::Common;
use Shorewall::Config;
use Shorewall::IPAddrs;
use Shorewall::Zones;

use strict;

our @ISA = qw(Exporter);
our @EXPORT = qw( add_group_to_zone
		  validate_interfaces_file
		  known_interface
		  port_to_bridge
		  source_port_to_bridge
		  interface_is_optional
		  find_interfaces_by_option
		  get_interface_option

		  @interfaces
		  @bridges );
our @EXPORT_OK = qw( initialize );
our @VERSION = 1.00;

#
#     Interface Table.
#
#     @interfaces lists the interface names in the order that they appear in the interfaces file.
#
#     %interfaces { <interface1> => { root        => <name without trailing '+'>
#                                     options     => { <option1> = <val1> ,
#                                                      ...
#                                                    }
#                                     zone        => <zone name>
#                                     bridge      => <bridge>
#                                   }
#                 }
#
our @interfaces;
our %interfaces;
our @bridges;

sub initialize() {
    @interfaces = ();
    %interfaces = ();
    @bridges    = ();
}

INIT {
    initialize;
}

sub add_group_to_zone($$$$$)
{
    my ($zone, $type, $interface, $networks, $options) = @_;
    my $typeref;
    my $interfaceref;
    my $arrayref;
    my $zoneref  = $zones{$zone};
    my $zonetype = $zoneref->{type};
    my $ifacezone = $interfaces{$interface}{zone};

    $zoneref->{interfaces}{$interface} = 1;

    my @newnetworks;
    my @exclusions;
    my $new = \@newnetworks;
    my $switched = 0;

    $ifacezone = '' unless defined $ifacezone;

    for my $host ( @$networks ) {
	fatal_error "Invalid Host List" unless defined $host and $host ne '';

	if ( substr( $host, 0, 1 ) eq '!' ) {
	    fatal_error "Only one exclusion allowed in a host list" if $switched;
	    $switched = 1;
	    $host = substr( $host, 1 );
	    $new = \@exclusions;
	}

	unless ( $switched ) {
	    if ( $type eq $zonetype ) {
		fatal_error "Duplicate Host Group ($interface:$host) in zone $zone" if $ifacezone eq $zone;
		$ifacezone = $zone if $host eq ALLIPv4;
	    }
	}

	push @$new, $switched ? "$interface:$host" : $host;
    }

    $zoneref->{options}{in_out}{routeback} = 1 if $options->{routeback};

    $typeref      = ( $zoneref->{hosts}           || ( $zoneref->{hosts} = {} ) );
    $interfaceref = ( $typeref->{$type}           || ( $interfaceref = $typeref->{$type} = {} ) );
    $arrayref     = ( $interfaceref->{$interface} || ( $interfaceref->{$interface} = [] ) );

    $zoneref->{options}{complex} = 1 if @$arrayref || ( @newnetworks > 1 ) || ( @exclusions );

    my %h;

    $h{options} = $options;
    $h{hosts}   = \@newnetworks;
    $h{ipsec}   = $type eq 'ipsec' ? 'ipsec' : 'none';

    push @{$zoneref->{exclusions}}, @exclusions;
    push @{$arrayref}, \%h;
}

#
# Return a list of networks routed out of the passed interface
#
sub get_routed_networks ( $$ ) {
    my ( $interface , $error_message ) = @_;
    my @networks;

    if ( open IP , '-|' , "/sbin/ip route show dev $interface 2> /dev/null" ) {
	while ( my $route = <IP> ) {
	    $route =~ s/^\s+//;
	    my $network = ( split /\s+/, $route )[0];
	    if ( $network eq 'default' ) {
		fatal_error $error_message if $error_message;
		warning_message "default route ignored on interface $interface";
	    } else {
		my ( $address, $vlsm ) = split '/', $network;
		$vlsm = 32 unless defined $vlsm;
		push @networks, "$address/$vlsm";
	    }
	}
	close IP
    }

    @networks;
}

#
# Parse the interfaces file.
#

sub validate_interfaces_file( $ )
{
    my $export = shift;

    use constant { SIMPLE_IF_OPTION   => 1,
		   BINARY_IF_OPTION   => 2,
		   ENUM_IF_OPTION     => 3, 
	           MASK_IF_OPTION     => 3,
	           
	           IF_OPTION_ZONEONLY => 4 };

    my %validoptions = (arp_filter  => BINARY_IF_OPTION,
			arp_ignore  => ENUM_IF_OPTION,
			blacklist   => SIMPLE_IF_OPTION,
			bridge      => SIMPLE_IF_OPTION,
			detectnets  => SIMPLE_IF_OPTION,
			dhcp        => SIMPLE_IF_OPTION,
			maclist     => SIMPLE_IF_OPTION,
			logmartians => BINARY_IF_OPTION,
			norfc1918   => SIMPLE_IF_OPTION,
			nosmurfs    => SIMPLE_IF_OPTION,
			optional    => SIMPLE_IF_OPTION,
			proxyarp    => BINARY_IF_OPTION,
			routeback   => SIMPLE_IF_OPTION + IF_OPTION_ZONEONLY,
			routefilter => BINARY_IF_OPTION,
			sourceroute => BINARY_IF_OPTION,
			tcpflags    => SIMPLE_IF_OPTION,
			upnp        => SIMPLE_IF_OPTION,
			);

    my $fn = open_file 'interfaces';

    my $first_entry = 1;

    my @ifaces;

    while ( read_a_line ) {

	if ( $first_entry ) {
	    progress_message2 "$doing $fn...";
	    $first_entry = 0;
	}
	
	my ($zone, $interface, $networks, $options ) = split_line 2, 4, 'interfaces file';
	my $zoneref;
	my $bridge = '';

	if ( $zone eq '-' ) {
	    $zone = '';
	} else {
	    $zoneref = $zones{$zone};

	    fatal_error "Unknown zone ($zone)" unless $zoneref;
	    fatal_error "Firewall zone not allowed in ZONE column of interface record" if $zoneref->{type} eq 'firewall';
	}

	$networks = '' if $networks eq '-';
	$options  = '' if $options  eq '-';

	( $interface, my ($port, $extra) ) = split /:/ , $interface, 3;

	fatal_error "Invalid INTERFACE" if defined $extra || ! $interface;	

	fatal_error "Invalid Interface Name ( $interface )" if $interface eq '+';

	if ( defined $port ) {
	    require_capability( 'PHYSDEV_MATCH', 'Bridge Ports', '');
	    require_capability( 'KLUDGEFREE', 'Bridge Ports', '');
	    fatal_error "Duplicate Interface ( $port )" if $interfaces{$port};
	    fatal_error "$interface is not a defined bridge" unless $interfaces{$interface} && $interfaces{$interface}{options}{bridge};
	    fatal_error "Invalid Interface Name ( $interface:$port )" unless $port =~ /^[\w.@%-]+\+?$/;
	    fatal_error "Bridge Ports may only be associated with 'bport' zones" if $zone && $zoneref->{type} ne 'bport4';

	    if ( $zone ) {
		if ( $zoneref->{bridge} ) {
		    fatal_error "Bridge Port zones may only be associated with a single bridge" if $zoneref->{bridge} ne $interface;
		} else {
		    $zoneref->{bridge} = $interface;
		}
	    }
	    
	    $interfaces{$port}{bridge} = $bridge = $interface;
	    $interface = $port;
	} else {
	    fatal_error "Duplicate Interface ( $interface )" if $interfaces{$interface};
	    fatal_error "Zones of type 'bport' may only be associated with bridge ports" if $zone && $zoneref->{type} eq 'bport4';
	    $interfaces{$interface}{bridge} = $interface;
	}
    
	my $wildcard = 0;

	if ( $interface =~ /\+$/ ) {
	    $wildcard = 1;
	    $interfaces{$interface}{root} = substr( $interface, 0, -1 );
	} else {	    
	    $interfaces{$interface}{root} = $interface;
	}

	unless ( $networks eq '' || $networks eq 'detect' ) {

	    for my $address ( split /,/, $networks ) {
		fatal_error 'Invalid BROADCAST address' unless $address =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
	    }

	    warning_message 'Shorewall no longer uses broadcast addresses in rule generation';
	}

	my $optionsref = {};

	my %options;
	
	if ( $options ) {
	    fatal_error "Bridge Ports may not have options" if defined $port;

	    for my $option (split ',', $options ) {
		next if $option eq '-';

		( $option, my $value ) = split /=/, $option;

		fatal_error "Invalid Interface option ($option)" unless my $type = $validoptions{$option};

		fatal_error "The \"$option\" option may not be specified on a multi-zone interface" if $type & IF_OPTION_ZONEONLY && ! $zone;
		
		$type &= MASK_IF_OPTION;

		if ( $type == SIMPLE_IF_OPTION ) {
		    fatal_error "Option $option does not take a value" if defined $value;
		    $options{$option} = 1;
		} elsif ( $type == BINARY_IF_OPTION ) {
		    $value = 1 unless defined $value;
		    fatal_error "Option value for $option must be 0 or 1" unless ( $value eq '0' || $value eq '1' );
		    fatal_error "The $option option may not be used with a wild-card interface name" if $wildcard;
		    $options{$option} = $value;
		} elsif ( $type == ENUM_IF_OPTION ) {
		    fatal_error "The $option option may not be used with a wild-card interface name" if $wildcard;
		    if ( $option eq 'arp_ignore' ) {
			if ( defined $value ) {
			    if ( $value =~ /^[1-3,8]$/ ) {
				$options{arp_ignore} = $value;
			    } else {
				fatal_error "Invalid value ($value) for arp_ignore";
			    } 
			} else {
			    $options{arp_ignore} = 1;
			}
		    } else {
			fatal_error "Internal Error in validate_interfaces_file";
		    }
		}
	    }

	    $zoneref->{options}{in_out}{routeback} = 1 if $zoneref && $options{routeback};

	    if ( $options{bridge} ) {
		require_capability( 'PHYSDEV_MATCH', 'The "bridge" option', 's');
		fatal_error "Bridges may not have wildcard names" if $wildcard;
		push @bridges, $interface;
	    }
	} elsif ( defined $port ) {
	    $options{port} = 1;
	}
	
	$interfaces{$interface}{options} = $optionsref = \%options;

	push @ifaces, $interface;

	my @networks;

	if ( $options{detectnets} ) {
	    fatal_error "The 'detectnets' option is not allowed on a multi-zone interface" unless $zone;
	    fatal_error "The 'detectnets' option may not be used with a wild-card interface name" if $wildcard;
	    fatal_error "The 'detectnets' option may not be used with the '-e' compiler option" if $export;
	    @networks = get_routed_networks( $interface, 'detectnets not allowed on interface with default route' );
	    fatal_error "No routes found through 'detectnets' interface $interface" unless @networks || $options{optional};
	    delete $options{maclist} unless @networks;
	} else {
	    @networks = @allipv4;
	}

	add_group_to_zone( $zone, $zoneref->{type}, $interface, \@networks, $optionsref ) if $zone && @networks;

    	$interfaces{$interface}{zone} = $zone; #Must follow the call to add_group_to_zone()
    
	progress_message "   Interface \"$line\" Validated";

    }

    #
    # We now assemble the @interfaces array such that bridge ports immediately precede their associated bridge
    #
    for my $interface ( @ifaces ) {
	my $interfaceref = $interfaces{$interface};
	
	if ( $interfaceref->{options}{bridge} ) {
	    my @ports = grep $interfaces{$_}{options}{port} && $interfaces{$_}{bridge} eq $interface, @ifaces;

	    if ( @ports ) {
		push @interfaces, @ports;
	    } else {
		$interfaceref->{options}{routeback} = 1; #so the bridge will work properly
	    }
	}

	push @interfaces, $interface unless $interfaceref->{options}{port};
    }	
}

#
# Returns true if passed interface matches an entry in /etc/shorewall/interfaces
#
# If the passed name matches a wildcard, a entry for the name is added in %interfaces to speed up validation of other references to that name.
#
sub known_interface($)
{
    my $interface = $_[0];

    return 1 if $interfaces{$interface};

    for my $i ( @interfaces ) {
	my $interfaceref = $interfaces{$i};
	my $val = $interfaceref->{root};
	next if $val eq $i;
	if ( substr( $interface, 0, length $val ) eq $val ) {
	    #
	    # Cache this result for future reference
	    #
	    $interfaces{$interface} = { options => $interfaceref->{options}, bridge => $interfaceref->{bridge} };
	    return 1;
	}
    }

    0;
}

#
# Return the bridge associated with the passed interface. If the interface is not a bridge port,
# return ''
#
sub port_to_bridge( $ ) {
    my $portref = $interfaces{$_[0]};
    return $portref && $portref->{options}{port} ? $portref->{bridge} : '';
}

#
# Return the bridge associated with the passed interface.
#
sub source_port_to_bridge( $ ) {
    my $portref = $interfaces{$_[0]};
    return $portref ? $portref->{bridge} : '';
}

#
# Return the 'optional' setting of the passed interface
#
sub interface_is_optional($) {
    my $optionsref = $interfaces{$_[0]}{options};
    $optionsref && $optionsref->{optional};
}

#
# Returns reference to array of interfaces with the passed option
#
sub find_interfaces_by_option( $ ) {
    my $option = $_[0];
    my @ints = ();

    for my $interface ( @interfaces ) {
	my $optionsref = $interfaces{$interface}{options};
	if ( $optionsref && defined $optionsref->{$option} ) {
	    push @ints , $interface
	}
    }

    \@ints;
}

#
# Return the value of an option for an interface
#
sub get_interface_option( $$ ) {
    my ( $interface, $option ) = @_;

    $interfaces{$interface}{options}{$option};
}

1;
