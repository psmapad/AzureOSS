#!/bin/bash
## File to deploy HPC OSS with Azure CLI 2.0
## Azure CLI 2.0
## Tested on Azure
## Developer: Manuel Alejandro Peña Sánchez
## VM HPC Infiniband

AZCSUFF=$3
AZZONE=$2
AZVMUser=$4
AZVMPass=$5
AZDNSN="$(echo $AZCSUFF |awk '{ print tolower($0) }')piphpc"
AZImage="OpenLogic:CentOS-HPC:7.4:7.4.20180719"
AZSKUAS="Standard_A9"
AZFHPC="$(echo $AZCSUFF |awk '{ print tolower($0) }')afhpc"
AZSAKEY=""

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
        az group create --location $AZZONE --name "$AZCSUFF"RGHPC
        f_news "Resource Group Created" "Resource Group Failed"

        echo "Creating Public IP"
        az network public-ip create --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"PIPHPC --dns-name $AZDNSN
        f_news "Public IP Created" "Public IP Failed"

        echo "Creating VNET and VSNET"
        az network vnet create --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"VNETHPC --address-prefix 10.0.0.0/24 --subnet-name "$AZCSUFF"VNETINTHPC --subnet-prefix 10.0.0.0/24
        f_news "VNET and VSNET Created" "VNET and VSNET Failed"

        echo "Creating Network Security Group"
        az network nsg create --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"NSGHPC
        f_news "Network Security Group Created" "Network Security Group Failed"

        echo "Creating NSG - SSH Rule"
        az network nsg rule create --resource-group "$AZCSUFF"RGHPC --nsg-name "$AZCSUFF"NSGHPC --name "$AZCSUFF"SSHHPC --protocol tcp --priority 1000 --destination-port-range 22 --access allow
        f_news "NSG - SSH Rule Created" "NSG - SSH Rule Failed"

        echo "Creating AVS"
        az vm availability-set create --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"AVSHPC

        echo "Creating Storage Account"
        az storage account create --resource-group "$AZCSUFF"RGHPC --name $(echo $AZCSUFF |awk '{ print tolower($0) }')sahpc  --sku Standard_LRS
        f_news "Storage Account Created" "Storage Account failed"
        current_env_conn_string=$(az storage account show-connection-string -n $(echo $AZCSUFF |awk '{ print tolower($0) }')sahpc -g "$AZCSUFF"RGHPC --query 'connectionString' -o tsv)

        echo "Creating Azure File"
        az storage share create --name $AZFHPC --quota 2048 --connection-string $current_env_conn_string
        f_news "Azure File Created" "Azure File failed"

        AZSAUSER=$(echo $(echo $AZCSUFF |awk '{ print tolower($0) }')sahpc)
        AZSAKEY=$(az storage account keys list --resource-group "$AZCSUFF"RGHPC --account-name $AZSAUSER --query "[0].value" | tr -d '"')
        f_news "Storage Account Key Stored" "Storage Account Key failed"

        echo "Creating Base Image"
        AZIPVMB=$(az vm create --resource-group "$AZCSUFF"RGHPC --availability-set "$AZCSUFF"AVSHPC --nsg "$AZCSUFF"NSGHPC --vnet-name "$AZCSUFF"VNETHPC --subnet "$AZCSUFF"VNETINTHPC --name "$AZCSUFF"VMHPCBASE --size $AZSKUAS --image $AZImage --admin-username $AZVMUser --admin-password "$AZVMPass" |grep publicIpAddress |awk -F\" '{print $4}')
        f_news "Base Image Created" "Base Image failed"

        sshpass -p $AZVMPass ssh -o ConnectTimeout=5 $AZVMUser@$AZIPVMB "id"
        if [ "$?" -eq 0 ]
        then
            CONTINUE="y"
            sleep 30
        else
            exit 2
        fi

        echo "- Configuring HPC Image on $AZIPVMB"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S yum -y update"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S yum -y install cifs-utils"
        echo "Root Configuration"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo Host * >> ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo StrictHostKeyChecking no >> ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'cat ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c \"echo y | ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''\""
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'chmod 600 ~/.ssh/authorized_keys'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'chmod 400 ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'ssh 0 id'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'mkdir /tmp/DATA'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'mkdir /etc/smbcredentials'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo username=$(echo $AZSAUSER) >> /etc/smbcredentials/$(echo $AZSAUSER).cred'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo password=$(echo $AZSAKEY) >> /etc/smbcredentials/$(echo $AZSAUSER).cred'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'chmod 600 /etc/smbcredentials/$(echo $AZSAUSER).cred'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"//$(echo $AZSAUSER).file.core.windows.net/$(echo $AZFHPC) /tmp/DATA cifs nofail,vers=3.0,credentials=/etc/smbcredentials/$(echo $AZSAUSER).cred,dir_mode=0777,file_mode=0777,serverino\" >> /etc/fstab'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S mount /tmp/DATA"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo source /opt/intel/impi/5.1.3.223/bin64/mpivars.sh >> ~/.bashrc'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"export I_MPI_FABRICS=shm:dapl\" >> ~/.bashrc'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"export I_MPI_DAPL_PROVIDER=ofa-v2-ib0\" >> ~/.bashrc'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"export I_MPI_DYNAMIC_CONNECTION=0\" >> ~/.bashrc'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"mpirun -ppn 1 -n 3 -hosts $(echo $AZCSUFF)VMHPC001,$(echo $AZCSUFF)VMHPC002,$(echo $AZCSUFF)VMHPC003 -env I_MPI_FABRICS=shm:dapl -env I_MPI_DAPL_PROVIDER=ofa-v2-ib0 -env I_MPI_DYNAMIC_CONNECTION=0 hostname\" >> /tmp/DATA/mpi.sh'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo \"mpirun -ppn 2 -n 3 -hosts $(echo $AZCSUFF)VMHPC001,$(echo $AZCSUFF)VMHPC002,$(echo $AZCSUFF)VMHPC003 -env I_MPI_FABRICS=shm:dapl -env I_MPI_DAPL_PROVIDER=ofa-v2-ib0 -env I_MPI_DYNAMIC_CONNECTION=0 IMB-MPI1 pingpong\" >> /tmp/DATA/mpi.sh'"

        echo "User Configuration"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "sh -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "sh -c 'echo Host * >> ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "sh -c 'echo StrictHostKeyChecking no >> ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "sh -c 'cat ~/.ssh/config'"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "chmod 400 ~/.ssh/config"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo -e  'y\n' | ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "chmod 600 ~/.ssh/authorized_keys"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "ssh 0 id"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "ssh 0 hostname"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo source /opt/intel/impi/5.1.3.223/bin64/mpivars.sh >> ~/.bashrc"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo \"export I_MPI_FABRICS=shm:dapl\" >> ~/.bashrc"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo \"export I_MPI_DAPL_PROVIDER=ofa-v2-ib0\" >> ~/.bashrc"
        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo \"export I_MPI_DYNAMIC_CONNECTION=0\" >> ~/.bashrc"

        sshpass -p $AZVMPass ssh -o ConnectTimeout=3 $AZVMUser@$AZIPVMB "echo '$AZVMPass' |sudo -S sh -c 'echo y |waagent -deprovision'"

        if [ $CONTINUE == "y" ]
        then
            echo "Deallocating VM Base Image"
            az vm deallocate --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"VMHPCBASE
            f_news "VM Base Image Deallocated" "VM Base Image Deallocate Failed"

            echo "VM Base Image Generalize"
            az vm generalize --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"VMHPCBASE
            f_news "Resource Group Created" "Resource Group Failed"

            echo "Creating Base Image"
            az image create --resource-group "$AZCSUFF"RGHPC --name "$AZCSUFF"VMHPCIMG --source "$AZCSUFF"VMHPCBASE
            f_news "Base Image Created" "Base Image Failed"
            echo "Creating VM HEAD NODE"
            az vm create --resource-group "$AZCSUFF"RGHPC --public-ip-address "$AZCSUFF"PIPHPC --availability-set "$AZCSUFF"AVSHPC --nsg "$AZCSUFF"NSGHPC --vnet-name "$AZCSUFF"VNETHPC --subnet "$AZCSUFF"VNETINTHPC --name "$AZCSUFF"VMHPC001 --size $AZSKUAS --image "$AZCSUFF"VMHPCIMG --admin-username $AZVMUser --admin-password "$AZVMPass"
            f_news "VM HEAD NODE Created" "VM HEAD NODE Failed"
            echo "Creating VM WORK NODES"
            az vm create --resource-group "$AZCSUFF"RGHPC --public-ip-address "" --availability-set "$AZCSUFF"AVSHPC --nsg "$AZCSUFF"NSGHPC --vnet-name "$AZCSUFF"VNETHPC --subnet "$AZCSUFF"VNETINTHPC --name "$AZCSUFF"VMHPC002 --size $AZSKUAS --image "$AZCSUFF"VMHPCIMG --admin-username $AZVMUser --admin-password "$AZVMPass"
            az vm create --resource-group "$AZCSUFF"RGHPC --public-ip-address "" --availability-set "$AZCSUFF"AVSHPC --nsg "$AZCSUFF"NSGHPC --vnet-name "$AZCSUFF"VNETHPC --subnet "$AZCSUFF"VNETINTHPC --name "$AZCSUFF"VMHPC003 --size $AZSKUAS --image "$AZCSUFF"VMHPCIMG --admin-username $AZVMUser --admin-password "$AZVMPass"
            f_news "VM WORK NODES Created" "VM WORK NODES Failed"
            for i in $(seq -w 001 003); do az vm restart --no-wait -g "$AZCSUFF"RGHPC -n "$AZCSUFF"VMHPC$i; done
            sleep 30
        else
            echo "HPC FAILED"
            exit 2
        fi

        echo -e "HEAD NODE Access with SSH:\n Address: $(echo $AZDNSN).$AZZONE.cloudapp.azure.com\n Username: $AZVMUser\n Password: $AZVMPass\n"
        echo ""
        ;;
    remove)
        az group delete -y --name "$2"RGHPC
        f_news "Resource Group deleted" "Resource Group delete Failed"
        ;;
    *)
        echo "Usage: $0 {deploy AZUREZONE COMPANYPREFIX VMUSER VMPASS | remove COMPANYPREFIX}"
        exit 2
        ;;
esac
