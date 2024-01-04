#!/bin/bash
region=$1
clienttenantid=$2
clientsubid=$3
clientrg=$4
fwname=$5
depoloyVMurl="https://func-sre-tools-eastus-001.azurewebsites.net/api/deployvm"
destroyVMurl="https://func-sre-tools-eastus-001.azurewebsites.net/api/destroyvm"
iturl="https://itinfra.paloaltonetworks.local/fetch_gw_ips?location=true"
gplocations="singapore-gw,California,India North,India South,HQ,blr-coe"
function_key_d="c0d0VGl3UE5aX3ZGOXotUnY2SWQzeExMRzNSbkVETW40ZVVRcTZIa0hvR2lBekZ1cWlvSWRRPT0K"
data=$(curl -s -k "$iturl")

filtered_ips=$(echo $(echo "$data" | grep -E "($(echo "$gplocations" | tr ',' '|'))" | awk -F ' # ' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}' | paste -sd "," -) | tr -d '"')
sourceips=${filtered_ips%,}
echo 'Installaing the dependancies'
bash ./setup.sh
dt=$(date '+%Y%m%d%H%M%S%m')
user=$(whoami)
bastionsshpath='/tmp/bastionkey'$dt
function_key=$(echo $function_key_d | base64 -d)
full_url="${depoloyVMurl}?region=${region}&clienttenantid=${clienttenantid}&clientsubid=${clientsubid}&clientrg=${clientrg}&fwname=${fwname}&sshkeycontent=${file2}&sourceips=${sourceips}&username=${user}"
echo 'Invoked the service at '$(date)' to deploy the bastion. It might take upto 1 min'
response=$(curl -s -k -H "x-functions-key: ${function_key}" "${full_url}")
#echo $response
echo 'ended at' $(date)
status=$(echo $response | jq -r '.status')
if [[ $status == 'success' ]]
then
    vmss_name=$(echo $response | jq -r '.vmss_name')
    file1=$(echo $response | jq -r '.file1')
    file2=$(echo $response | jq -r '.file2')
    echo 'Bastion deployment is success.'
    echo $file1 | base64 -d >$bastionsshpath
    echo $file2 | base64 -d >$bastionsshpath'.pub'
    chmod 600 $bastionsshpath
    bastionIp=$(echo $response | jq -r '.ip')
    vmkeyfile='/tmp/vmkey'$dt
    ssh=$(echo $response | jq -r '.key')
    vmdetails=$(echo $response | jq -r '.vmdetails')
    echo ${ssh} | base64 -d>$vmkeyfile
    chmod 600 $vmkeyfile
    invalid_attempts=0
    exit_repeat_attempts=0

    IFS=',' read -ra values <<< "$vmdetails"

    while true; do
        echo "Below are the list of the instances under the firewall("$vmss_name")"
        printf "\nS.No.\tHostName\t\t\t\tIP"
        printf "\n------\t--------------------------\t\t-------------"
        printf "\n"

        for ((i=0; i<${#values[@]}; i++)); do
            IFS=':' read -ra parts <<< "${values[i]}"
            ip="${parts[0]}"
            name="${parts[1]}"
            printf "%d\t%s\t\t%s\n" "$((i+1))" "$name" "$ip"
        done
        printf "\n"
        read -p "Select the instance you want to login to (1-${#values[@]}): " choice

        if [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#values[@]} ]]; then
            IFS=':' read -ra selected_parts <<< "${values[choice-1]}"
            vmIP="${selected_parts[0]}"
        else
            echo "Invalid choice. Please select a valid value."
            ((invalid_attempts++))
            if [ $invalid_attempts -ge 3 ]; then
                echo "You have exceeded the maximum number of invalid attempts. Exiting."
                break 2
            fi
            continue
        fi

        invalid_attempts=0

        echo 'Connecting to the firewall instance with the IP: '$vmIP
        ssh -o ProxyCommand="ssh -W %h:%p panwuser@$bastionIp -i $bastionsshpath -oHostKeyAlgorithms=+ssh-rsa -o 'StrictHostKeyChecking=no'" panwuser@${vmIP} -i $vmkeyfile -oHostKeyAlgorithms=+ssh-rsa -o "StrictHostKeyChecking=no"
        
        while true; do
            
            echo '1. Connect to different instance under this firewall'
            echo '2. Exit'
            read -p 'Select the next option: ' option
            case $option in
                1)
                    break
                    ;;
                2)
                    break 3
                    ;;
                *)
                    ((exit_repeat_attempts++))
                    if [ $exit_repeat_attempts -ge 3 ]; then
                        echo "You have exceeded the maximum number of exit attempts. Exiting."
                        break 3
                    fi
                    echo "Invalid choice. Please select a valid value."
                    ;;
                
            esac
        done
    done

full_url="${destroyVMurl}?region=${region}&clienttenantid=${clienttenantid}&clientsubid=${clientsubid}&clientrg=${clientrg}&fwname=${fwname}"
echo 'Invoked the service to destroy the bastion and relevant resources in the background'
curl -s -H "x-functions-key: ${function_key}" "${full_url}" >/dev/null 2>&1 &


rm $vmkeyfile
rm $bastionsshpath
rm $bastionsshpath'.pub'

else
    echo "${response}" 
    echo 'Bastion deployment has failed. Please contact FWaaS SRE team with the above error messages'
fi
