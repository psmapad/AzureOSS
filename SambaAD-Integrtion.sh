#!/bin/bash
## File to deploy Domain Controler Integration with Samba for File Sharing
## Centos 7.3
## Tested on Azure 
## Developer: Manuel Alejandro Peña Sánchez
## AD Integration with sssd and Samba
## Use ./SambaAD-Integration.sh DOMAINREALM "Domain User" "NTP IP Server"
DOMAINREALM=$1
ADUSER=$2
NTPS=$3

DOMAIN=$(echo $DOMAINREALM |cut -d. -f1)
SHRNAME="TestSHR"
SHRCOMM="TestSHR"
SHRCOMM="/tmp"

echo "Install SSSD REALM NTPDATE"
yum -y update
yum -y install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano

echo "Install Samba"
yum -y install krb5-user samba smbfs samba-client

echo "Configure ntpserver"
sed -i 's/^server/#server/g' /etc/ntp.conf
echo server $NTPS >> /etc/ntp.conf
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
echo -n "¿Change SSSD Configuration?(y/n): "
SSDCNF="y"
read SSDCNF
if [ '$SSDCNF' == 'y' ]
then
    sed -i 's/^default_shell.*/default_shell=\/bin\/bash/g' /etc/sssd/sssd.conf
    sed -i 's/^use_fully_qualified_names.*/use_fully_qualified_names=True/g' /etc/sssd/sssd.conf
    sed -i 's/^fallback_homedir.*/fallback_homedir=\/home\/\%u\/g' /etc/sssd/sssd.conf
    sed -i 's/^override_homedir.*/override_homedir=\/home\/\%u\/g' /etc/sssd/sssd.conf
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

echo "Configuring Samba"
mv /etc/samba/smb.conf /etc/samba/smb.conf.old
> /etc/samba/smb.conf

SMBCNF="n"
echo -n "¿Do you want to confiure a Share? (y/n): "
read SMBCNF
echo $SMBCNF

if [ $SMBCNF == "y" ]
then
    echo -n "¿Give the name of the Share? (Default: TestSHR): "
    read SHRNAME
    echo -n "¿Give the Description of the Share? (Default: TestSHR): "
    read SHRCOMM
    echo -n "¿Give the path of the Share? (Default: /tmp): "
    read SHRPATH

    echo "# See smb.conf.example for a more detailed config file or
    # Run 'testparm' to verify the config is correct after
    # you modified it.
    [global]
    workgroup = $DOMAIN
    security = ads
    client signing = yes
    client use spnego = yes
    kerberos method = secrets and keytab
    realm = $DOMAINREALM
    domain master = no
    local master = no
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $DOMAIN:backend = ad
    idmap config $DOMAIN:schema_mode = rfc2307
    idmap config $DOMAIN:range = 10000-999999
    template homedir = /home/\%U
    template shell = /bin/false
    # client ntlmv2 auth = yes
    encrypt passwords = yes
    restrict anonymous = 2
    printcap name = /etc/printcap
    load printers = no
    log file = /var/log/samba/samba.log
    log level = 3

    [$SHRNAME]
    comment = $SHRCOMM
    path = $SHRPATH
    force group = \"domain users\"
    browseable = Yes
    writable = yes
    read only = no
    public = yes
    force create mode = 0660
    create mask = 0777
    directory mask = 0777
    force directory mode = 0770
    access based share enum = yes
    hide unreadable = no
    valid users = @\"domain users\"
    write list = @\"domain users\"
    inherit permissions = yes
    inherit acls = yes" > /etc/samba/smb.conf

else
    echo "Taking Default Valuess for SHARE"
    echo "
    # See smb.conf.example for a more detailed config file or
    # read the smb.conf manpage.
    # Run 'testparm' to verify the config is correct after
    # you modified it.
    [global]
    workgroup = $DOMAIN
    security = ads
    client signing = yes
    client use spnego = yes
    kerberos method = secrets and keytab
    realm = $DOMAINREALM
    domain master = no
    local master = no
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $DOMAIN:backend = ad
    idmap config $DOMAIN:schema_mode = rfc2307
    idmap config $DOMAIN:range = 10000-999999
    template homedir = /home/\%U
    template shell = /bin/false
    # client ntlmv2 auth = yes
    encrypt passwords = yes
    restrict anonymous = 2
    printcap name = /etc/printcap
    load printers = no
    log file = /var/log/samba/samba.log
    log level = 3

    [$SHRNAME]
    comment = $SHRCOMM
    path = $SHRPATH
    force group = \"domain users\"
    browseable = Yes
    writable = yes
    read only = no
    public = yes
    force create mode = 0660
    create mask = 0777
    directory mask = 0777
    force directory mode = 0770
    access based share enum = yes
    hide unreadable = no
    valid users = @\"domain users\"
    write list = @\"domain users\"
    inherit permissions = yes
    inherit acls = yes" > /etc/samba/smb.conf
fi

echo "DONE"
