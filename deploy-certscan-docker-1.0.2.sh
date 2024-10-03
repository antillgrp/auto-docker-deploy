#!/usr/bin/env bash

# ./deploy-certscan-docker-1.0.2.sh -e && git add . && git commit -m "sync: $(date)" && git push

#region COMMON ##########################################################################################################################

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

msg_success() { sleep 1s && msg "${GREEN}[\xE2\x9C\x94]${NOFORMAT} ${*}"; }

msg_important() { msg "${GREEN}[! IMPORTANT]${NOFORMAT} ${*}"; }

# default exit status 1
error() { local msg=$1; msg "${BRED}[! ERROR]${NOFORMAT} $msg"; } 
fail() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 
fatal() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 

#pad () { [ "$#" -gt 1 ] && [ -n "$2" ] && printf "$1%$2.${2#-}s"; }

pad() { echo "$1$(printf -- ' '%.s $(seq -s ' ' $(($2-${#1}))))"; }

#endregion

#region UTILS ###########################################################################################################################

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
  msg "${YELLOW}Usage: ./$(basename "${BASH_SOURCE[0]}") [-v] | [-h] | -c <<sbom.conf>> [ -g ] [-t <<tag>>] [ -u ] [ -d ] | -w ${NOFORMAT}" 
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
  msg "-c, --config-file  <<sbom.com>>    | Parses <<sbom.conf>> and collects all sbom info into a data structure"
  msg '-g, --generate                     | (RE)Generates (use when sbom changes) the docker compose and folder structure with the data collected'
  msg '-t, --tag  <<tag>>                 | Adds <<tag>> sufix to parent folder, if not added "devMonthYear" is used (ex. "dev0824")'
  msg "-d, --deploy                       | Deploys the generated compose file to docker (compose up)"
  msg "-u, --undo-deploy                  | Undoes the deployment (compoese down)"
  #msg "-w, --wipe-out                     | (ALERT! data loose) Completely eliminates deployment, compose, and folder structure"
  msg
  msg "Examples:"
  msg '- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -g -t "prod" -d'
  msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -u -d # <-- does not (re)generate, uses the compose already created"
  msg '- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -t "dev0824" -u'
  #msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -w"
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

#endregion

#region DATA ############################################################################################################################

declare -g S3_BUCKET='s2global-test-bucket'
declare -g IP_ADDRESS && IP_ADDRESS="$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)"
declare -g INSTALL_TAG && INSTALL_TAG="dev$(date +"%m%y")"
declare -g PREFIX=''
declare -g WORKING_DIR=''
declare -g VOLUMES_FOLDER='' 
declare -g COMPOSE_FILE=''  

populateGlobalVar(){

  PREFIX="cs${sbom_config_map[default.cs-version]}_${sbom_config_map[default.tennant]}"
  WORKING_DIR="${script_dir}/${PREFIX}_${INSTALL_TAG}";
  COMPOSE_FILE="${WORKING_DIR}/${PREFIX}_compose.yaml"

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
  populateGlobalVar

  return 0
}

#endregion

#region createFoldersAndCompose #########################################################################################################

createFoldersAndCompose(){
  
  TENNANT=$(
    [ -n "${sbom_config_map[default.tennant]-}" ]     && 
    printf '%s' "${sbom_config_map[default.tennant]}" || 
    printf '%s' "cbp"
  )

  DOMAIN=$(
    [ -n "${sbom_config_map[default.domain]-}" ]     && 
    printf '%s' "${sbom_config_map[default.domain]}" || 
    printf '%s' "portal.certscan.net"
  )
  
  mkdir -p "$WORKING_DIR/deployment_logs" && msg && msg_success "Created stack folder [$WORKING_DIR] ..."

  local RKIT_ZIP_FILE="${WORKING_DIR}/${PREFIX}_relkit.zip" && [ ! -f "$RKIT_ZIP_FILE" ]       && 
  dld_s3_obj "$S3_BUCKET" "${sbom_config_map[default.rel-kit-path]}" "$RKIT_ZIP_FILE"  
  [ -f "$RKIT_ZIP_FILE" ] && msg_success "Downloaded release kit (zip) with configs files ..."                    
  
  local RKIT_FOLDER="${WORKING_DIR}/${PREFIX}_relkit" && [ ! -d "$RKIT_FOLDER" ]               &&
  mkdir -p "$RKIT_FOLDER"                                                                      &&
  busybox unzip "$RKIT_ZIP_FILE" -o -d "$RKIT_FOLDER"  > "$WORKING_DIR/deployment_logs/${PREFIX}_relkit_unzip.log"
  [ -d "$RKIT_FOLDER" ] && msg_success "Uncompresed release kit (zip) file ..."

  VOLUMES_FOLDER="${WORKING_DIR}/${PREFIX}_dkr_volumes" 
  [ ! -d "${VOLUMES_FOLDER}" ] && mkdir -p "${VOLUMES_FOLDER}"
  [ -d "${VOLUMES_FOLDER}" ] && msg_success "Created volumes folder ..."
  
  configs="$(for e in "$RKIT_FOLDER"/*; do [[ -d "$e" ]] && { echo "$e"; break; }; done)"                      &&
  cp -v -r -p -a "$configs"/certscan-docker/r* "$VOLUMES_FOLDER"  &> "$WORKING_DIR/deployment_logs/cp.res.log" &&
  msg_success "Copied [.properties] files from release kit to volumes folder ..."                              &&
  cp -v -r -p -a "$configs"/certscan-docker/h* "$VOLUMES_FOLDER"  &> "$WORKING_DIR/deployment_logs/cp.hap.log" &&
  chown -R 99:99 "$VOLUMES_FOLDER"/h*                                                                          &&
  msg_success "Copied haproxy configs from release kit to volumes folder ..."

### COMPOSE

### NETWORKS AND SERVICES
msg_success "Creating docker compose file from template at: [ $COMPOSE_FILE ]"

tee "$COMPOSE_FILE" <<EOF > /dev/null 
networks:
  cs_backend:
  cis_backend:
services: 
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
EOF

##################################################################################################
##### THIRD-PARTY ################################################################################
##################################################################################################

### REDIS
[ -n "${sbom_config_map[third-party.redis]-}" ] && {

  msg
  msg '############################################################################################'
  msg '#### THIRD-PARTY SW ########################################################################'
  msg '############################################################################################'
  msg

  REDIS_PASSWORD=$(printf '$${REDIS_PASSWORD}')

} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
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
    command: /bin/sh -c 'redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}'
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
EOF
msg_success "[$(pad " redis" 20)] added to compose: [ $COMPOSE_FILE ]"

### RABBITMQ
[ -n "${sbom_config_map[third-party.rabbitmq]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
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
msg_success "[$(pad " rabbitmq" 20)] added to compose: [ $COMPOSE_FILE ]"

#TODO POSTGRES 12 TO POSTGRES 16 migration job

### POSTGRES
[ -n "${sbom_config_map[third-party.postgres]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  postgres:
    image: "${sbom_config_map[third-party.postgres]}"
    container_name: postgres
    restart: always
    #user: 70:70
    ports:
      - "5432:5432"  
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_USER: postgres
      POSTGRES_DB: postgres
    volumes:
      - "${VOLUMES_FOLDER}/dckr-vol-postgres:/var/lib/postgresql/data"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    command:
      [
        "postgres",
        "-c",
        "log_statement=all",
        "-c",
        "log_destination=stderr",
        "-c",
        "shared_preload_libraries=pg_cron",
        "-c",
        "max_worker_processes=40",
        "-c",
        "cron.database_name=certscandb",
      ]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready"]
      interval: 10s
      timeout: 5s
      retries: 5
  ####
EOF
msg_success "[$(pad " postgres" 20)] added to compose: [ $COMPOSE_FILE ]"

### SUPERSET
[ -n "${sbom_config_map[third-party.superset]-}" ] && {

  mkdir -p "${VOLUMES_FOLDER}/superset_home/scripts" "${VOLUMES_FOLDER}/logs/superset"                        &&
  wget -qO- "https://raw.githubusercontent.com/antillgrp/auto-docker-deploy/main/superset-setup.sh" >         \
  "${VOLUMES_FOLDER}/superset_home/scripts/superset-setup.sh"                                                 &&
  chown -R 1000:1000  "${VOLUMES_FOLDER}/superset_home" "${VOLUMES_FOLDER}/logs/superset"
  msg_success "[$(pad " superset" 20)] configs downloaded and copied to volume folder ...";

} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  superset:  
    image: "${sbom_config_map[third-party.superset]}" 
    container_name: reports-pt-8088
    volumes:
      - "${VOLUMES_FOLDER}/logs/superset:/app/superset_home/logs:rw"
      - "${VOLUMES_FOLDER}/superset_home:/app/superset_home/:rw"
    command: bash "/app/superset_home/scripts/superset-setup.sh"
    environment:
      SUPERSET_CONFIG_PATH: "/app/superset_home/scripts/00-superset-config.py"
      SUPERSET_SCRIPTS: "/app/superset_home/scripts"
      DATABASE_URL: postgres
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      SUPERSET_DB_ENGINE: postgres
      SUPERSET_DB_NAME: supersetdb
      SUPERSET_USER: superadmin
      SUPERSET_USER_EMAIL: superadmin@certscan.net
      SUPERSET_PASSWORD: Test@123
    networks:
      - cs_backend
    ports:
      - "8088:8088"
  ####
EOF
msg_success "[$(pad " superset" 20)] added to compose: [ $COMPOSE_FILE ]"

### MONGODB
[ -n "${sbom_config_map[third-party.mongodb]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  mongodb: 
    image: "${sbom_config_map[third-party.mongodb]}"
    container_name: mongodb
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/dckr-vol-mongo:/data/db:rw"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      SERVER_HOME: /home/Server
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: admin
      MONGO_INITDB_DATABASE: admin 
      MONGODBHOST: mongodb
      MONGODBPORT: 27017
    networks:
      - cs_backend
    ports:
      - "27017:27017"
    healthcheck: 
      test: echo 'db.runCommand({find:"app_db_name.devUser"}).ok' | mongosh --authenticationDatabase admin --host 127.0.0.1 -u admin -p admin --quiet | grep -q 1
      interval: 10s
      timeout: 10s
      retries: 3
      start_period: 20s
  ####
EOF
msg_success "[$(pad " mongodb" 20)] added to compose: [ $COMPOSE_FILE ]"

### HAPROXY
[ -n "${sbom_config_map[third-party.haproxy]-}" ] && {
  
  grep -qi "${IP_ADDRESS} ${DOMAIN}" /etc/hosts ||
  printf '%s' "\n${IP_ADDRESS} ${DOMAIN}\n" &>> /etc/hosts
  msg_success "[$(pad " haproxy" 20)] domain name [${DOMAIN}] added to local host file ..." 

  msg ''
  msg_important \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} ${DOMAIN} )${NOFORMAT}" \
  "\nto dns server or host file, so [haproxy stats page] can be accessed at:" \
  "\n☛ ${UCYAN}http://${DOMAIN}/services${NOFORMAT}"
  msg ''

  DEPENDS=()
  [ -n "${sbom_config_map[certscan.cchelp]-}" ] && DEPENDS+=('cchelp,')
  [ -n "${sbom_config_map[certscan.csview]-}" ] && DEPENDS+=('csview,')
  [ -n "${sbom_config_map[certscan.workflow]-}" ] && DEPENDS+=('workflow,')
  [ -n "${sbom_config_map[certscan.converter]-}" ] && DEPENDS+=('converter,')
  DEPENDS_ON=$(printf 'depends_on: [' && printf ' %s' "${DEPENDS[@]}" | sed 's/,*$/ /g' && printf ']')

} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  haproxy:
    image: "${sbom_config_map[third-party.haproxy]}"
    container_name: haproxy
    restart: always
    user: 99:99 # haproxy:x:99:99:Linux User,,,:/var/lib/haproxy:/sbin/nologin
    volumes:
      - "${VOLUMES_FOLDER}/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:rw" 
      - "${VOLUMES_FOLDER}/haproxy/certs/:/etc/ssl/certs"
    ports:
      - "443:8443"
      - "80:8404" # <-- stats   
    entrypoint: # echo -e "" >> /usr/local/etc/haproxy/haproxy.cfg
      - sh
      - -c
      - |
        echo -e "\n\n"   >> /usr/local/etc/haproxy/haproxy.cfg
        grep -qi "listen stats" /usr/local/etc/haproxy/haproxy.cfg || 
        cat <<EO1 >> /usr/local/etc/haproxy/haproxy.cfg
        listen stats
                mode http
                bind *:8404
                stats enable
                #stats realm Statistics
                stats hide-version
                stats refresh 25s
                stats show-node
                #stats auth admin:password
                stats uri /services
        EO1
        haproxy -W -db -f /usr/local/etc/haproxy/haproxy.cfg
    networks:
      cs_backend:
        aliases:
          - "${DOMAIN}"
    healthcheck:
      test: ["CMD-SHELL", 'wget -S http://127.0.0.1:8404/services 2>&1 >/dev/null | grep -q "200 OK" || exit 1']
      interval: 20s
      timeout: 5s
      retries: 5
    ${DEPENDS_ON}
  ####
EOF
msg_success "[$(pad " haproxy" 20)] added to compose: [ $COMPOSE_FILE ]"

##################################################################################################
##### CERTSCAN ###################################################################################
##################################################################################################

### FLYWAY
[ -n "${sbom_config_map[certscan.flyway]-}" ] && {
  msg
  msg '############################################################################################'
  msg '#### CERTSCAN SUB-STACK ####################################################################'
  msg '############################################################################################'
  msg
} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  ####
  flyway:
    image: "${sbom_config_map[certscan.flyway]}"
    container_name: db-migration-flyway
    environment:
      DATABASE_SCHEMA_LIST: "${TENNANT}"
      DATABASE_URL: postgres
      DATABASE_LIST: certscandb
      FLYWAY_USER: postgres
      FLYWAY_PASSWORD: postgres
      FLYWAY_IGNORiE_MIGRATION_PATTERNS: "*:ignored"
    volumes:
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    depends_on:
      - postgres
    # entrypoint:
    #   - /bin/bash
    #   - -c
    #   - |
    #     sleep 10000
  ####
EOF
msg_success "[$(pad " flyway" 20)] added to compose: [ $COMPOSE_FILE ]"

### DISCOVERYSERVICE
[ -n "${sbom_config_map[certscan.discoveryservice]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  discovery-service:
    image: "${sbom_config_map[certscan.discoveryservice]}"
    container_name: discovery-service
    restart: always
    environment:
      SERVER_HOME: /home/Server
    volumes: 
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:
      - "8761:8761"
    healthcheck: 
      test: ["CMD-SHELL", 'wget --no-verbose --tries=1 --spider 127.0.0.1:8761/actuator/health || exit 1',]
      start_period: 20s
      interval: 20s
      timeout: 10s
      retries: 20
  #### 
EOF
msg_success "[$(pad " discovery-service" 20)] added to compose: [ $COMPOSE_FILE ]"

### CCHELP
[ -n "${sbom_config_map[certscan.cchelp]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  cchelp:
    image: "${sbom_config_map[certscan.cchelp]}"
    container_name: cchelp
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
    networks:
      - cs_backend
    ports:
      - "8040:8040"
    healthcheck: 
      test: wget -S http://127.0.0.1:8040/cchelp 2>&1 >/dev/null | grep -q "200 OK" || exit 1
      start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " cchelp" 20)] added to compose: [ $COMPOSE_FILE ]"

### CONFIGSERVER
[ -n "${sbom_config_map[certscan.configserver]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  configserver:
    image: "${sbom_config_map[certscan.configserver]}"
    container_name: configserver
    restart: always
    environment:
      SPRING_RABBITMQ_HOST: rabbitmq
      SERVER_HOME: /home/Server
      #TZ: Asia/Kolkata
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"    
    networks:
      - cs_backend
    ports:
      - "8010:8010"
    healthcheck: 
      test: wget -S http://127.0.0.1:8010/configserver 2>&1 >/dev/null | grep -q "200 OK" || exit 1
      #start_period: 20s
      interval: 20s
      timeout: 10s
      retries: 20
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  #### 
EOF
msg_success "[$(pad " configserver" 20)] added to compose: [ $COMPOSE_FILE ]"

### APPLICATIONCONFIGURATION
[ -n "${sbom_config_map[certscan.appconfiguration]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  appconfiguration:
    image: "${sbom_config_map[certscan.appconfiguration]}"
    container_name: applicationconfiguration
    restart: always
    environment:
      SERVER_HOME: /home/Server
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend   
    ports:
      - "9010:9010"
    healthcheck: 
      test: wget -S http://127.0.0.1:9010/applicationconfiguration 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####  
EOF
msg_success "[$(pad " appconfiguration" 20)] added to compose: [ $COMPOSE_FILE ]"

### CONVERTER
[ -n "${sbom_config_map[certscan.converter]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  converter:
    image: "${sbom_config_map[certscan.converter]}"
    container_name: converter
    restart: always
    environment:
      SPRING_RABBITMQ_HOST: rabbitmq
      SERVER_HOME: /home/Server
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "${VOLUMES_FOLDER}/archive:/home/Output:rw"
      - "${VOLUMES_FOLDER}/archive:/app/data:rw"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:
      - "8090:8089"
      - "7090:7090"
    healthcheck: 
      test: curl -vvv http://127.0.0.1:8089/converter/actuator/health 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " converter" 20)] added to compose: [ $COMPOSE_FILE ]"

### CSVIEW
[ -n "${sbom_config_map[certscan.csview]-}" ] && {

  grep -qi "${IP_ADDRESS} ${DOMAIN}" /etc/hosts ||
  printf '%s' "\n${IP_ADDRESS} ${DOMAIN}\n" &>> /etc/hosts
  msg_success "[$(pad " csview" 20)] domain name [${DOMAIN}] added to local host file ..." 

  msg ''
  msg_important \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} ${DOMAIN} )${NOFORMAT}" \
  "\nto dns server or host file, so [Certscan] can be accessed at:" \
  "\n☛ ${UCYAN}https://${DOMAIN}/csview${NOFORMAT}"
  msg ''

} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  csview:
    image: "${sbom_config_map[certscan.csview]}"
    container_name: csview
    restart: always
    environment:
      SPRING_RABBITMQ_HOST: rabbitmq
      SERVER_HOME: /home/Server
      # TZ: Asia/Kolkata
    volumes:
      - "${VOLUMES_FOLDER}/archive:/home/Output:rw"
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro" 
    networks:
      cs_backend:
        aliases:
          - "${DOMAIN}"  
    ports:
      - "8080:8080"
      - "9001:9001"
    healthcheck:
      test: wget -S http://127.0.0.1:8080/csview 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " csview" 20)] added to compose: [ $COMPOSE_FILE ]"

### WORKFLOW
[ -n "${sbom_config_map[certscan.workflow]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  workflow:
    image: "${sbom_config_map[certscan.workflow]}"
    container_name: workflow
    restart: always
    environment:
      SERVER_HOME: /home/Server
      #TZ: Asia/Kolkata
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      cs_backend:
        aliases:
          - "${DOMAIN}"  
    ports:
      - "8030"
    healthcheck: 
      test: wget -S http://127.0.0.1:8030/workflow 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " workflow" 20)] added to compose: [ $COMPOSE_FILE ]"

### WORKFLOWENGINE
[ -n "${sbom_config_map[certscan.workflowengine]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  workflowengine:
    image: "${sbom_config_map[certscan.workflowengine]}"
    container_name: workflowengine
    restart: always
    environment:
      SERVER_HOME: /home/Server
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "${VOLUMES_FOLDER}/logs:/home/workflowengine/logs:rw"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:
      - "9081:9081"
    healthcheck: # /actuator/health
      test: wget -S http://127.0.0.1:9081/workflowEngine/actuator/health 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20 
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " workflowengine" 20)] added to compose: [ $COMPOSE_FILE ]"

### USERMANEGEMENT
[ -n "${sbom_config_map[certscan.usermanagement]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  ####
  usermanagement:
    image: "${sbom_config_map[certscan.usermanagement]}"
    container_name: usermanagement
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    environment:
      SERVER_HOME: /home/Server
      #TZ: Asia/Kolkata
    networks:
      - cs_backend
    ports:
      - "9047:9047"
    healthcheck: 
      test: wget -S http://127.0.0.1:9047/usermanagement 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20 
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " usermanagement" 20)] added to compose: [ $COMPOSE_FILE ]"

### ASSIGNMENTSERVICE
[ -n "${sbom_config_map[certscan.assignmentservice]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  assignmentservice:
    image: "${sbom_config_map[certscan.assignmentservice]}"
    container_name: assignmentservice
    restart: always
    environment:
      SPRING_RABBITMQ_HOST: rabbitmq
      SERVER_HOME: /home/Server
      #TZ: Asia/Kolkata
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro" 
    ports:
      - "8099:8099"
    healthcheck: 
      test:  wget -S http://127.0.0.1:8099/assignmentservice/actuator/health 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20 
    networks:
      - cs_backend
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " assignmentservice" 20)] added to compose: [ $COMPOSE_FILE ]"

### EVENT
[ -n "${sbom_config_map[certscan.event]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  event:
    image: "${sbom_config_map[certscan.event]}"
    container_name: event
    restart: always
    environment:
      SPRING_RABBITMQ_HOST: rabbitmq
      SERVER_HOME: /home/Server
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:
      - "8060:8060"
    healthcheck: 
      test:  wget -S http://127.0.0.1:8060/event 2>&1 >/dev/null | grep -q "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20 
    depends_on:
      flyway:
        condition: service_completed_successfully
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " event" 20)] added to compose: [ $COMPOSE_FILE ]"

### IRSERVISE
[ -n "${sbom_config_map[certscan.irservice]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  irservice:
    image: ${sbom_config_map[certscan.irservice]}
    container_name: irservice
    restart: always
    environment:
      SERVER_HOME: /home/Server
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "${VOLUMES_FOLDER}/logs:/home/irservice/logs:rw"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:                                                                                    
      - 9099:9099                                                                           
    healthcheck:                                                                              
      test: wget -S http://127.0.0.1:9099/irservice 2>&1 >/dev/null | grep -q "200 OK" || exit 1  
      interval: 20s                                                                           
      timeout: 5s                                                                             
      retries: 5
    depends_on:
      discovery-service:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " irservice" 20)] added to compose: [ $COMPOSE_FILE ]"

### MANIFESTSERVICE
[ -n "${sbom_config_map[certscan.manifestservice]-}" ] && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  ####
  manifestservice:
    image: ${sbom_config_map[certscan.manifestservice]}
    container_name: manifest
    restart: always
    environment:
      SERVER_HOME: /home/Server
      MONGODBHOST: mongodb
      MONGODBPORT: 27017
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: admin
      MONGO_INITDB_DATABASE: certscan
      #TZ: Asia/Kolkata
    volumes:
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"
      - "/etc/timezone:/etc/timezone:ro"
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    ports:
      - "8989:8989"
    # healthcheck:
    #   test: wget -S http://127.0.0.1:8989/manifest 2>&1 >/dev/null | grep -q \"200 OK\" || exit 1
    #   interval: 20s
    #   timeout: 5s
    #   retries: 5
    depends_on:
      mongodb:
        condition: service_healthy
      discovery-service:
        condition: service_healthy
  #### 
EOF
msg_success "[$(pad " manifestservice" 20)] added to compose: [ $COMPOSE_FILE ]"

##################################################################################################
##### CIS ########################################################################################
##################################################################################################

### CIS SUBSTACK
[ -z "${sbom_config_map[cis.cis-cert-path]-}" ] && {

   error 'CIS sub-stack could not be deployed, if "cis-api" is specified, "cis-cert-path" will be mandatory'

} || 
[ -n "${sbom_config_map[cis.cis-ui]-}" ]  &&
[ -n "${sbom_config_map[cis.cis-api]-}" ] && 
[ -n "${sbom_config_map[cis.cis-ps]-}" ]  && {

  msg
  msg '############################################################################################'
  msg '#### CIS SUB-STACK #########################################################################'
  msg '############################################################################################'
  msg

  grep -qi "${IP_ADDRESS} cismgmt.certscan.net" /etc/hosts                                       ||
  printf '%s' "\n${IP_ADDRESS} cismgmt.certscan.net\n" &>> /etc/hosts 
  msg_success "[$(pad " cis-ui" 20)] domain name [cismgmt.certscan.net] added to local host file ..." 

  msg && msg_important                                                                                  \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} cismgmt.certscan.net )${NOFORMAT}" \
  "\nto dns server or host file, so [cis ui] can be accessed at:"                                       \
  "\n☛ ${UCYAN}http://cismgmt.certscan.net:34352${NOFORMAT}" && msg 

  [ ! -f "${WORKING_DIR}/cis_certs.zip" ]                                                        && 
  dld_s3_obj "$S3_BUCKET" "${sbom_config_map[cis.cis-cert-path]}" "${WORKING_DIR}/cis_certs.zip"
  msg_success "[$(pad " cis-api" 20)] Downloaded cis api ssl certificates (zip) ..."

  [ ! -d "${VOLUMES_FOLDER}/cis/certs" ] && mkdir -p "${VOLUMES_FOLDER}/cis/certs"               &&
  busybox unzip "${WORKING_DIR}/cis_certs.zip" -o -d "${VOLUMES_FOLDER}/cis/certs" >             \
  "$WORKING_DIR/deployment_logs/cis_certs_unzip.log" 2>&1      
  msg_success "[$(pad " cis-api" 20)] Uncompressed cis api ssl certificates (zip) file ..." 

  grep -qi "${IP_ADDRESS} cis-api.certscan.net" /etc/hosts                                       ||
  printf '%s' "\n${IP_ADDRESS} cis-api.certscan.net\n" &>> /etc/hosts 
  msg_success "[$(pad " cis-api" 20)] domain name [cis-api.certscan.net] added to local host file ..." 
  
  msg && msg_important                                                                                  \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} cis-api.certscan.net )${NOFORMAT}" \
  "\nto dns server or host file, so [cis api] can be accessed at:"                                      \
  "\n☛ ${UCYAN}https://cis-api.certscan.net:34351${NOFORMAT}" && msg

  DB_CONN='Server=postgres;Port=5432;User Id=postgres;Password=postgres;Database=cis-api'
  # shellcheck disable=SC2016
  CERT_PASSWORD='!@OnDem@ndPa$$$$1234'
  
} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  #### CIS SUB-STACK #####################################################################################
  #####
  cis-ui:
    image: ${sbom_config_map[cis.cis-ui]}
    container_name: cis-ui
    restart: always
    environment:
      - CIS_API_ENDPOINT=https://cis-api.certscan.net:34351
      - CIS_NOTIFICATION_HUB=https://cis-api.certscan.net:34351/api/notificationhub
    ports:
      - "34352:80"
    networks:
      cis_backend:
        aliases:
          - cismgmt.certscan.net
    healthcheck:
      test: wget -O- -S http://127.0.0.1:80 3>&2 2>&1 1>&3 >/dev/null | grep "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      - cis-api
  ####
  ####
  cis-api:
    image: ${sbom_config_map[cis.cis-api]}
    container_name: cis-api
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/cis/certs:/cis/certs"
      - "${VOLUMES_FOLDER}/cis/archive:/cis/storage:rw"
      - "${VOLUMES_FOLDER}/cis/logs:/cis/logs:rw"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - App__DataSettings__DataConnectionString=${DB_CONN}
      - App__SSL__KeyPath=/cis/certs/certscan.net.encrypted.key
      - App__SSL__KeyPass=${CERT_PASSWORD}
      - Kestrel__Certificates__Default__Path=/cis/certs/certscan.net.pfx
      - Kestrel__Certificates__Default__Password=${CERT_PASSWORD}
      - App__EnableCors=true 
      - App__AllowedHosts=http://cismgmt.certscan.net:34352
      - Serilog__MinimumLevel__Default=Debug
      - Serilog__WriteTo__1__Args__path=/cis/logs/cis-api-std-.log
      - Serilog__WriteTo__2__Args__path=/cis/logs/cis-api-err-.log
      - App__EventBus__Uri=amqp://rabbitmq:5672
      - App__EventBus__UserName=guest
      - App__EventBus__Password=guest
      - App__InstallSampleData=true
      - App__StorageConfig__Type=1
      - App__StorageConfig__AmazonFsxConfig__SharedFolderNetworkPath=/cis/storage
      - App__SSL__UseSSL=false
      - App__SSL__OnlineCert=false
      - App__SSL__CrtPath=/cis/certs/certscan.net.crt
      - App__GrpcConfig__CertscanServerEndpoint__Host=http://converter
      - App__GrpcConfig__CertscanServerEndpoint__Port=7090
      - App__WebSocketConfig__BaseUrl=http://csview:8088/csview
      - App__WebSocketConfig__EnableSSL=True
      - App__WebSocketConfig__UserName=username
      - App__WebSocketConfig__Password=password
      - App__AIService__AIEndpoint=http://localhost:1880/api/v1/external/predict
      - App__AIService__ModelName=Test
      - Kestrel__Endpoints__http__Url=http://*:34350
      - Kestrel__Endpoints__https__Url=https://*:34351
      - Kestrel__Endpoints__grpc__Url=https://*:5003
    ports:
      - "34350:34350"
      - "34351:34351"
      - "5003:5003"
    networks:
      cs_backend:
      cis_backend:
        aliases:
          - cis-api.certscan.net
    healthcheck:
      test: wget -O- -S "https://cis-api.certscan.net:34351/swagger/index.html" 3>&2 2>&1 1>&3 >/dev/null | grep "200 OK" || exit 1
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      postgres:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
  ####
  ####
  cis-ps-m60-01:
    image: ${sbom_config_map[cis.cis-ps]}
    container_name: cis-ps-m60-01
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/cis/logs:/cis/logs:rw"
    environment:
      - AppConfig__ServiceId=cacc3948-2934-4ce0-a8f2-b96d228510ce # <-- CHANGE IT FROM CIS
      - AppConfig__CisWebApiEndpoints__Prod__Host=https://cis-api.certscan.net
      - AppConfig__CisWebApiEndpoints__Prod__GrpcPort=5003
      - ASPNETCORE_ENVIRONMENT=Development
      - Serilog__MinimumLevel__Default=Debug
      - Serilog__WriteTo__1__Args__path=/cis/logs/cis-ps-m60-01-std-.log
      - Serilog__WriteTo__2__Args__path=/cis/logs/cis-ps-m60-01-err-.log
      - AppConfig__EventBus__Uri=amqp://rabbitmq:5672
      - AppConfig__EventBus__UserName=guest
      - AppConfig__EventBus__Password=guest
    networks:
      - cs_backend
      - cis_backend
    depends_on:
      cis-api:
        condition: service_started
      rabbitmq:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " cis-ui" 20)] added to compose: [ $COMPOSE_FILE ]" &&
msg_success "[$(pad " cis-api" 20)] added to compose: [ $COMPOSE_FILE ]" &&
msg_success "[$(pad " cis-ps-m60-01" 20)] added to compose: [ $COMPOSE_FILE ]" 

##################################################################################################
##### CIS EMULATOR ###############################################################################
##################################################################################################

### EMU SUB STACK
[ -z "${sbom_config_map[emulator.emu-scans-path]-}" ] && {
   error 'EMU sub-stack could not be generated, if "emu-api" is specified, "emu-scans-path" will be mandatory'
} || 
[ -n "${sbom_config_map[emulator.emu-ui]-}" ]  &&
[ -n "${sbom_config_map[emulator.emu-api]-}" ] && {

  msg
  msg '############################################################################################'
  msg '#### EMULATOR SUB-STACK ####################################################################'
  msg '############################################################################################'
  msg
  
  grep -qi "${IP_ADDRESS} emumgmt.certscan.net" /etc/hosts                                       ||
  printf '%s' "\n${IP_ADDRESS} emumgmt.certscan.net\n" &>> /etc/hosts 
  msg_success "[$(pad " cis-ps-emu-ui" 20)] domain name [emumgmt.certscan.net] added to local host file ..." 

  msg && msg_important                                                                                  \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} emumgmt.certscan.net )${NOFORMAT}" \
  "\nto dns server or host file, so [emu ui] can be accessed at:"                                       \
  "\n☛ ${UCYAN}http://emumgmt.certscan.net:35351${NOFORMAT}" && msg

  local SCANS_ZIP_FILE="${WORKING_DIR}/${TENNANT}_scans.zip"                               &&
  [ ! -f "$SCANS_ZIP_FILE" ]                                                               &&
  dld_s3_obj "$S3_BUCKET" "${sbom_config_map[emulator.emu-scans-path]}" "$SCANS_ZIP_FILE"
  msg_success "[$(pad " cis-ps-emu-api" 20)] Downloaded emulator scans demo package (zip) ..."

  local SCANS_CONTAINER="${TENNANT}_scans"                                                  &&
  local SCANS_FOLDER="${VOLUMES_FOLDER}/emu/storage/${SCANS_CONTAINER}"                     && 
  [ ! -d "${SCANS_FOLDER}" ] && mkdir -p "${SCANS_FOLDER}"                                  &&
  busybox unzip "$SCANS_ZIP_FILE" -o -d "$SCANS_FOLDER" >                                   \
  "$WORKING_DIR/deployment_logs/${SCANS_CONTAINER}_unzip.log" 2>&1      
  msg_success "[$(pad " cis-ps-emu-api" 20)] Uncompresed emulator scans demo package (zip) into it's volume ..."

  grep -qi "${IP_ADDRESS} emu-api.certscan.net" /etc/hosts                                       ||
  printf '%s' "\n${IP_ADDRESS} emu-api.certscan.net\n" &>> /etc/hosts 
  msg_success "[$(pad " cis-ps-emu-api" 20)] domain name [emu-api.certscan.net] added to local host file ..." 

  msg && msg_important                                                                                  \
  "FOR REMOTE ACCESS: Please add entry \n☛ ${BGREEN}( ${IP_ADDRESS} emu-api.certscan.net )${NOFORMAT}" \
  "\nto dns server or host file, so [emu api] can be accessed at:"                                      \
  "\n☛ ${UCYAN}http://emu-api.certscan.net:35350${NOFORMAT}" && msg

} && tee -a "$COMPOSE_FILE" <<EOF > /dev/null &&
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUAL MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  #### CIS SUB-STACK #####################################################################################
  ####
  cis-ps-emu-ui:
    image: ${sbom_config_map[emulator.emu-ui]}
    container_name: cis-ps-emu-ui
    restart: always
    environment:
      - DEBUG=TRUE
      - API_URL=http://emu-api.certscan.net:35350
    ports:
      - "35351:80"
    networks:
      cis_backend:
        aliases:
          - emumgmt.certscan.net
    healthcheck:
      test: wget -O- -S http://127.0.0.1:80 3>&2 2>&1 1>&3 >/dev/null | grep "200 OK" || exit 1 
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      - cis-ps-emu-api
  ####
  ####
  cis-ps-emu-api:
    image: ${sbom_config_map[emulator.emu-api]}
    container_name: cis-ps-emu-api
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/emu/storage:/app/emu-storage:rw"
      - "${VOLUMES_FOLDER}/emu/logs:/app/logs:rw"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - Serilog__MinimumLevel__Default=Debug
      - Serilog__WriteTo__1__Args__path=/app/logs/cis-ps-emu-api-std-.log
      - App__EventBus__Uri=amqp://rabbitmq:5672
      - App__EventBus__UserName=guest
      - App__EventBus__Password=guest
      - App__AllowedHosts="http://emumgmt.certscan.net:35351,http://${IP_ADDRESS}:35351"
      - App__CorsAllowOrigins="http://emumgmt.certscan.net:35351,http://${IP_ADDRESS}:35351"
      - App__StorageConfig__AmazonFsxConfig__SharedFolderNetworkPath=/app/emu-storage
      - App__StorageConfig__Container=${SCANS_CONTAINER}
    ports:
      - "35350:35350"
    networks:
      cs_backend:
      cis_backend:
        aliases:
          - emu-api.certscan.net
    healthcheck:
      test: wget -O- -S "http://emu-api.certscan.net:35350/index.html" 3>&2 2>&1 1>&3 >/dev/null | grep "200 OK" || exit 1
      #start_period: 20s
      interval: 20s
      timeout: 5s
      retries: 20
    depends_on:
      rabbitmq:
        condition: service_healthy
  ####
EOF
msg_success "[$(pad " cis-ps-emu-ui" 20)] added to compose: [ $COMPOSE_FILE ]" &&
msg_success "[$(pad " cis-ps-emu-api" 20)] added to compose: [ $COMPOSE_FILE ]"

##################################################################################################

msg && msg "DONE!" && msg 
  sed -i '/^[[:space:]]*$/d' "$COMPOSE_FILE" 
  return 0

}
#endregion

composeUp() { 
  
  LOG="$WORKING_DIR/deployment_logs/compose-up.log"
  printf '' > "$LOG"

  msg
  msg '######################################################################################################'
  msg "#### COMPOSE UP START / LOG: [${LOG}]"
  msg '######################################################################################################'
  msg

  tput sc && docker compose -f "${COMPOSE_FILE}" up -d  2>&1 | {
    
    total_lines=10 && current_line=1
    
    while IFS= read -r line; do 
      [ "$current_line" -gt $total_lines ] && {
        current_line=1 && tput rc && tput dl $total_lines 
      }
      #Your processing logic here 
      echo "$line" | tee -a "$LOG"
      current_line=$((current_line+1)) 
    done
    
    tput rc && tput dl "$current_line"
   
  }
  
  #tee "$WORKING_DIR/deployment_logs/compose-up.log" && sleep 3; 
  
  msg
  msg '######################################################################################################'
  msg '#### COMPOSE UP END ##################################################################################'
  msg '######################################################################################################'
  msg
}

composeDown() { 
  
  LOG="$WORKING_DIR/deployment_logs/compose-down.log"

  msg
  msg '#######################################################################################################'
  msg "#### COMPOSE DOWN START / LOG: [${LOG}]"
  msg '#######################################################################################################'
  msg
  
  tput sc && docker compose -f "${COMPOSE_FILE}" down  2>&1 | {
    
    total_lines=10 && current_line=1
    
    while IFS= read -r line; do 
      [ "$current_line" -gt $total_lines ] && {
        current_line=1 && tput rc && tput dl $total_lines 
      }
      #Your processing logic here 
      echo "$line" | tee -a "$LOG"
      current_line=$((current_line+1)) 
    done
    
    tput rc && tput dl "$current_line"
   
  }
  #tee "$WORKING_DIR/deployment_logs/compose-up.log" && sleep 3; 
  
  msg
  msg '#######################################################################################################'
  msg '#### COMPOSE DOWN END #################################################################################'
  msg '#######################################################################################################'
  msg
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
      -g | --generate-compose)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
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
      -t | --tag)
          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

          [[ -z "${2-}" ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-t, --tag) option, tag (string) is expected"

          INSTALL_TAG="${2-}"
          shift
          ;;
      -h | --help) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          help && exit 
          ;; 
      -v | --version) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          version && exit 
          ;; 
      -e | --encrypt)
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          openssl aes-128-cbc -k "solutions@123" -e -pbkdf2 -iter 100 -a -salt < "$(basename "${BASH_SOURCE[0]}")" > \
          "$(basename "${BASH_SOURCE[0]}")".aes && exit 0
        
          # decrypt --> cat deploy-certscan-docker-X.Y.Z.sh.aes | \
          # openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k "solutions@123" > \
          # deploy-certscan-docker-X.Y.Z.sh
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

  [[ "${args[*]}" == *"-c"* ]] || [[ "${args[*]}" == *"--config-file"* ]] && {

    parseIniFileToMap "${CONFIG_FILE-}"
    # DEBUG echo "###" && declare -p sbom_config_map | sed 's/\[/\n\[/g;' | sed 's/)/\n)/g;' && echo "###"
  
  }
  
  [[ "${args[*]}" == *"-g"* ]] || [[ "${args[*]}" == *"--generate-compose"* ]] && {

    unset AWS_ACCESS_KEY_ID && unset AWS_SECRET_ACCESS_KEY                                &&
    aws ecr get-login-password                                                            \
      --profile default                                                                   \
      --region "$(aws configure get region)" | docker login                               \
        --password-stdin "585953033457.dkr.ecr.$(aws configure get region).amazonaws.com" \
        --username AWS &> "$WORKING_DIR/deployment_logs/aws_auth.log"                     && 
    msg && msg_success "Docker logged in to aws ecr successfuly"
  
    [[ "${args[*]}" != *"-c"* ]] && [[ "${args[*]}" != *"--config-file"* ]] &&
    fail " ${RED}[ERROR]${NOFORMAT} With (-g, --generate-compose) option, option -c/--config-file is required"

    createFoldersAndCompose
  }

  [[ "${args[*]}" == *"-u"* ]] || [[ "${args[*]}" == *"--undo-deploy"* ]] && {

    [[ "${args[*]}" != *"-c"* ]] && [[ "${args[*]}" != *"--config-file"* ]] && 
    fail " ${RED}[ERROR]${NOFORMAT} With (-u, --undo-deploy) option, option -c/--config-file is required"

    [ ! -f "${COMPOSE_FILE}" ] &&
    fail " ${RED}[ERROR]${NOFORMAT} (-u | --undo-deploy) ${COMPOSE_FILE} could not be found, try (-g) option"
  
    composeDown
  }
  
  [[ "${args[*]}" == *"-d"* ]] || [[ "${args[*]}" == *"--deploy"* ]] && {
  
    [[ "${args[*]}" != *"-c"* ]] && [[ "${args[*]}" != *"--config-file"* ]] && 
    fail " ${RED}[ERROR]${NOFORMAT} With (-u, --undo-deploy) option, option -c/--config-file is required"

    [ ! -f "${COMPOSE_FILE}" ] &&
    fail " ${RED}[ERROR]${NOFORMAT} (-u | --undo-deploy) ${COMPOSE_FILE} could not be found, try (-g) option"

    composeUp
  }
  
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
