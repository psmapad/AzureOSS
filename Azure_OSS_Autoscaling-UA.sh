#!/bin/bash
## File to deploy VMSS OSS with Azure CLI 2.0 - Unattended
## Azure CLI 2.0
## Tested on Azure
## Developer: Manuel Alejandro Peña Sánchez
## VM Scale Service

AZCSUFF=$3
AZZONE=$2
AZVMUser=$4
AZVMPass=$5
AZDNSN=$6
AZSKUAS="Standard_A1_v2"
AZSKUJB="Standard_A1_v2"

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
        echo "Creating Resource Group"
        az group create --location $AZZONE --name "$AZCSUFF"RGAUTOSC >> /dev/null
        f_news "Resource Group Created" "Resource Group Failed"

        echo "Creating Public IP"
        az network public-ip create --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"PIPAUTOSC --dns-name $AZDNSN >> /dev/null
        f_news "Public IP Created" "Public IP Failed"
        az network public-ip create --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"PIPAUTOSCJB --dns-name "$AZDNSN"jb >> /dev/null
        f_news "Public IP Created" "Public IP Failed"

        echo "Creating VNET and VSNET"
        az network vnet create --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"VNETAUTOSC --address-prefix 10.0.0.0/24 --subnet-name "$AZCSUFF"VNETINTAUTOSC --subnet-prefix 10.0.0.0/24 >> /dev/null
        f_news "VNET and VSNET Created" "VNET and VSNET Failed"

        echo "Creating Network Security Group"
        az network nsg create --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"NSGAUTOSC >> /dev/null
        f_news "Network Security Group Created" "Network Security Group Failed"

        echo "Creating NSG - SSH Rule"
        az network nsg rule create --resource-group "$AZCSUFF"RGAUTOSC --nsg-name "$AZCSUFF"NSGAUTOSC --name "$AZCSUFF"SSHAUTOSC --protocol tcp --priority 1000 --destination-port-range 22 --access allow >> /dev/null
        f_news "NSG - SSH Rule Created" "NSG - SSH Rule Failed"

        echo "Creating NSG - Web (80 TCP) Rule"
        az network nsg rule create --resource-group "$AZCSUFF"RGAUTOSC --nsg-name "$AZCSUFF"NSGAUTOSC --name "$AZCSUFF"WEBAUTOSC --protocol tcp --priority 1001 --destination-port-range 80 --access allow >> /dev/null
        f_news "NSG - Web (80 TCP) Rule Created" "NSG - Web (80 TCP) Rule Failed"

        echo "Creating Load Balancer"
        az network lb create --resource-group "$AZCSUFF"RGAUTOSC  --name "$AZCSUFF"LBAUTOSC --public-ip-address "$AZCSUFF"PIPAUTOSC --frontend-ip-name "$AZCSUFF"FIPAUTOSC --backend-pool-name "$AZCSUFF"BIPAUTOSC >> /dev/null
        f_news "Load Balancer Created" "Load Balancer Failed"

        echo "Creating Load Balancer Probe"
        az network lb probe create --resource-group "$AZCSUFF"RGAUTOSC  --lb-name "$AZCSUFF"LBAUTOSC --name "$AZCSUFF"LBHPAUTOSC --protocol tcp --port 80 >> /dev/null
        f_news "Load Balancer Probe Created" "Load Balancer Probe Failed"

        echo "Creating Load Balancer Rule"
        az network lb rule create --resource-group "$AZCSUFF"RGAUTOSC  --lb-name "$AZCSUFF"LBAUTOSC --name "$AZCSUFF"LBRWEBAUTOSC --protocol tcp --frontend-port 80 --backend-port 80 --frontend-ip-name "$AZCSUFF"FIPAUTOSC --backend-pool-name "$AZCSUFF"BIPAUTOSC --probe-name "$AZCSUFF"LBHPAUTOSC >> /dev/null
        f_news "Load Balancer Rule Created" "Load Balancer Rule Failed"

        echo "Creating Storage Account"
        az storage account create --resource-group "$AZCSUFF"RGAUTOSC --name $(echo $AZCSUFF |awk '{ print tolower($0) }')saautosc  --sku Standard_LRS
        f_news "Storage Account Created" "Storage Account failed"
        current_env_conn_string=$(az storage account show-connection-string -n $(echo $AZCSUFF |awk '{ print tolower($0) }')saautosc -g "$AZCSUFF"RGAUTOSC --query 'connectionString' -o tsv)

        echo "Creating Azure File"
        az storage share create --name $(echo $AZCSUFF |awk '{ print tolower($0) }')afautosc --quota 32 --connection-string $current_env_conn_string
        f_news "Azure File Created" "Azure File failed"
        AZSAUSER=$(echo $(echo $AZCSUFF |awk '{ print tolower($0) }')saautosc)
        AZSAKEY=$(az storage account keys list --resource-group "$AZCSUFF"RGAUTOSC --account-name $AZSAUSER --query "[0].value" | tr -d '"')
        f_news "Storage Account Key Stored" "Storage Account Key failed"

        echo "Creating Base Image"
        AZIPVMB=$(az vm create --resource-group "$AZCSUFF"RGAUTOSC --nsg "$AZCSUFF"NSGAUTOSC --vnet-name "$AZCSUFF"VNETAUTOSC --subnet "$AZCSUFF"VNETINTAUTOSC --name "$AZCSUFF"VAUTOSCBASE --location $AZZONE --size $AZSKUAS --image OpenLogic:CentOS:7.6:7.6.20190402 --admin-username $AZVMUser --admin-password "$AZVMPass" |grep publicIpAddress |awk -F\" '{print $4}')
        f_news "Base Image Created" "Base Image failed"
        echo "Access to $AZIPVMB IP with SSH with $AZVMUser through SSH with $AZVMPass"
        echo "Testing Services:"
        echo "- Please test your ssh login"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=5 $AZVMUser@$AZIPVMB "id"

        if [ "$?" -eq 0 ]
        then
            CONTINUE="y"
            sleep 30
        else
            exit 2
        fi
        echo "- Configuring Webserver on $AZIPVMB"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S yum install -y apache2 php cifs-utils"
        if [ "$?" -eq 0 ]
        then
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S mkdir -p /var/www/html"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'mkdir /etc/smbcredentials'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo username=$(echo $AZSAUSER) >> /etc/smbcredentials/$(echo $AZSAUSER).cred'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo password=$(echo $AZSAKEY) >> /etc/smbcredentials/$(echo $AZSAUSER).cred'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'chmod 600 /etc/smbcredentials/$(echo $AZSAUSER).cred'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"//$(echo $AZSAUSER).file.core.windows.net/$(echo $AZCSUFF |awk '{ print tolower($0) }')afautosc /var/www/html cifs nofail,vers=3.0,credentials=/etc/smbcredentials/$(echo $AZSAUSER).cred,dir_mode=0777,file_mode=0777,serverino\" >> /etc/fstab'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S mount /var/www/html"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S touch /var/www/html/index.php"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "ls -lF /var/www/html/"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '<?php echo gethostbyname(trim(\`hostname\`)); ?>' > ~/tmp.txt"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '<h3> Version 1 </h3>' >> ~/tmp.txt"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S mv /home/$AZVMUser/tmp.txt /var/www/html/index.php"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S rm -f /var/www/html/index.h* /etc/httpd/conf.d/welcome.conf"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'setenforce 0'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'systemctl enable httpd'"
            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'systemctl start httpd'"

            sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo y |waagent -deprovision'"
        else
            exit 2
        fi

        echo "Done configuring Webserver Main Page"
        if [ $CONTINUE == "y" ]
        then
            echo "Deallocating VM Base Image"
            az vm deallocate --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"VAUTOSCBASE >> /dev/null
            f_news "VM Base Image Deallocated" "VM Base Image Deallocate Failed"

            echo "VM Base Image Generalize"
            az vm generalize --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"VAUTOSCBASE >> /dev/null
            f_news "Resource Group Created" "Resource Group Failed"

            echo "Creating Base Image"
            az image create --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"VAUTOSCIMG --source "$AZCSUFF"VAUTOSCBASE >> /dev/null
            f_news "Base Image Created" "Base Image Failed"
            echo "Creating VM Scale Service"
            az vmss create --upgrade-policy-mode Automatic --lb "$AZCSUFF"LBAUTOSC --location $AZZONE --public-ip-address "$AZCSUFF"PIPAUTOSC --nsg "$AZCSUFF"NSGAUTOSC --vnet-name "$AZCSUFF"VNETAUTOSC --subnet "$AZCSUFF"VNETINTAUTOSC --resource-group "$AZCSUFF"RGAUTOSC --name "$AZCSUFF"SSAUTOSC --image "$AZCSUFF"VAUTOSCIMG --vm-sku $AZSKUAS --admin-username $AZVMUser --admin-password "$AZVMPass" >> /dev/null
            echo "az vmss extension set --extension-instance-name AUTOSC --publisher Microsoft.Azure.Extensions --version 2.0 --name CustomScript --resource-group "$AZCSUFF"RGAUTOSC --vmss-name "$AZCSUFF"SSAUTOSC --settings '{ \"commandToExecute\": \"setenforce 0\" }'" | bash
            f_news "VM Scale Service Created" "VM Scale Service Failed"
        else
            echo "Nothing To Do, Please finish to custom your VM image and run the following Azure CLI 2.0 commands:"
            echo "az vm deallocate --resource-group $(echo $AZCSUFF)RGAUTOSC --name $(echo $AZCSUFF)VAUTOSCBASE"
            echo "az vm generalize --resource-group $(echo $AZCSUFF)RGAUTOSC --name $(echo $AZCSUFF)VAUTOSCBASE"
            echo "az image create --resource-group $(echo $AZCSUFF)RGAUTOSC --name $(echo $AZCSUFF)VAUTOSCIMG --source $(echo $AZCSUFF)VAUTOSCBASE"
            echo "az vmss create --upgrade-policy-mode Automatic --lb $(echo $AZCSUFF)LBAUTOSC --location $AZZONE --public-ip-address $(echo $AZCSUFF)PIPAUTOSC --nsg $(echo $AZCSUFF)NSGAUTOSC --vnet-name $(echo $AZCSUFF)VNETAUTOSC --subnet $(echo $AZCSUFF)VNETINTAUTOSC --resource-group $(echo $AZCSUFF)RGAUTOSC --name $(echo $AZCSUFF)SSAUTOSC --image $(echo $AZCSUFF)VAUTOSCIMG --vm-sku $AZSKUAS --admin-username $AZVMUser --admin-password '$AZVMPass'"
        fi

        echo "Creating Jump Box"
        AZIPVMJB=$(az vm create --resource-group $(echo $AZCSUFF)RGAUTOSC --nsg $(echo $AZCSUFF)NSGAUTOSC --vnet-name $(echo $AZCSUFF)VNETAUTOSC --subnet $(echo $AZCSUFF)VNETINTAUTOSC --name $(echo $AZCSUFF)VAUTOSCJP --public-ip-address $(echo $AZCSUFF)PIPAUTOSCJB --location $AZZONE --size $AZSKUJB --image $(echo $AZCSUFF)VAUTOSCIMG --admin-username $AZVMUser --admin-password "$AZVMPass" |grep publicIpAddress |awk -F\" '{print $4}')
        f_news "Jump Box Created" "Jump Box Failed"
        echo "JumpBox Access to $AZIPVMJB IP with SSH with $AZVMUser through SSH with $AZVMPass"
        echo "Or $(echo $AZDNSN)jb.$AZZONE.cloudapp.azure.com"
        echo "WebPage is on http://$AZDNSN.$AZZONE.cloudapp.azure.com/"
        ;;

    remove)
        az group delete -y --name "$2"RGAUTOSC >> /dev/null
        f_news "Resource Group deleted" "Resource Group delete Failed"
        ;;

    *)
        echo "Usage: $0 {deploy AZUREZONE COMPANYSUFFIX VMUSER VMPASS DNSNAME | remove COMPANYSUFFIX}"
        exit 2
        ;;
esac


