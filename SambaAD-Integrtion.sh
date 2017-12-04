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
DNS1="IPDNSServer"
DNS2="IPDNSServer"
SEARCH="PREFIX DOMAIN SEARCH"

DOMAIN=$(echo $DOMAINREALM |cut -d. -f1)
SHRNAME="TestSHR"
SHRCOMM="TestSHR"
SHRCOMM="/tmp"

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

echo "Install SSSD REALM NTPDATE"
yum -y update > /dev/null
f_news "System Updated" "System Update Failed"
yum -y install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano > /dev/null
f_news "SSSD Service Installed" "SSSD Service Install Failed"

echo "Install Samba"
yum -y install krb5-user samba smbfs samba-client > /dev/null
f_news "Samba Service Installed" "Samba Service Install Failed"

echo "Configure ntpserver"
sed -i 's/^server/#server/g' /etc/ntp.conf
echo server $NTPS >> /etc/ntp.conf
systemctl restart ntpd  > /dev/null
f_news "NTP Service configured" "NTP Service configure failed"

echo "Change Secure Settings"
echo "SELINUX to Permissive"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
setenforce 0 > /dev/null
f_news "SELinux Service configured" "SELinux Service configure Failed"

echo "Setting UP Networking INFO for Active Directory Join"
sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
systemctl restart network > /dev/null
f_news "Network Service configured" "Network Service configure Failed"

echo "DOMAIN TESTING"
if ping -c3 $DOMAINREALM
then
    realm discover $DOMAINREALM > /dev/null
    f_news "Domain Discovery - OK" "Domain Discovery - Failed"
else
    echo "Domain not reacheable"
fi
echo "Domain Join"
kinit $ADUSER@$DOMAINREALM
f_news "Kerberos configure - OK" "Kerberos configure - Failed"
realm join --verbose $DOMAINREALM -U $ADUSER@$DOMAINREALM
f_news "Domain Join - OK" "Domain Join - Failed"

SSDCNF='y'
echo -n "¿Change SSSD Configuration?(y/n): "
read SSDCNF

if [ "$SSDCNF" == "y" ]
then
    sed -i 's/^default_shell.*/default_shell=\/bin\/bash/g' /etc/sssd/sssd.conf
    f_news "SSSD Configure - OK" "SSSD Configure - Failed"
    sed -i 's/^use_fully_qualified_names.*/use_fully_qualified_names=False/g' /etc/sssd/sssd.conf
    f_news "SSSD Configure - OK" "SSSD Configure - Failed"
    sed -i 's/^fallback_homedir.*/fallback_homedir=\/home\/\%u/g' /etc/sssd/sssd.conf
    f_news "SSSD Configure - OK" "SSSD Configure - Failed"
    sed -i 's/^override_homedir.*/override_homedir=\/home\/\%u/g' /etc/sssd/sssd.conf
    f_news "SSSD Configure - OK" "SSSD Configure - Failed"
else
    echo "Not Overriding SSSD conf"
fi
systemctl restart sssd realmd > /dev/null
f_news "SSSD restart - OK" "SSSD restart - Failed"
echo "Domain Integration Testing"
echo " ID Testing"
id $ADUSER@$DOMAINREALM
if [ "$SSDCNF" == "y" ]
then
    id $ADUSER
fi
echo " SU - Testing"
su - $ADUSER@$DOMAINREALM -c pwd
if [ "$SSDCNF" == "y" ]
then
    su - $ADUSER -c pwd
fi
echo "SSH Test (please provide your AD users password)"
if [ "$SSDCNF" == "y" ]
then
    ssh $ADUSER@localhost who
else
eval    ssh -l '$DOMAIN\$ADUSER' localhost who
fi
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
f_news "Samba Share Configured Correctly" "Samba Share Configure Failed"
systemctl restart smb nmb > /dev/null
f_news "Samba Share restart Correctly" "Samba Share restart Failed"

echo "DONE"
