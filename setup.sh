#!/usr/bin/env bash

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
  aws sts get-caller-identity && {
    aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}          &&
    aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}  &&
    aws configure set region "us-east-2"                              &&
    aws configure set output "json"                                   &&
    aws ecr get-login-password --region $(aws configure get region) | \
    docker login                                                      \
    --username AWS                                                    \
    --password-stdin 585953033457.dkr.ecr.$(aws configure get region).amazonaws.com
  } && break
  whiptail \
    --clear \
    --title "AWS: Sign in as IAM user" \
    --yesno "               Error: The provided ID/KEY pair could not be verified. Try again?" \
    --fb 10 100 3>&1 1>&2 2>&3 || break # $(stty size) 
done

####################################################################################################################

wget -qO- https://raw.githubusercontent.com/antillgrp/auto-docker-deploy/main/deploy-certscan-docker-1.0.0.sh.aes | \
openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k "solutions@123" > deploy-certscan-docker.sh
