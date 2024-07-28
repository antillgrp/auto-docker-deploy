#!/usr/bin/env bash

# wget -qO- https://git.new/rfR0pfn | bash

#set -eu -o pipefail # fail on error and report it, debug all lines
#sudo -n true # -n, --non-interactive         non-interactive mode, no prompts are used
test $? -eq 0 || exit 1 "you should have sudo privilege to run this script"

prereq_is_installed(){
  [[ -z $(which $1) ]] && return 1
  [[ -z $($1 --version) ]] && return 1
  return 0
}

grep -qi "prereq_is_installed" /etc/profile || cat <<EOF >> /etc/profile

$(declare -f prereq_is_installed)
EOF

uninstall_prereqs(){
  #DOCKER
  apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli
  #LAZYDOCKER
  rm -f /usr/local/bin/lazydocker
  #AWS CLI
  rm /usr/local/bin/aws && rm /usr/local/bin/aws_completer && rm -rf /usr/local/aws-cli
  #VSCODE
  dpkg --purge code
}

grep -qi "uninstall_prereqs" /etc/profile || cat <<EOF >> /etc/profile

$(declare -f uninstall_prereqs)
EOF

# $$ = the PID of the running script instance
STDOUT=`readlink -f /proc/$$/fd/1`
STDERR=`readlink -f /proc/$$/fd/2`
exec > setup.log 2>&1

apt-get -qq update &>/dev/null && apt-get -qq upgrade -y &>/dev/null && echo update

tmp_dir=$(mktemp -d) && echo $tmp_dir

## -> DOCKER #######################################################################################################

prereq_is_installed "docker" || {
  wget -qO- https://get.docker.com | bash &>/dev/null
}

#TODO debug
prereq_is_installed "docker" && echo "docker" || echo "no docker"

#Uninstall
#apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli

## -> LAZYDOCKER ###################################################################################################

prereq_is_installed "lazydocker" || {
  wget -qO- "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" \
  | sed 's|$HOME/.local/bin|/usr/local/bin|' \
  | sudo bash &>/dev/null
} &&
mkdir -p $HOME/.config/lazydocker && cat > $HOME/.config/lazydocker/config.yml <<EO1
# https://github.com/jesseduffield/lazydocker/blob/master/docs/Config.md
logs:
  timestamps: true
  since: ''             # set to '' to show all logs
  tail: '50'            # set to 200 to show last 200 lines of logs
EO1

#TODO debug
prereq_is_installed "lazydocker" && echo "lazydocker" || echo "no lazydocker"

#Uninstall
#rm -f /usr/local/bin/lazydocker

## --> VSCODE ######################################################################################################
code="code --no-sandbox --user-data-dir $HOME/.vscode"                       &&
prereq_is_installed "code" || {
  mkdir -p "$HOME/.vscode"  && wget -qO "$tmp_dir/vscode.deb"                \
  'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' &&
  dpkg -i "$tmp_dir/vscode.deb" 2>&1  > "$tmp_dir/vscode_install.log"        &&
  echo "alias code=\"code --no-sandbox --user-data-dir $HOME/.vscode\"" >> $HOME/.bashrc
}
#TODO debug
prereq_is_installed "code" && echo "code" || echo "no code"

#Unistall
# dpkg --purge code

## --> AWS_CLI #####################################################################################################

prereq_is_installed "aws" || {
  wget -qO- "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"     |
  busybox unzip -d "$tmp_dir" - 2>&1 > "$tmp_dir/aws-unzip.log"            &&
  chmod -R +x "$tmp_dir/aws"                                               &&
  "$tmp_dir"/aws/install -i /usr/local/aws-cli -b /usr/local/bin --update  \
  2>&1 > "$tmp_dir"/aws-install.log
}

#TODO debug
prereq_is_installed "aws" && echo "aws" || echo "no aws" #TODO debug

#Uninstall
# rm /usr/local/bin/aws && rm /usr/local/bin/aws_completer && rm -rf /usr/local/aws-cli

# t=$EPOCHSECONDS && until grep "You can now run:" "$tmp_dir/aws-install.log" ;
# do if (( EPOCHSECONDS-t > 2 )); then break; fi; sleep 1; done

exec 1>$STDOUT 2>$STDOUT # $STDERR # https://stackoverflow.com/a/57004149

whiptail \
    --title "AWS: Sign in as IAM user" \
    --yesno "                        Would you like to provide AWS IAM credetials now?" \
    --fb 10 100 3>&1 1>&2 2>&3 && 
while true ; do
  # https://stackoverflow.com/a/49356580
  export AWS_ACCESS_KEY_ID=$(whiptail                                 \
    --title "AWS: Sign in as IAM user"                                \
    --inputbox "                        \nEnter aws access key id:"   \
    --fb 10 100 3>&1 1>&2 2>&3
  ) &&
  export AWS_SECRET_ACCESS_KEY=$(whiptail                             \
    --title "AWS: Sign in as IAM user"                                \
    --inputbox "                        Enter aws secret access key:" \
    --fb 10 100 3>&1 1>&2 2>&3
  ) && 
  aws sts get-caller-identity 2>&1 >> setup.log                                     &&
  mkdir -p $HOME/.aws                                                               &&
  echo -n "[default]                                                                \n\
  aws_access_key_id=${AWS_ACCESS_KEY_ID}                                            \n\
  aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}" > $HOME/.aws/credentials          &&
  echo -n "[default]                                                                \n\
  region="us-east-2"                                                                \n\
  output=json" > $HOME/.aws/config                                                   &&
  {
    aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}                        &&
    aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}                &&
    aws configure set region "us-east-2"                                            &&
    aws configure set output "json"                                                 &&
    aws ecr get-login-password --region $(aws configure get region) |               \
    docker login                                                                    \
    --password-stdin 585953033457.dkr.ecr.$(aws configure get region).amazonaws.com \
    --username AWS 2>&1 >> setup.log                                                && 
    break
  } 2>&1 >> setup.log 
  whiptail \
    --clear \
    --title "AWS: Sign in as IAM user" \
    --yesno "               Error: The provided ID/KEY pair could not be verified. Try again?" \
    --fb 10 100 3>&1 1>&2 2>&3 || break # $(stty size) 
done

####################################################################################################################

GITHUB_LATEST_VERSION=$(
  curl -L -s -H 'Accept: application/json' https://github.com/antillgrp/auto-docker-deploy/releases/latest | \
  sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/'
)                                                                                                                      &&
GITHUB_FILE="deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh.aes"                                               &&
GITHUB_URL="https://github.com/antillgrp/auto-docker-deploy/releases/download/${GITHUB_LATEST_VERSION}/${GITHUB_FILE}" &&
while true ; do
  encrypt_pass=$(whiptail                                                                                              \
      --title "$GITHUB_FILE unencryption"                                                                              \
      --passwordbox "\n             Please, enter unencryption password:"                                              \
      --fb 10 70 3>&1 1>&2 2>&3)                                                                                       && 
  wget -qO- $GITHUB_URL |                                                                                              \
  openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k ${encrypt_pass} >                                               \
  "deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh" 2>> setup.log                                               &&
  chmod +x "deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh"                                                    &&
  echo "deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh succefuly downloaded and made executable" >> setup.log  && 
  break                                                                                                                ||
  whiptail                                                                                                             \
    --clear                                                                                                            \
    --title "$GITHUB_FILE unencryption"                                                                                \
    --yesno "Error: $GITHUB_FILE could not be decrypted with the provided password. Try again?"                        \
    --fb 10 110 3>&1 1>&2 2>&3 || break # $(stty size)
done

####################################################################################################################

cat > sbom.conf <<EO3
tennant=oman
cs-version=4.3.3
domain=wajajah.certscan.rop.gov.internal
rel-kit-path=Releases/4.3.3/Certscan Release Kit 4.3.3 Oman_Hotfix_SOL-27093_ July 8th 2024.zip
[third-party]
postgres=postgres:12-alpine
pgweb=sosedoff/pgweb
redis=redis:7.2.4-alpine
rabbitmq=rabbitmq:3.13.0-management-alpine
[certscan]
flyway=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/flyway:4.3.3-release-20240502
csview=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/core:4.3.3-release-20240628-Hotfix
workflow=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowdesginerservice:4.3.3-release-20240502
cchelp=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/cchelp:4.3.3-release-20240502
configserver=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/configservice:4.3.3-release-20240502
assignmentservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/assignmentservice:4.3.3-release-20240502
converter=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/imageprocessor:4.3.3-release-20240502
event=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/eventalarms:4.3.3-release-20240502
workflowengine=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowengine:4.3.3-release-20240502
appconfiguration=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/applicationconfiguration:4.3.3-release-20240502
discoveryservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/discoveryservice:4.3.3-release-20240502
usermanagement=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/usermanagement:4.3.3-release-20240502
certscanjobs=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/certscan-db-jobs:4.3.3-release-20240502
haproxy=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/haproxy:4.3.3-release-20240502
#irservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/irservice:4.3.4-release-20240607
[cis]
#cis-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/api:dev-4.5.1.288
cis-cert-path=cis-4/cis_api_certs_2024.zip
cis-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/ui:dev-4.5.1.273
cis-ps=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/ps:dev-4.5.1.288
[emulator]
#emu-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/api:dev-1.6.0.16
emu-scans-path=cis-emulator/cs-cis-demo.zip
emu-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/ui:prod-0.1.0.2
EO3
