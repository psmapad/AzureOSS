#!/bin/bash
## File tu deploy Citrix VDA
## Centos 7.3
## Tested on Azure 
## Developer: Manuel Alejandro Peña Sánchez
## AD Integration with sssd
## Download XenDesktopVDA.rpm to /usr/local/src
## It's recomended, but not necesary, to reboot after deploy

DNS1="IPDNS1"
DNS2="IPDNS2"
SEARCH="prefix domain search"
DCSRV="dc domain"

# Citrix ENVS
export CTX_XDL_SUPPORT_DDC_AS_CNAME='n'
export CTX_XDL_DDC_LIST='xa-controller.xenapp.local'
export CTX_XDL_VDA_PORT='80'
export CTX_XDL_REGISTER_SERVICE='y'
export CTX_XDL_ADD_FIREWALL_RULES='y'
export CTX_XDL_AD_INTEGRATION='4'
export CTX_XDL_HDX_3D_PRO='y'
export CTX_XDL_SITE_NAME='<none>'
export CTX_XDL_LDAP_LIST='<none>'
export CTX_XDL_SEARCH_BASE='<none>'
export CTX_XDL_START_SERVICE='y'

cd /usr/local/src
echo "Change Secure Settings"
echo "SELINUX to Permissive"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
setenforce 0
echo "Setting UP Networking INFO for Active Directory Join"
sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/selinux
echo DNS1=$DNS1 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo DNS2=$DNS2 >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo SEARCH=$SEARCH >> /etc/sysconfig/network-scripts/ifcfg-eth0
echo "Deploy Dependencies"
echo "Kernel Development"
yum -y --releasever 7.3.1611 install kernel-headers kernel-devel
ln -s /usr/src/kernels/3.10.0-514.26.2.el7.x86_64 /usr/src/linux
echo "Fedora EPEL"
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
echo "DEV TOOLS"
yum -y --releasever 7.3.1611 install autoconf automake libtool gcc cpp make
echo "Desktop"
yum -y --releasever 7.3.1611 groupinstall "Gnome Desktop"
echo "XENAPP VDA DEPENDENCIES"
yum -y --releasever 7.3.1611 install postgresql-server postgresql-jdbc java-1.8.0-openjdk ImageMagick policycoreutils-python dbus-x11 xorg-x11-server-utils xorg-x11-xinit libXpm libXrandr libXtst motif cups foomatic-filters cyrus-sasl cyrus-sasl-gssapi
yum -y --releasever 7.3.1611 install realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools ntp krb5-user samba smbfs samba-client sssd-winbind-idmap ntpdate nano
echo "Excluding Packages (Citrix Support Stuff)"
echo exclude=kernel* xorg* centos-release* >> /etc/yum.conf
echo "LIGHTDM"
yum -y install lightdm
echo "DKMS"
yum -y install dkms
echo "XenDesktop VDA RPM Install"
yum -y install XenDesktopVDA-7.12.0.375-1.el7_2.x86_64.rpm
echo "Change Citrix Nvidia Script(ctx-nvidia.sh)"
sed -i 's/PCI:/PCI:0@/g' /etc/X11/ctx-nvidia.sh
echo "Disable NOUVEAU Driver"
cat <<EOF >> /etc/modprobe.d/nouveau.conf
blacklist nouveau
blacklist lbm-nouveau
EOF
rmmod nouveau
echo "NVIDIA SETUP (Version 384.81)"
cd /usr/local/src
wget http://us.download.nvidia.com/tesla/384.81/NVIDIA-Linux-x86_64-384.81.run
chmod +x NVIDIA-Linux-x86_64-384.81.run
./NVIDIA-Linux-x86_64-384.81.run -a -s -Z
nvidia-xconfig
echo "IgnoreSP=TRUE" >> /etc/nvidia/gridd.conf
echo "Setting Up BusID"
VAL=$(nvidia-xconfig --query-gpu-info |grep BusID |awk '{print $4}')
sed "s/VendorName     \"NVIDIA Corporation\"/VendorName     \"NVIDIA Corporation\"\n    BusID          \"$VAL\"/g" /etc/X11/xorg.conf
echo "Upgrading System"
yum -y update
systemctl restart network
echo "Citrix XenAPP VDA Install"
/opt/Citrix/VDA/sbin/ctxinstall.sh
