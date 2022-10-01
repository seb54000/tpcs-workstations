#!/bin/bash

# TODO review solution with using output from serverinfo 
# (with a query string option to retrieve list of instances in a JSON format)

# We may not be able to login with password, we need to use ec2-user with key and go check the logs of cloudinti to be sure everything is OK ?
# Try sshpass ?? https://stackoverflow.com/questions/32255660/how-to-install-sshpass-on-mac
# brew install sshpass 
# brew install hudochenkov/sshpass/sshpass  # https://gist.github.com/arunoda/7790979 // https://github.com/Homebrew/brew/issues/7994 

SERVER_LIST=$(curl http://serverinfo.tpkube2709.multiseb.com/ | grep -v pre | awk '{print $4}')

export SSHPASS=${TF_VAR_cloudus_user_passwd}

for vm in $SERVER_LIST
do
    echo "Testing ${vm} : "
    sshpass -e ssh -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile=/dev/null" cloudus@${vm} hostname
done
