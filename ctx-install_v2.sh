#!/bin/bash
## File tu deploy Citrix VDA
## Centos 7.3
## Tested on Azure 
## Developer: Manuel Alejandro Peña Sánchez
## AD Integration with sssd
## This Script solves the issue between NFS Server with REALM SSSD AD Integration and XenDesktop Winbind AD Integration. 
## Download XenDesktopVDA.rpm and Nvidia installer to /usr/local/src
## It's recomended, but not necesary, to reboot after deploy
## Don't forget to set up proxy if you need it.

# CTX ENV
export CTX_XDL_DDC_LIST='CTX Console Server'
export CTX_XDL_SUPPORT_DDC_AS_CNAME='n'
export CTX_XDL_VDA_PORT='80'
export CTX_XDL_REGISTER_SERVICE='y'
export CTX_XDL_ADD_FIREWALL_RULES='y'
export CTX_XDL_AD_INTEGRATION='4'
export CTX_XDL_HDX_3D_PRO='y'
export CTX_XDL_SITE_NAME='<none>'
export CTX_XDL_LDAP_LIST='<none>'
export CTX_XDL_SEARCH_BASE='<none>'
export CTX_XDL_START_SERVICE='y'

# DA ENV
DNS1="IP DNS1"
DNS2="IP DNS2"
NTP="NTP IP"
SEARCH="search prefix"
REALM="REALM DOMAIN"
DAUSR="DOMAIN USER"

# ¿NEED PROXY? 
echo "Proxy Configuration"
#echo "proxy=http://IP:PORT/" >> /etc/yum.conf
#echo "proxy_username=USERNAME" >> /etc/yum.conf
#echo "proxy_password=PASSWORD" >> /etc/yum.conf
#echo "http_proxy = http://USER:PASS@IP:PORT/" >> /etc/wgetrc
#echo "https_proxy = http://USER:PASS@IP:PORT/" >> /etc/wgetrc
#echo "ftp_proxy = http://USER:PASS@IP:PORT/" >> /etc/wgetrc

echo "Setting up CentOS 7.3.1611 Repo"

cat << EOF >>  /etc/yum.repos.d/vault73.repo
[C7.3.1611-base]
name=CentOS-7.3.1611 - Base
#baseurl=http://vault.centos.org/7.3.1611/os/\$basearch/
baseurl=http://olcentgbl.trafficmanager.net/centos/7.3.1611/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=0

[C7.3.1611-updates]
name=CentOS-7.3.1611 - Updates
#baseurl=http://vault.centos.org/7.3.1611/updates/\$basearch/
baseurl=http://olcentgbl.trafficmanager.net/centos/7.3.1611/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

EOF

echo "Disabling CentOS Updates"

yum-config-manager --disable "CentOS-7 -*"
yum-config-manager --disable "CentOS-7 - Updates"
yum-config-manager --disable "CentOS-7 - Base"

echo "Installing Desktop and Development Tools"
yum -y --disablerepo=\* --enablerepo=C7.3.1611-base,C7.3.1611-updates groupinstall Base 'GNOME Desktop' 'Development Tools'
echo "Installing XenDesktop Prerequisites"
yum -y --disablerepo=\* --enablerepo=C7.3.1611-base,C7.3.1611-updates install java-1.8.0-openjdk postgresql-server postgresql-jdbc
echo "Installing Active Directory Integration Packages"
yum -y --disablerepo=\* --enablerepo=C7.3.1611-base,C7.3.1611-updates install sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate samba-common ntp authconfig
echo "Installing XenDesktop - Version 7.15-1000"
yum -y --disablerepo=\* --enablerepo=C7.3.1611-base,C7.3.1611-updates localinstall /usr/local/src/XenDesktopVDA-7.15.1000.11-1.el7_3.x86_64.rpm

echo "Disable NOUVEAU Driver"
cat <<EOF >> /etc/modprobe.d/nouveau.conf
blacklist nouveau
blacklist lbm-nouveau
EOF
rmmod nouveau
 
echo "Change Secure Settings"
echo "SELINUX to disabled"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
setenforce 0

echo "Disable Initial-Setup-Graphical"
systemctl stop initial-setup-graphical.service
systemctl disable initial-setup-graphical.service

echo "Setting UP NTP Server"
timedatectl set-timezone America/Mexico_City
sed -i 's/^server [0-9]./#server 0./g' /etc/ntp.conf
echo "server $NTP" >> /etc/ntp.conf
systemctl start ntpd.service

echo "PostgreSQL InitDB"
postgresql-setup initdb
systemctl enable postgresql.service
systemctl start postgresql.service

echo "Networking Configuration"
echo "Setting UP Networking INFO for Active Directory Join"
sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/selinux
echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
systemctl restart network

echo "Disable Gnome Autostart" 
echo "X-GNOME-Autostart-enabled=false" >> /etc/xdg/autostart/gnome-software-service.desktop

echo "Setting up NVIDIA Drivers"
chmod +x /usr/local/src/NVIDIA-Linux-x86_64-grid.run
/usr/local/src/NVIDIA-Linux-x86_64-grid.run -a -s -Z
nvidia-xconfig
echo "Change Citrix Nvidia Script(ctx-nvidia.sh)"
VAL=$(nvidia-xconfig --query-gpu-info |grep BusID |awk '{print $4}')
sed -i "s/VendorName     \"NVIDIA Corporation\"/VendorName     \"NVIDIA Corporation\"\n    BusID          \"$VAL\"/g" /etc/X11/xorg.conf
sed -i 's/PCI:/PCI:0@/g' /etc/X11/ctx-nvidia.sh
echo "sed -i -r \"s/BusID.*/BusID \\\"PCI:0@\$busid\\\"/\" /etc/X11/xorg.conf" >> /etc/X11/ctx-nvidia.sh

echo "Active Directory Integration"
echo "$(ifconfig eth0 |grep -m1 inet |awk '{print $2}')   $(hostname).$SEARCH $(hostname)" >> /etc/hosts

echo "1. Setting up Authconfig"

authconfig --smbsecurity=ads --smbworkgroup= $(echo $REALM |awk '{print tolower($0)}') --smbrealm=$SEARCH --krb5realm=$SEARCH --krb5kdc=$(hostname).$SEARCH --enablekrb5kdcdns --enablekrb5realmdns --update

echo "2. Setting up Samba"

cp /etc/samba/smb.conf /etc/samba/smb.conf.old
> /etc/samba/smb.conf

cat << EOF >> /etc/samba/smb.conf

# See smb.conf.example for a more detailed config file or
# read the smb.conf manpage.
# Run 'testparm' to verify the config is correct after
# you modified it.

[global]
#--authconfig--start-line--

# Generated by authconfig on 2018/04/15 22:20:29
# DO NOT EDIT THIS SECTION (delimited by --start-line--/--end-line--)
# Any modification may be deleted or altered by authconfig in future

   workgroup = $(echo $REALM |awk '{print tolower($0)}')
   realm = $(echo $SEARCH |awk '{print toupper($0)}')
   security = ads
   idmap config * : range = 16777216-33554431
   template shell = /bin/false
   kerberos method = secrets and keytab
   winbind use default domain = false
   winbind offline logon = false

#--authconfig--end-line--
        passdb backend = tdbsam
        printing = cups
        printcap name = cups
        load printers = yes
        cups options = raw

[homes]
        comment = Home Directories
        valid users = %S, %D%w%S
        browseable = No
        read only = No
        inherit acls = Yes

[printers]
        comment = All Printers
        path = /var/tmp
        printable = Yes
        create mask = 0600
        browseable = No

[print\$]
        comment = Printer Drivers
        path = /var/lib/samba/drivers
        write list = root
        create mask = 0664
        directory mask = 0775

EOF

echo "3. Join to Domain $(echo $REALM |awk '{print toupper($0)}')"
net ads join $(echo $REALM |awk '{print toupper($0)}') -U $DAUSR 
# net ads join $(echo $REALM |awk '{print toupper($0)}') -U $DAUSR createcomputer="OU/OU/Servers"

echo "4. Setting UP SSSD"

cp /etc/sssd/sssd.conf /etc/sssd/sssd.conf.old
> /etc/sssd/sssd.conf
cat << EOF >> /etc/sssd/sssd.conf

[sssd]
config_file_version = 2
domains = $(echo $SEARCH |awk '{print tolower($0)}')
services = nss, pam

[domain/$(echo $SEARCH |awk '{print tolower($0)}')]
cache_credentials = true
id_provider = ad
auth_provider = ad
access_provider = ad
ldap_id_mapping = true
ldap_schema = ad
ad_domain = $(echo $SEARCH |awk '{print tolower($0)}')
krb5_ccachedir = /tmp
krb5_ccname_template = FILE:%d/krb5cc_%U
ad_server = $(echo $SEARCH |awk '{print tolower($0)}')
default_shell = /bin/bash
override_homedir = /home/%u
fallback_homedir = /home/%u

EOF

echo "5. Setting UP NFS Client"
cp /etc/idmapd.conf /etc/idmapd.conf.old
> /etc/idmapd.conf

cat << EOF >> /etc/idmapd.conf
[General]
Domain = pemex.pmx.com
[Mapping]
Nobody-User = nobody
Nobody-Group = nobody
[Translation]
Method = nsswitch

EOF

echo "6. Enable SSSD"
authconfig --enablesssd --enablesssdauth --enablemkhomedir --update
systemctl restart sssd 
systemctl enable sssd 
echo "7. Domain KINIT"
kinit -k $(hostname)\$@$(echo $REALM |awk '{print toupper($0)}')]

echo "8. Testing Domain Integration"
getent passwd $ADUSR
getent group "domain users"

su - $ADUSR -c pwd

echo "XenDesktop VDA Setup" 
/opt/Citrix/VDA/sbin/ctxsetup.sh