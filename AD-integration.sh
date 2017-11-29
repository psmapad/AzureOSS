#!/bin/bash
## File to deploy Domain Controler Integration on Centos
## Centos 7.3
## Tested on Azure 
## Developer: Manuel Alejandro Peña Sánchez
## AD Integration with sssd

DOMAINREALM="REALM IN UPPERCASE"
ADUSER="ACTIVE DIRECTORY ADMINISTRATOR USER"
NTPS="IP NTP SERVER/DOMAIN CONTROLER IP"

echo "Install SSSD REALM NTPDATE"
yum -y update
yum -y install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano

echo "Configure ntpserver"
sed -i 's/^server/#server/g' /etc/ntp.conf
echo server $NTPS >> /etc/ntpd.conf
systemctl restart ntpd
echo "Change Secure Settings"
echo "SELINUX to Permissive"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
setenforce 0
echo "Setting UP Networking INFO for Active Directory Join"
sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
systemctl restart network
echo "DOMAIN TESTING"
if ping -c3 $DOMAINREALM
then
    realm discover $DOMAINREALM
else
    echo "Domain not reacheable"
fi
echo "Domain Join"
kinit $ADUSER@$DOMAINREALM
realm join --verbose $DOMAINREALM -U $ADUSER@$DOMAINREALM
echo -n "Change SSSD Configuration?(s/n): "
SSDCNF="s"
read SSDCNF
if [ '$SSDCNF' == 's' ]
then
    sed 's/^default_shell.*/default_shell=\/bin\/bash/g' /etc/sssd/sssd.conf
    sed 's/^use_fully_qualified_names.*/use_fully_qualified_names=True/g' /etc/sssd/sssd.conf
    sed 's/^fallback_homedir.*/fallback_homedir=\/home\/\%u\/g' /etc/sssd/sssd.conf
    sed 's/^override_homedir.*/override_homedir=\/home\/\%u\/g' /etc/sssd/sssd.conf
else
    echo "Not Overriding SSSD conf"
fi
systemctl restart sssd realmd
echo "Domain Integration Testing"
echo " ID Testing"
id $ADUSER@$DOMAINREALM
id $ADUSER
echo " SU - Testing"
su - $ADUSER@$DOMAINREALM pwd
su - $ADUSER pwd
echo "SSH Test (please provide your AD users password)"
ssh $ADUSER@localhost who

echo "DONE"

