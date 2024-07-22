#!/usr/bin/env bash

#set -eu -o pipefail # fail on error and report it, debug all lines
#sudo -n true # -n, --non-interactive         non-interactive mode, no prompts are used
test $? -eq 0 || exit 1 "you should have sudo privilege to run this script"

apt-get -qq update && apt-get -qq upgrade -y

exec > setup.log 2>&1

prereq_is_installed(){
  [[ -z $(which $1) ]] && return 1
  [[ -z $($1 --version) ]] && return 1
  return 0
}

grep -qi "prereq_is_installed" /etc/profile || cat <<EOF >> /etc/profile

$(declare -f prereq_is_installed)
EOF

tmp_dir=$(mktemp -d) && echo $tmpdir

#### PREREQS

## -> DOCKER #######################################################################################################

#TODO debug
#apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli

prereq_is_installed "docker" || {
  wget -qO- https://get.docker.com | bash
}

#TODO debug
prereq_is_installed "docker" && echo "docker" || echo "no docker"

## -> LAZYDOCKER ###################################################################################################

prereq_is_installed "lazydocker" || {
  wget -qO- "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" | \
  sed 's|$HOME/.local/bin|/usr/local/bin|' | sudo bash                                                            &&
  mkdir -p $HOME/.config/lazydocker && cat > $HOME/.config/lazydocker/config.yml <<EO1
# https://github.com/jesseduffield/lazydocker/blob/master/docs/Config.md
logs:
  timestamps: true
  since: ''             # set to '' to show all logs
  tail: '50'            # set to 200 to show last 200 lines of logs
EO1
}

#TODO debug
prereq_is_installed "lazydocker" && echo "lazydocker" || echo "no lazydocker"

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

## --> VSCODE ######################################################################################################
code="code --no-sandbox --user-data-dir $HOME/.vscode"                       &&
prereq_is_installed "$code" || {
  mkdir -p "$HOME/.vscode"  && wget -qO "$tmp_dir/vscode.deb"                \
  'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' &&
  dpkg -i "$tmp_dir/vscode.deb" 2>&1  > "$tmp_dir/vscode_install.log"        &&
  echo "alias code=\"code --no-sandbox --user-data-dir $HOME/.vscode\"" >> $HOME/.bashrc
}
#TODO debug
prereq_is_installed "$code" && echo "code" || echo "no code"

#Unistall
# dpkg --purge code

####################################################################################################################

