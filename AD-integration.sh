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
	echo "Install SSSD REALM NTPDATE"
	yum -y update  > /dev/null
	f_news "System Updated Correctly" "Had a problem updating System"
	yum -y install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano > /dev/null
	f_news "Services Installed Correctly" "Had a problem installing Services"
	
	echo "Configure ntpserver"
	sed -i 's/^server/#server/g' /etc/ntp.conf
	f_news "Services Installed Correctly" "Had a problem installing Services"
	echo server $NTPS >> /etc/ntp.conf
	systemctl restart ntpd > /dev/null
	f_news "NTP Service configured correctly" "Had a problem configuring NTP"
	
	echo "Change Secure Settings"
	echo "SELINUX to Permissive"
	sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
	setenforce 0 > /dev/null
	f_news "NTP Service configured correctly" "Had a problem configuring NTP"
	
	echo "Setting UP Networking INFO for Active Directory Join"
	sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/network-scripts/ifcfg-eth0
	echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
	echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
	echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
	systemctl restart network > /dev/null
	f_news "Network Services configured correctly" "Had a problem configuring Network Services"
	
	echo "DOMAIN TESTING"
	if ping -c3 $DOMAINREALM
	then
	    realm discover $DOMAINREALM > /dev/null
	    f_news "Domain Controler discovered correctly" "Had a problem discovering Domain Controler"
	else
	    echo "Domain not reacheable"
	fi
	
	echo "Domain Join"
	echo -n $ADPASS|kinit $ADUSER@$DOMAINREALM 
	f_news "Kerberos service configured correctly" "Had a problem configuring Kerberos"
	
	echo -n $ADPASS |realm join --verbose $DOMAINREALM -U $ADUSER@$DOMAINREALM
	f_news "Server joined domain configured correctly" "Had a problem joining Domain"

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
	    sed -i 's/^default_shell.*/default_shell=\/bin\/bash/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD"
	    sed -i 's/^use_fully_qualified_names.*/use_fully_qualified_names=False/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD"
	    sed -i 's/^fallback_homedir.*/fallback_homedir=\/home\/\%u/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD"
	    sed -i 's/^override_homedir.*/override_homedir=\/home\/\%u/g' /etc/sssd/sssd.conf
	    f_news "SSSD Service configured correctly" "Had a problem configuring SSSD"
	else
	    echo "Not Overriding SSSD conf"
	fi
	systemctl restart sssd realmd > /dev/null
	f_news "SSSD Service restarted correctly" "Had a problem restarting SSSD"
	
	echo "Domain Integration Testing"
	echo " ID Testing"
	id $ADUSER@$DOMAINREALM > /dev/null
	f_news "Domain Controler User Testing 01 - OK" "Domain Controler User Testing 01 - Had a problem"
	id $ADUSER > /dev/null
	f_news "Domain Controler User Testing 02 - OK" "Domain Controler User Testing 02 - Had a problem"
	
	echo " SU - Testing"
	su - $ADUSER@$DOMAINREALM -c pwd > /dev/null
	f_news "Domain Controler User Testing 03 - OK" "Domain Controler User Testing 03 - Had a problem"
	
	su - $ADUSER -c pwd > /dev/null
	f_news "Domain Controler User Testing 04 - OK" "Domain Controler User Testing 04 - Had a problem"
	
	;;
    leave)
	realm leave -v -U $3 $2
	;;
    *)
	echo "Usage: $0 {join REALM ADMINADUSER NTPSERVER DNS1 DNS2 SEARCHDOMAIN PASSWORD | leave REALM ADMINADUSER PASSWORD}"
	exit 2
	;;
esac
