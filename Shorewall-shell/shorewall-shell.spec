%define name shorewall-shell
%define version 4.0.0
%define release 0Beta6
%define prefix /usr

Summary: Shoreline Firewall is an iptables-based firewall for Linux systems.
Name: %{name}
Version: %{version}
Release: %{release}
Prefix: %{prefix}
License: GPL
Packager: Tom Eastep <teastep@shorewall.net>
Group: Networking/Utilities
Source: %{name}-%{version}.tgz
URL: http://www.shorewall.net/
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Requires: iptables iproute
Provides: shorewall_compiler

%description

The Shoreline Firewall, more commonly known as "Shorewall", is a Netfilter
(iptables) based firewall that can be used on a dedicated firewall system,
a multi-function gateway/ router/server or on a standalone GNU/Linux system.

%prep

%setup

%build

%install
export PREFIX=$RPM_BUILD_ROOT ; \
export OWNER=`id -n -u` ; \
export GROUP=`id -n -g` ;\
./install.sh -n

%clean
rm -rf $RPM_BUILD_ROOT

%post

%preun

%files
%defattr(0644,root,root,0755)
%attr(0755,root,root) %dir /usr/share/shorewall-shell

%attr(0555,root,root) /usr/share/shorewall-shell/compiler
%attr(0444,root,root) /usr/share/shorewall-shell/lib.accounting
%attr(0444,root,root) /usr/share/shorewall-shell/lib.actions
%attr(0444,root,root) /usr/share/shorewall-shell/lib.maclist
%attr(0444,root,root) /usr/share/shorewall-shell/lib.nat
%attr(0444,root,root) /usr/share/shorewall-shell/lib.providers
%attr(0444,root,root) /usr/share/shorewall-shell/lib.proxyarp
%attr(0444,root,root) /usr/share/shorewall-shell/lib.tc
%attr(0444,root,root) /usr/share/shorewall-shell/lib.tcrules
%attr(0444,root,root) /usr/share/shorewall-shell/lib.tunnels
%attr(0644,root,root) /usr/share/shorewall-shell/prog.footer
%attr(0644,root,root) /usr/share/shorewall-shell/prog.header
%attr(0644,root,root) /usr/share/shorewall-shell/version

%doc COPYING INSTALL 

%changelog
* Wed Jun 20 2007 Tom Eastep tom@shorewall.net
- Updated to 4.0.0-0Beta6
* Thu Jun 14 2007 Tom Eastep tom@shorewall.net
- Updated to 4.0.0-0Beta5
* Fri Jun 08 2007 Tom Eastep tom@shorewall.net
- Updated to 4.0.0-0Beta4
* Tue Jun 05 2007 Tom Eastep tom@shorewall.net
- Updated to 4.0.0-0Beta3
* Tue May 15 2007 Tom Eastep tom@shorewall.net
- Updated to 4.0.0-0Beta1
* Fri May 11 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.6-1
* Sat May 05 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.6-1
* Mon Apr 30 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.5-1
* Mon Apr 23 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.4-1
* Wed Apr 18 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.3-1
* Mon Apr 16 2007 Tom Eastep tom@shorewall.net
- Moved lib.dynamiczones to Shorewall-common
* Sat Apr 14 2007 Tom Eastep tom@shorewall.net
- Updated to 3.9.2-1
* Tue Apr 03 2007 Tom Eastep tom@shorewall.net
- Initial Version


