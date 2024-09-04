#!/usr/bin/env bash

# wget -qO- https://tinyurl.com/setup-1-0-0-sh | sudo bash

# git add . && git commit -m "sync: $(date)" && git push

VERSION=1.0.0 # TODO integrate https://github.com/fmahnke/shell-semver/blob/master/increment_version.sh

#set -eu -o pipefail # fail on error and report it, debug all lines
#sudo -n true # -n, --non-interactive         non-interactive mode, no prompts are used
test $? -eq 0 || exit 1 "you should have sudo/root  privilege to run this script"

prereq_is_installed(){
  [[ -z $(which $1) ]] && return 1
  [[ -z $($1 --version) ]] && return 1
  return 0
}

uninstall_prereqs(){
  #DOCKER
  sudo apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli
  #LAZYDOCKER
  sudo rm -f /usr/local/bin/lazydocker
  #AWS CLI
  sudo rm -rf /usr/local/bin/aws /usr/local/bin/aws_completer /usr/local/aws-cli
  #VSCODE
  sudo dpkg --purge code
}

grep -qi "prereq_is_installed" /etc/profile || cat <<EOF >> /etc/profile

$(declare -f prereq_is_installed)

$(declare -f uninstall_prereqs)

EOF

# $$ = the PID of the running script instance
STDOUT=`readlink -f /proc/$$/fd/1`
STDERR=`readlink -f /proc/$$/fd/2`
#exec > "$bin_dir/setup.log" 2>&1

GOOD="\033[1;32m☑\033[0m"
FAIL="\033[1;31m☒\033[0m"
COOL="\033[1;33m😎\033[0m"

echo && echo "[Initialization]" && echo
bin_dir="/opt/certscan/bin" && mkdir -p $bin_dir    &&
echo -e "$GOOD bin dir created: $bin_dir"

tmp_dir=$(mktemp -d)                                && 
echo -e "$GOOD tmp dir created: $tmp_dir"

# uninstall_prereqs &>>/dev/null

echo && echo "[PREREQS installation]" && echo

apt-get -qq update &>/dev/null      && echo -e "$GOOD system updated"  && 
apt-get -qq upgrade -y &>/dev/null  && echo -e "$GOOD system upgraded" &&
apt-get -qq -y install curl unzip   && echo -e "$GOOD curl installed"

## -> DOCKER #######################################################################################################

prereq_is_installed "docker" || {
  wget -qO- https://get.docker.com | bash &>/dev/null
}

exec 1>$STDOUT 2>$STDOUT # $STDERR # https://stackoverflow.com/a/57004149
prereq_is_installed "docker" && echo -e "$GOOD docker installed" || echo -e "$FAIL docker installation failed"
#exec > "$bin_dir/setup.log" 2>&1

#Uninstall
#apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli

## -> LAZYDOCKER ###################################################################################################

prereq_is_installed "lazydocker" || {
  wget -qO- "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" \
  | sed 's|$HOME/.local/bin|/usr/local/bin|'                                                                    \
  | bash &>/dev/null
} &&
mkdir -p $HOME/.config/lazydocker && cat > $HOME/.config/lazydocker/config.yml <<EO1
# https://github.com/jesseduffield/lazydocker/blob/master/docs/Config.md
logs:
  timestamps: true
  since: ''             # set to '' to show all logs
  tail: '50'            # set to 200 to show last 200 lines of logs
EO1

exec 1>$STDOUT 2>$STDOUT # $STDERR # https://stackoverflow.com/a/57004149
prereq_is_installed "lazydocker" && echo -e "$GOOD lazydocker installed" || echo -e "$FAIL lazydocker installation failed"
#exec > "$bin_dir/setup.log" 2>&1

#Uninstall
#rm -f /usr/local/bin/lazydocker

## --> VSCODE ######################################################################################################

  # code="code --no-sandbox --user-data-dir $HOME/.vscode"                       &&
  # prereq_is_installed "code" || {
  #   mkdir -p "$HOME/.vscode"  && wget -qO "$tmp_dir/vscode.deb"                \
  #   'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' &&
  #   dpkg -i "$tmp_dir/vscode.deb" 2>&1  > "$tmp_dir/vscode_install.log"        &&
  #   echo "alias code=\"code --no-sandbox --user-data-dir $HOME/.vscode\"" >> $HOME/.bashrc
  # }

  # #TODO debug
  # prereq_is_installed "code" && echo "code" || echo "no code"

  #Unistall
  # dpkg --purge code

## --> AWS_CLI #####################################################################################################

prereq_is_installed "aws" || {
  #curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_dir/awscliv2.zip"
  #unzip -o -X -qq -d "$tmp_dir" "$tmp_dir/awscliv2.zip" 
  #$tmp_dir/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  wget -qO- "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"     |
  busybox unzip -d "$tmp_dir" - 2>&1 > "$tmp_dir/aws-unzip.log"            &&
  chmod -R +x "$tmp_dir/aws"                                               &&
  sudo "$tmp_dir/aws/install"                                              \
  --bin-dir /usr/local/bin                                                 \
  --install-dir /usr/local/aws-cli                                         \
  --update                                                                 \
  2>&1 > "$tmp_dir"/aws-install.log
}

exec 1>$STDOUT 2>$STDOUT # $STDERR # https://stackoverflow.com/a/57004149
prereq_is_installed "aws" && echo -e "$GOOD aws cli installed" || echo -e "$FAIL aws cli installation failed"
#exec > "$bin_dir/setup.log" 2>&1

#Uninstall
# rm /usr/local/bin/aws && rm /usr/local/bin/aws_completer && rm -rf /usr/local/aws-cli

## --> AWS_CLI CONFIGURE ############################################################################################

# t=$EPOCHSECONDS && until grep "You can now run:" "$tmp_dir/aws-install.log" ;
# do if (( EPOCHSECONDS-t > 2 )); then break; fi; sleep 1; done

echo && echo "[AWS: Sign in as IAM user]" 

aws sts get-caller-identity &>> "$bin_dir/setup.log" && 
echo && echo -e "$GOOD aws creds validated" 

aws sts get-caller-identity &>> "$bin_dir/setup.log" || { 

  echo && until [[ ${REPLY-} =~ ^[YyNn]$ ]] ; do
 
    read -p "Would you like to provide AWS IAM credetials now? (yY/nN): " -n 1 -r < /dev/tty && echo
    if [[ ! ${REPLY-} =~ ^[YyNn]$ ]] ; then echo "(yY/nN)"; fi

  done 
  
  while [[ $REPLY =~ ^[Yy]$ ]] ; do

    read -p "Enter aws access key id     :" -r < /dev/tty                            &&
    AWS_ACCESS_KEY_ID=$REPLY                                                         &&
    read -p "Enter aws secret access key :" -r < /dev/tty                            &&
    AWS_SECRET_ACCESS_KEY=$REPLY                                                     &&
    mkdir -p $HOME/.aws && echo -e "[default]                                        \n\
    aws_access_key_id=${AWS_ACCESS_KEY_ID}                                           \n\
    aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}" > $HOME/.aws/credentials         &&
    aws sts get-caller-identity &>> "$bin_dir/setup.log"                             &&
    echo && echo -e "$GOOD aws creds validated"                                      &&
    aws configure set region "us-east-2"                                             &&
    aws configure set output "json"                                                  &&
    aws ecr get-login-password                                                       \
    --profile default                                                                \
    --region $(aws configure get region) |                                           \
    docker login                                                                     \
    --password-stdin 585953033457.dkr.ecr.$(aws configure get region).amazonaws.com  \
    --username AWS &>> "$bin_dir/setup.log"                                           &&
    echo -e "$GOOD docker ecr login verified"                                        && 
    break
    read -p "The provided ID/KEY pair could not be verified. Try again? (yY/nN): " -n 1 -r < /dev/tty && echo

  done
  
}

####################################################################################################################

GITHUB_LATEST_VERSION=$(
  curl -L -s -H 'Accept: application/json' https://github.com/antillgrp/auto-docker-deploy/releases/latest |            \
  sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/'
)                                                                                                                       &&
GITHUB_FILE="deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh.aes"                                                &&
#GITHUB_URL="https://github.com/antillgrp/auto-docker-deploy/releases/download/${GITHUB_LATEST_VERSION}/${GITHUB_FILE}" &&
GITHUB_URL="https://github.com/antillgrp/auto-docker-deploy/raw/main/${GITHUB_FILE}"                                    &&

echo && echo "[$GITHUB_FILE unencryption]"

REPLY=y && while [[ $REPLY =~ ^[Yy]$ ]] ; do

  echo                                                                                                                   &&
  read -p "Please, enter unencryption password: " -r < /dev/tty                                                          &&
  wget -qO- $GITHUB_URL | openssl aes-128-cbc -k ${REPLY} -d -pbkdf2 -iter 100 -a -salt  2>> "$bin_dir/setup.log" >      \
  "$bin_dir/deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh"                                                      &&
  chmod +x "$bin_dir/deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh"                                             &&
  echo -e "\n$COOL deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh and prereqs succefully installed" |            \
  tee -a "$bin_dir/setup.log"                                                                                            &&
  echo -e "\n$COOL To review the log do: \033[1;33mcat $bin_dir/setup.log\033[0m" |                                      \
  tee -a "$bin_dir/setup.log"                                                                                            &&
  ln -sf "$bin_dir/deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh"                                               \
  "/usr/local/bin/deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh"                                                &&
  echo -e "\n$COOL To start using it do: \033[1;33msudo deploy-certscan-docker-${GITHUB_LATEST_VERSION//v/}.sh\033[0m" | \
  tee -a "$bin_dir/setup.log"                                                                                            &&
  break
  read -p "$GITHUB_FILE Could not be decrypted with the provided password. Try again? (yY/nN)"                           \
  -n 1 -r < /dev/tty && echo

done

####################################################################################################################
echo -e "\n$COOL A sbom.conf example can be found at: \033[1;33m$(pwd)/sbom-example.conf\033[0m\n" | \
tee -a "$bin_dir/setup.log"                                                                          &&
cat > "sbom-example.conf" <<EO3
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

###################################################################################################################
