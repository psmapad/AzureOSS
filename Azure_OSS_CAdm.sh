#!/bin/bash
## Script to deploy Ansible on Azure
## Centos 7.5
## Tested on Azure
## Developer: Manuel Alejandro Peña Sánchez
## Ansible on Azure

PREF=$2
LOC=$3
AUSER=$4
APASS=$5
VMSIZE=Standard_A2_v2
FLAVOR=CentOS

f_tit(){
    TIT=$1
    echo "Creacion de $1"
}

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
    deploy)
        f_tit "Resource Group"
        az group create -n $(echo $PREF)RGBCENTRAL -l $LOC
        f_tit "Virtual Network"
        az network vnet create --resource-group $(echo $PREF)RGBCENTRAL --name $(echo $PREF)VNETBCENTRAL --address-prefix 172.16.10.0/24 --subnet-name $(echo $PREF)VSNETBCENTRAL --subnet-prefix 172.16.10.0/24
        f_tit "Public IP"
        az network public-ip create --resource-group $(echo $PREF)RGBCENTRAL --name $(echo $PREF)PIPBCENTRAL --dns-name $(echo $PREF |awk '{ print tolower($0) }')pipbcentral
        f_tit "Network Security Group"
        az network nsg create --resource-group $(echo $PREF)RGBCENTRAL --name $(echo $PREF)NSGBCENTRAL
        f_tit "NSG - SSH Allow"
        az network nsg rule create --resource-group $(echo $PREF)RGBCENTRAL --nsg-name $(echo $PREF)NSGBCENTRAL --name $(echo $PREF)NSGBCENTRALSSH --protocol tcp --priority 1000 --destination-port-range 22 --access allow
        f_tit "Network Interface"
        az network nic create --resource-group $(echo $PREF)RGBCENTRAL --name $(echo $PREF)NICBCENTRAL --vnet-name $(echo $PREF)VNETBCENTRAL --subnet $(echo $PREF)VSNETBCENTRAL --public-ip-address $(echo $PREF)PIPBCENTRAL --network-security-group $(echo $PREF)NSGBCENTRAL
        f_tit "Ansible Virtual Machine"
        az vm create --resource-group $(echo $PREF)RGBCENTRAL --nics  $(echo $PREF)NICBCENTRAL --name $(echo $PREF)VMBCENTRAL --os-disk-name $(echo $PREF)VHDBCENTRAL --admin-username $AUSER --admin-password $APASS --image $FLAVOR --size $VMSIZE
        f_tit "Ansible Configuration"

        sshpass -p $APASS ssh -o ConnectTimeout=2 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "hostname"
        sleep 30
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S yum -y update"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S yum check-update; sudo yum install -y gcc libffi-devel python-devel openssl-devel epel-release"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S yum install -y python-pip python-wheel"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S rpm --import https://packages.microsoft.com/keys/microsoft.asc"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S touch /etc/yum.repos.d/azure-cli.repo"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'echo -e \"[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc$(hostname)\"> /etc/yum.repos.d/azure-cli.repo'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S yum -y install azure-cli"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S pip install ansible[azure]"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'mkdir ~/.azure'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'echo -e \"[default]\nad_user=AzureUser@onmicrosoft.com\npassword=ComplexPassWord\n\"> ~/.azure/credentials'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'echo -e \"export AZURE_AD_USER=AzureUser@onmicrosoft.com\nexport AZURE_PASSWORD=ComplexPassWord\n\">> ~/.bash_profile'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'echo -e \"---\n- hosts: localhost\n  connection: local\n  tasks:\n    - name: Create resource group\n      azure_rm_resourcegroup:\n        name: BSRGBCENTTEST\n        location: westus\n      register: rg\n    - debug:\n        var: rg\n\" > ~/rg.yml'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'wget https://raw.githubusercontent.com/ansible/ansible/devel/contrib/inventory/azure_rm.py -O ~/azure_rm.py'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'wget https://raw.githubusercontent.com/psmapad/AzureOSS/master/vm.yml -O ~/vm.yml'"
        sshpass -p $APASS ssh -o ConnectTimeout=3 $AUSER@$(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com "echo '$APASS' |sudo -S sh -c 'chmod +x ~/azure_rm.py'"

        #az login --username
        #ansible-playbook vm.yml
        #az resource tag --tags ANSIBLE --name BSVMBCENTTEST -g BSRGBCENTTEST --resource-type Microsoft.Compute/virtualMachines
        echo "Ansible access to $(echo $PREF |awk '{ print tolower($0) }')pipbcentral.$(echo $LOC).cloudapp.azure.com with $AUSER through SSH with $APASS"

        ;;

    remove)
        az group delete -y --name "$PREF"RGBCENTRAL >> /dev/null
        f_news "Resource Group deleted" "Resource Group delete Failed"
        ;;

    *)
        echo "Usage: $0 {deploy COMPANYPREFIX AZURELOCATION VMUSER VMPASS | remove COMPANYPREFIX}"
        exit 2
esac
