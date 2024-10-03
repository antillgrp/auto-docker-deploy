#!/usr/bin/env bash

# git add . && git commit -m "sync: $(date)" && git push

### COMMON ##########################################################################################################################

set -Eeuo pipefail; 

# https://stackoverflow.com/a/42956288
# script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
script_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"

setup_colors() { # https://stackoverflow.com/a/72652446
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' 
    RED='\033[0;31m' BRED='\033[1;31m' URED='\033[4;31m' BGRED='\033[41m'        
    GREEN='\033[0;32m' BGREEN='\033[1;32m' UGREEN='\033[4;32m' BGGREEN='\033[42m'
    BLUE='\033[0;34m' BBLUE='\033[1;34m' UBLUE='\033[4;34m' BGBLUE='\033[44m'
    CYAN='\033[0;36m' BCYAN='\033[1;36m' UCYAN='\033[4;36m' BGCYAN='\033[46m' 
    YELLOW='\033[1;33m' BYELLOW='\033[1;33m' UYELLOW='\033[4;33m' BGYELLOW='\033[43m' 
  else
    NOFORMAT='' 
    RED='' BRED='' URED='' BGRED=''        
    GREEN='' BGREEN='' UGREEN='' BGGREEN=''
    BLUE='' BBLUE='' UBLUE='' BGBLUE=''
    CYAN='' BCYAN='' UCYAN='' BGCYAN='' 
    YELLOW='' BYELLOW='' UYELLOW='' BGYELLOW=''
  fi
}

setup_colors

msg() { echo >&2 -e "${*}"; }

msg_success() { msg "${GREEN}[\xE2\x9C\x94]${NOFORMAT} ${*}"; }

msg_important() { msg "${GREEN}[! IMPORTANT]${NOFORMAT} ${*}"; }

# default exit status 1
error() { local msg=$1; msg "${BRED}[! ERROR]${NOFORMAT} $msg"; } 
fail() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 
fatal() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 


### LOGIC ###########################################################################################################################

test $? -eq 0 || fail "This script need root/sudo privilege to run"

CURRENT_BASH_VERSION=$(uname -r | cut -c1-3); VERSION_LIMIT=4.2;
if (( $(echo "$CURRENT_BASH_VERSION <= $VERSION_LIMIT" | bc -l) )); then
  fail "Current bash version is [${CURRENT_BASH_VERSION}], needs to be higher than [${VERSION_LIMIT}]"
fi

VERSION=1.0.2 # TODO integrate https://github.com/fmahnke/shell-semver/blob/master/increment_version.sh

version() {
  msg
  msg "${YELLOW}Version: ${VERSION}${NOFORMAT}" 
  msg
}

usage() {
  msg
  msg "${YELLOW}Usage: ./$(basename "${BASH_SOURCE[0]}") [-v] | [-h] | -c <<sbom.conf>> [-t <<tag>>] [ -u ] [ -d ] | -w ${NOFORMAT}" 
  msg 
}

help(){
  usage
  version 
  msg
  msg "Given <<sbom.conf>> (see format below), this script puts toghether all the resources along with a generated  docker compose file "
  msg "to  deploy a fully operative certscan docker stack (certscan+cis+emulator) under $BYELLOW[/opt/certscan/]$NOFORMAT. Also provide an API to manage "
  msg "it's deployment."
  msg
  msg "Available options:"
  msg "-h, --help                         | Prints this help and exit"
  msg "-v, --version                      | Displays the script version"
  msg "-c, --config-file  <<sbom.com>>    | Processes <<sbom.conf>> generating the docker compose and folder structure"
  msg '-t, --tag  <<tag>>                 | Adds <<tag>> sufix to parent folder, if not added "devMonthYear" is used (ex. "dev0824")'
  msg "-d, --deploy                       | Deploys the generated compose file to docker (compose up)"
  msg "-u, --undo-deploy                  | Undoes the deployment (compoese down)"
  #msg "-w, --wipe-out                     | (ALERT! data loose) Completely eliminates deployment, compose, and folder structure"
  msg
  msg "Examples:"
  msg '- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -t "prod" -d'
  msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -u -d"
  msg '- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -t "dev0824" -u'
  msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -w"
  msg
  msg "References: sbom (https://en.wikipedia.org/w/index.php?title=Software_bill_of_materials&redirect=no)"
  msg
  msg "sbom.conf format:"
  msg "-----------------------------------------------------------------------------------------------------------"
  msg "tennant=saudi"
  msg "cs-version=4.3.4"
  msg "release-kit-zip-path=Releases/4.3.4/Certscan Release Kit 4.3.4 Saudi National Interim - June 7th 2024.zip"
  msg "domain=portal.certscan.net"
  msg "[certscan]"
  msg "flyway=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/flyway:4.3.4-release-20240607"
  msg "..."
  msg "[third-party]"  
  msg "postgres=postgres:12-alpine"
  msg "..."
  msg "[cis]"
  msg "cis-api=..."
  msg "cis-ui=..."
  msg "cis-ps=..."
  msg "[emulator]"
  msg "emu-api=..."
  msg "emu-ui=..."
  msg "emu-pkg=<<zip file with emulator archive>>"
  msg "-----------------------------------------------------------------------------------------------------------"
  msg
}

dld_s3_obj() {
  local bucket_name=$1
  local object_name=$2
  local destination_file_name=$3
  local response=""; response=$(aws s3api get-object --bucket "$bucket_name" --key "$object_name" "$destination_file_name") ||
  fail "AWS reports get-object operation failed.\n$response" $?
}

docker_cleanup(){
  # TODO review
  # shellcheck disable=SC2046
  # shellcheck disable=SC2006
  docker stop `docker ps -qa`              && 
  docker rm `docker ps -qa`                && 
  docker volume rm `docker volume ls -q`   && 
  docker network rm `docker network ls -q` 
}

#declare syntax below (-gA) only works with bash 4.2 and higher
unset sbom_config_map; declare -gA sbom_config_map=(); 

parseIniFileToMap() { #accepts the name of the file to parse as argument ($1)
  #echo "###" && declare -p sbom_config_map && echo "###" # debug
  
  # https://kb.novaordis.com/index.php/Bash_Return_Multiple_Values_from_a_Function_using_an_Associative_Array [Option 2 (Associative Array is Set up by Calling Layer)]
  declare -A | grep -q "declare -A sbom_config_map" || fail "no \"sbom_config_map\" associative array declared"
  
  currentSection="default"
  [[ -f "$1" && $(tail -c1 "$1") ]] && echo ''>>"$1"
  while read -r line
  do
      # shellcheck disable=SC2001
      cleanLine=$(echo "$line" | sed -e 's/\r//g'); # DEBUG echo $cleanLine
      # LINE COMMENTED
      echo "$cleanLine" | grep -qx '^#.*' && [ "${PIPESTATUS[1]}" -eq 0 ] && continue 
      # NEW SECTION
      echo "$cleanLine" | grep -qx '^\[.*\]' && [ "${PIPESTATUS[1]}" -eq 0 ] && currentSection=$(echo "$cleanLine" | tr -d "[]") 
      # ENTRY
      echo "$cleanLine" | grep -qx '.*=.*' && [ "${PIPESTATUS[1]}" -eq 0 ] && {                             
        key=$currentSection.$(echo "$cleanLine" | awk -F: '{ st = index($0,"=");print  substr($0,0,st-1)}') 
        value=$(echo "$cleanLine" | awk -F: '{ st = index($0,"=");print  substr($0,st+1)}')                 
        sbom_config_map[$key]=$value
      }
  done < "$1"
  # echo "###" && declare -p sbom_config_map && echo "###" # debug
  return 0
}

declare -g S3_BUCKET='s2global-test-bucket'
declare -g IP_ADDRESS && IP_ADDRESS="$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)"
declare -g INSTALL_TAG && INSTALL_TAG="dev$(date +"%m%y")"
declare -g WORKING_DIR=''
declare -g VOLUMES_FOLDER='' 
declare -g COMPOSE_FILE=''  

createFoldersAndCompose(){
  msg && local PREFIX="${sbom_config_map[default.tennant]}_${sbom_config_map[default.cs-version]}"
 
  WORKING_DIR="${script_dir}/${PREFIX}_dkr_${INSTALL_TAG}"; 

  mkdir -p "$WORKING_DIR/deployment_logs" && msg && msg_success "Created stack folder [$WORKING_DIR] ..."

  unset AWS_ACCESS_KEY_ID && unset AWS_SECRET_ACCESS_KEY                           &&
  aws ecr get-login-password                                                       \
  --profile default                                                                \
  --region "$(aws configure get region)" |                                           \
  docker login                                                                     \
  --password-stdin "585953033457.dkr.ecr.$(aws configure get region).amazonaws.com"  \
  --username AWS &> "$WORKING_DIR/deployment_logs/aws_auth.log"
  msg_success "Docker logged in to aws ecr successfuly"
  
  local RKIT_ZIP_FILE="${WORKING_DIR}/${PREFIX}_relkit.zip" && [ ! -f "$RKIT_ZIP_FILE" ]       && 
  dld_s3_obj "$S3_BUCKET" "${sbom_config_map[default.rel-kit-path]}" "$RKIT_ZIP_FILE"  
  msg_success "Downloaded release kit (zip) with configs files ..."                    
  
  local RKIT_FOLDER="${WORKING_DIR}/${PREFIX}_relkit" && [ ! -d "$RKIT_FOLDER" ]               &&
  mkdir -p "$RKIT_FOLDER"                                                                      &&
  busybox unzip "$RKIT_ZIP_FILE" -o -d "$RKIT_FOLDER"  > "$WORKING_DIR/deployment_logs/${PREFIX}_relkit_unzip.log"
  msg_success "Uncompresed release kit (zip) file ..."

  configs="$(for e in "$RKIT_FOLDER"/*; do [[ -d "$e" ]] && { echo "$e"; break; }; done)"                     &&
  cp -v -r -p -a "$configs"/certscan-docker/r* "$VOLUMES_FOLDER"  > "$WORKING_DIR/deployment_logs/cp.res.log" &&
  cp -v -r -p -a "$configs"/certscan-docker/h* "$VOLUMES_FOLDER"  > "$WORKING_DIR/deployment_logs/cp.hap.log" &&
  chown -R 99:99 "$VOLUMES_FOLDER"/h*                                                                         &&
  msg_success "Copied configs folders from release kit to volumes folder ..."

  COMPOSE_FILE="${WORKING_DIR}/${PREFIX}_compose.yaml"

### NETWORKS AND SERVICES
msg_success "Creating docker compose file from template at: [ $COMPOSE_FILE ]"
tee "$COMPOSE_FILE" <<EOF > /dev/null 
networks:
  cs_backend:
  cis_backend:
services: 
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
EOF
  
  VOLUMES_FOLDER="${WORKING_DIR}/${PREFIX}_dkr_volumes" 
  [ ! -d "${VOLUMES_FOLDER}" ] && mkdir -p "${VOLUMES_FOLDER}"
  msg_success "Created volumes folder ..."
  

### REDIS
[ -n "${sbom_config_map[third-party.redis]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null 
  ####
  redis:
    image: "${sbom_config_map[third-party.redis]}"
    container_name: redis
    restart: always
    environment:
      REDIS_PASSWORD: 'solutions@123'
    volumes:
      - "${VOLUMES_FOLDER}/dckr-vol-redis:/data"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"
    command: /bin/sh -c 'redis-server --appendonly yes --requirepass '$${REDIS_PASSWORD}'
    networks:
      - cs_backend
    ports:
      - "6379"
    healthcheck:
      test: ["CMD-SHELL", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
  ####
  ####
  #redis-mgmt:
    # image: redislabs/redisinsight:1.14.0 # TODO <-- move to conf file third party
    # container_name: redis-mgmt-pt-6380
    # volumes:
    #   - ${VOLUMES_FOLDER}/redisinsight:/data
    # networks:
    #   - cs_backend
    # ports:
    #   - '6380:8001'
  ####
EOF
msg_success "Redis added to compose: [ $COMPOSE_FILE ]"

### RABBITMQ
[ -n "${sbom_config_map[third-party.rabbitmq]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null
  #### 
  rabbitmq:
    image: "${sbom_config_map[third-party.rabbitmq]}"
    container_name: rabbitmq
    restart: always
    hostname: rabbitmq-container
    ports:
      - "5672:5672"
      - "5673:15672" # <- UI
    volumes:
      - "${VOLUMES_FOLDER}/dckr-vol-rabbitmq:/var/lib/rabbitmq/mnesia"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"      
    networks:
      - cs_backend
    healthcheck:
      test: rabbitmq-diagnostics -q ping
      interval: 30s
      timeout: 30s
      retries: 3
  ####
EOF


  sed -i '/^[[:space:]]*$/d' "$COMPOSE_FILE"
  return 0

}

composeDown() { 
  docker compose -f "${COMPOSE_FILE}" --profile monitoring down &>"$WORKING_DIR/deployment_logs/undo_deployment.log" && sleep 3; 
}

composeUp() { 
  docker compose -f "${COMPOSE_FILE}" --profile monitoring up -d &>"$WORKING_DIR/deployment_logs/deployment.log" && sleep 3; 
}

parse_params() {
  args=("$@") && [[ ${#args[@]} -eq 0 ]] && fail "Missing script arguments, try (-h) option, to understand usage"
  
  local CONFIG_FILE=""

  while : ; do
    case "${1-}" in
      -c | --config-file)
          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

          [[ -z "${2-}" ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-c, --config-file) option, file path is expected"

          CONFIG_FILE="${2-}"
          shift
          ;;
      -t | --tag)
          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

          [[ -z "${2-}" ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-t, --tag) option, tag (string) is expected"

          INSTALL_TAG="${2-}"
          shift
          ;;
      -u | --undo-deploy)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
          ;;
      -d | --deploy)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
          ;;
      -e | --encrypt)
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          openssl aes-128-cbc -k "solutions@123" -e -pbkdf2 -iter 100 -a -salt < "$(basename "${BASH_SOURCE[0]}")" > \
          "$(basename "${BASH_SOURCE[0]}")".aes
        
          # decrypt --> cat deploy-certscan-docker-X.Y.Z.sh.aes | \
          # openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k "solutions@123" > \
          # deploy-certscan-docker-X.Y.Z.sh
          ;;
      -h | --help) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          help && exit 
          ;; 
      -v | --version) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          version && exit 
          ;; 
      -w | --wipe-out)
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          fail "Option (-w | --wipe-out) no yet implemented"
          ;;
      -?*) fail " ${RED}[ERROR]${NOFORMAT} Unknown option: ${2-}";;
        *) break ;;
    esac
    shift
  done

  [[ "${args[*]}" == *"-c"* ]] || [[ "${args[*]}" == *"--config-file"* ]] &&
  parseIniFileToMap "${CONFIG_FILE-}"                                     &&
  # DEBUG echo "###" && declare -p sbom_config_map | sed 's/\[/\n\[/g;' | sed 's/)/\n)/g;' && echo "###"
  createFoldersAndCompose

  [[ "${args[*]}" == *"-u"* ]] || [[ "${args[*]}" == *"--undo-deploy"* ]] &&
  composeDown

  [[ "${args[*]}" == *"-d"* ]] || [[ "${args[*]}" == *"--deploy"* ]]      &&
  composeUp

  return 0
}

# trap cleanup SIGINT SIGTERM ERR EXIT

# cleanup() { 
#   trap - SIGINT SIGTERM ERR EXIT;
#   # script cleanup here ########################
# }

parse_params "$@"

#####################################################################################################################################

  # tennant=oman # wajajah
  # cs-version=4.3.3
  # domain=wajajah.certscan.rop.gov.internal
  # rel-kit-path=Releases/4.3.3/Certscan Release Kit 4.3.3 Oman_Hotfix_SOL-27093_ July 8th 2024.zip
  # [third-party]
  # postgres=postgres:12-alpine
  # pgweb=sosedoff/pgweb
  # redis=redis:7.2.4-alpine
  # rabbitmq=rabbitmq:3.13.0-management-alpine
  # [certscan]
  # flyway=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/flyway:4.3.3-release-20240502
  # csview=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/core:4.3.3-release-20240628-Hotfix
  # workflow=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowdesginerservice:4.3.3-release-20240502
  # cchelp=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/cchelp:4.3.3-release-20240502
  # configserver=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/configservice:4.3.3-release-20240502
  # assignmentservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/assignmentservice:4.3.3-release-20240502
  # converter=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/imageprocessor:4.3.3-release-20240502
  # event=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/eventalarms:4.3.3-release-20240502
  # workflowengine=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowengine:4.3.3-release-20240502
  # appconfiguration=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/applicationconfiguration:4.3.3-release-20240502
  # discoveryservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/discoveryservice:4.3.3-release-20240502
  # usermanagement=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/usermanagement:4.3.3-release-20240502
  # certscanjobs=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/certscan-db-jobs:4.3.3-release-20240502
  # haproxy=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/haproxy:4.3.3-release-20240502
  # #irservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/irservice:4.3.4-release-20240607
  # [cis]
  # #cis-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/api:dev-4.5.1.288
  # cis-cert-path=cis-4/cis_api_certs_2024.zip
  # cis-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/ui:dev-4.5.1.273
  # cis-ps=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/ps:dev-4.5.1.288
  # [emulator]
  # #emu-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/api:dev-1.6.0.16
  # emu-scans-path=cis-emulator/cs-cis-demo.zip
  # emu-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/ui:prod-0.1.0.2

#####################################################################################################################################

  # tennant=oman # surfait
  # cs-version=4.3.5
  # domain=surfait.certscan.rop.gov.internal
  # rel-kit-path=Releases/4.3.5/Certscan Release Kit 4.3.5 Oman- August 12th 2024.zip
  # [third-party]
  # redis=redis:7.2.4-alpine
  # rabbitmq=rabbitmq:3.13.0-management-alpine
  # postgres=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/postgres:4.3.5-release-20240812
  # pgweb=sosedoff/pgweb
  # mongodb=mongo:latest
  # haproxy=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/haproxy:4.3.5-release-20240812
  # [certscan]
  # flyway=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/flyway:4.3.5-release-20240812
  # discoveryservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/discoveryservice:4.3.5-release-20240812
  # configserver=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/configservice:4.3.5-release-20240812
  # appconfiguration=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/applicationconfiguration:4.3.5-release-20240812
  # cchelp=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/cchelp:4.3.5-release-20240812
  # converter=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/imageprocessor:4.3.5-release-20240812
  # csview=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/core:4.3.5-release-20240812
  # workflow=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowdesginerservice:4.3.5-release-20240812
  # workflowengine=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/workflowengine:4.3.5-release-20240812
  # usermanagement=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/usermanagement:4.3.5-release-20240812
  # assignmentservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/assignmentservice:4.3.5-release-20240812
  # event=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/eventalarms:4.3.5-release-20240812
  # irservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/irservice:4.3.5-release-20240812
  # manifestservice=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/manifestservice:4.3.5-release-20240812
  # [cis]
  # #cis-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/api:dev-4.5.1.288
  # cis-cert-path=cis-4/cis_api_certs_2024.zip
  # cis-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/ui:dev-4.5.1.273
  # cis-ps=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2global/cis/ps:dev-4.5.1.288
  # [emulator]
  # #emu-api=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/api:dev-1.6.0.16
  # emu-scans-path=cis-emulator/cs-cis-demo.zip
  # emu-ui=585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cis/emu/ui:prod-0.1.0.2

#####################################################################################################################################

  # # https://www.baeldung.com/linux/bash-hash-table
  # declare -A DKR_STACK_COMPS=(
  #   [tennant]='saudi'
  #   [cs-version]='4_3_4'
  #   [bom-s3-path]='Releases/4.3.4/Certscan Release Kit 4.3.4 Saudi National Interim - June 7th 2024.zip' 
  #   [postgres]='postgres:12-alpine' 
  #   [flyway]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/flyway:4.3.4-release-20240607'
  #   [pgweb]='sosedoff/pgweb'
  #   [redis]='redis:7.2.4-alpine' 
  #   [rabbitmq]='rabbitmq:3.13.0-management-alpine'
  #   [haproxy]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/haproxy:4.3.4-release-20240607'
  #   [discovery-service]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/discoveryservice:4.3.4-release-20240607'
  #   [configserver]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/configservice:4.3.4-release-20240607'
  #   [applicationconfiguration]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/applicationconfiguration:4.3.4-release-20240607'
  #   [cchelp]='585953033457.dkr.ecr.us-east-2.amazonaws.com/s2/cs/cchelp:4.3.4-release-20240607'
  # )

#####################################################################################################################################

    
  #     - Kestrel__Certificates__Default__Path=/cis/certs/certscan.pfx                                                          \n\
  #     - Kestrel__Certificates__Default__Password=$(printf '!@OnDem@ndPa$$$$1234')                                             \n\
  #     - Kestrel__Endpoints__http__Url=http://*:34350                                                                          \n\
  #     - Kestrel__Endpoints__https__Url=https://*:34351                                                                        \n\
  #     - Kestrel__Endpoints__grpc__Url=https://*:5003                                                                          \n\
