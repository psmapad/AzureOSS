#!/bin/bash
## File to deploy Domain Controler Integration on Centos
## Centos 7.4
## Tested on Azure 
## Developer: Manuel Alejandro Peña Sánchez
## AD Integration with sssd


DOMAINREALM=$2
ADUSER=$3
NTPS=$4
DNS1=$5
DNS2=$6
SEARCH=$7
ADPASS=$8

f_news(){
    RET=$?
    NOK=$1
    NBAD=$2

    if [ "$RET" -eq 0 ]
    then
	echo "$NOK"
    else
	echo "$NBAD"
	exit
    fi    
}


case $1 in
    join)
	echo "Install SSSD REALM NTPDATE" 3>&1 1> ~/ADEnroll.log
	yum -y update  3>&1 1>> ~/ADEnroll.log
	f_news "System Updated Correctly" "Had a problem updating System" 3>&1 1>> ~/ADEnroll.log
	yum -y install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano 3>&1 1>> ~/ADEnroll.log
	f_news "Services Installed Correctly" "Had a problem installing Services" 3>&1 1>> ~/ADEnroll.log
	
	echo "Configure ntpserver" 3>&1 1>> ~/ADEnroll.log
	sed -i 's/^server/#server/g' /etc/ntp.conf
	f_news "Services Installed Correctly" "Had a problem installing Services" 3>&1 1>> ~/ADEnroll.log
	echo server $NTPS >> /etc/ntp.conf
	systemctl restart ntpd 3>&1 1>> ~/ADEnroll.log
	f_news "NTP Service configured correctly" "Had a problem configuring NTP" 3>&1 1>> ~/ADEnroll.log
	
	echo "Change Secure Settings" 3>&1 1>> ~/ADEnroll.log
	echo "SELINUX to Permissive" 3>&1 1>> ~/ADEnroll.log
	sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
	setenforce 0  3>&1 1>> ~/ADEnroll.log
	f_news "NTP Service configured correctly" "Had a problem configuring NTP" 3>&1 1>> ~/ADEnroll.log
	
	echo "Setting UP Networking INFO for Active Directory Join"
	sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/network-scripts/ifcfg-eth0
	echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
	echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
	echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
	systemctl restart network  3>&1 1>> ~/ADEnroll.log
	f_news "Network Services configured correctly" "Had a problem configuring Network Services" 3>&1 1>> ~/ADEnroll.log
	
	echo "DOMAIN TESTING"
	if ping -c3 $DOMAINREALM
	then
	    realm discover $DOMAINREALM 3>&1 1>> ~/ADEnroll.log
	    f_news "Domain Controler discovered correctly" "Had a problem discovering Domain Controler" 3>&1 1>> ~/ADEnroll.log
	else
	    echo "Domain not reacheable" 3>&1 1>> ~/ADEnroll.log
	fi
	
	echo "Domain Join" 3>&1 1>> ~/ADEnroll.log
	echo -n $ADPASS|kinit $ADUSER@$DOMAINREALM  3>&1 1>> ~/ADEnroll.log
	f_news "Kerberos service configured correctly" "Had a problem configuring Kerberos" 3>&1 1>> ~/ADEnroll.log
	
	echo -n $ADPASS |realm join --verbose $DOMAINREALM -U $ADUSER@$DOMAINREALM 3>&1 1>> ~/ADEnroll.log
	f_news "Server joined domain configured correctly" "Had a problem joining Domain" 3>&1 1>> ~/ADEnroll.log

	cp /etc/idmapd.conf /etc/idmapd.conf.old
	> /etc/idmapd.conf
	
	cat << EOF >> /etc/idmapd.conf
[General]
Domain = $(echo $DOMAINREALM |awk '{ print tolower($0) }')
[Mapping]
Nobody-User = nobody
Nobody-Group = nobody
[Translation]
Method = nsswitch

EOF
	
	SSDCNF="s"
	if [ "$SSDCNF" == "s" ]
	then
	    mkdir -p /Domain/home
	    sed -i 's/^default_shell.*/default_shell=\/bin\/bash/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD" 3>&1 1>> ~/ADEnroll.log
	    sed -i 's/^use_fully_qualified_names.*/use_fully_qualified_names=False/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD" 3>&1 1>> ~/ADEnroll.log
	    sed -i 's/^fallback_homedir.*/fallback_homedir=\/Domain\/home\/\%u/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD" 3>&1 1>> ~/ADEnroll.log
	    sed -i 's/^override_homedir.*/override_homedir=\/Domain\/home\/\%u/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD" 3>&1 1>> ~/ADEnroll.log
	    access_provider = ad
	    cat << EOF >> /etc/sssd/sssd.conf
auth_provider = ad
chpass_provider = ad
access_provider = ad
ldap_schema = ad
dyndns_update = true
dyndns_refresh_interval = 43200
dyndns_update_ptr = true
dyndns_ttl = 3600

EOF
	else
	    echo "Not Overriding SSSD conf" 3>&1 1>> ~/ADEnroll.log
	fi
	systemctl restart sssd realmd  3>&1 1>> ~/ADEnroll.log
	f_news "SSSD Service restarted correctly" "Had a problem restarting SSSD" 3>&1 1>> ~/ADEnroll.log
	
	echo "Domain Integration Testing" 3>&1 1>> ~/ADEnroll.log
	echo " ID Testing" 3>&1 1>> ~/ADEnroll.log
	id $ADUSER@$DOMAINREALM  3>&1 1>> ~/ADEnroll.log
	f_news "Domain Controler User Testing 01 - OK" "Domain Controler User Testing 01 - Had a problem" 3>&1 1>> ~/ADEnroll.log
	id $ADUSER  3>&1 1>> ~/ADEnroll.log
	f_news "Domain Controler User Testing 02 - OK" "Domain Controler User Testing 02 - Had a problem" 3>&1 1>> ~/ADEnroll.log
	
	echo " SU - Testing" 3>&1 1>> ~/ADEnroll.log
	su - $ADUSER@$DOMAINREALM -c pwd 3>&1 1>> ~/ADEnroll.log
	f_news "Domain Controler User Testing 03 - OK" "Domain Controler User Testing 03 - Had a problem" 3>&1 1>> ~/ADEnroll.log
	
	su - $ADUSER -c pwd 3>&1 1>> ~/ADEnroll.log
	f_news "Domain Controler User Testing 04 - OK" "Domain Controler User Testing 04 - Had a problem" 3>&1 1>> ~/ADEnroll.log
	
	;;
    leave)
	realm leave -v -U $3 $2 3>&1 1>> ~/ADEnroll.log
	;;
    *)
	echo "Usage: $0 {join REALM ADMINADUSER NTPSERVER DNS1 DNS2 SEARCHDOMAIN PASSWORD | leave REALM ADMINADUSER PASSWORD}"
	exit 2
	;;
esac
