#!/usr/bin/env bash

# cat deploy-certscan-docker-1.0.0.sh | openssl aes-128-cbc -e -pbkdf2 -iter 100 -a -salt -k "solutions@123" > deploy-certscan-docker-1.0.0.sh.aes
# cat deploy-certscan-docker-1.0.0.sh.aes | openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k "solutions@123" > deploy-certscan-docker-1.0.0.sh.dec

### COMMON ##########################################################################################################################

set -Eeuo pipefail; trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

msg() { echo >&2 -e "${1-}"; }

msg_success() { msg "${GREEN}[\xE2\x9C\x94]${NOFORMAT} ${1-}"; }

msg_important() { msg "${GREEN}[! IMPORTANT]${NOFORMAT} ${1-}"; }

# default exit status 1
error() { local msg=$1; msg "${BRED}[! ERROR]${NOFORMAT} $msg"; } 
fail() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 
fatal() { local msg=$1; local code=${2-1}; echo; msg "${BRED}[! FATAL ERROR]${NOFORMAT} $msg"; usage; exit "$code"; } 

cleanup() { 
  trap - SIGINT SIGTERM ERR EXIT;
  # script cleanup here ########################
}

### LOGIC ###########################################################################################################################

test $? -eq 0 || fail "This script need root/sudo privilege to run"

CURRENT_BASH_VERSION=$(uname -r | cut -c1-3); VERSION_LIMIT=4.2;
if (( $(echo "$CURRENT_BASH_VERSION <= $VERSION_LIMIT" | bc -l) )); then
  fail "Current bash version is [${CURRENT_BASH_VERSION}], needs to be higher than [${VERSION_LIMIT}]"
fi

VERSION=1.0.0 # TODO integrate https://github.com/fmahnke/shell-semver/blob/master/increment_version.sh

version() {
  msg "${YELLOW}Version: ${VERSION}${NOFORMAT}" 
  msg
}

usage() {
  msg "${YELLOW}Usage: ./$(basename "${BASH_SOURCE[0]}") [-v] | [-h] | -c <<sbom.conf>> [ -u ] [ -d ] | -w ${NOFORMAT}" 
  msg 
}

help(){
  usage
  version 
  msg
  msg "Given <<sbom.conf>> (see format below), this script generates a docker compose file to  deploy"
  msg "a fully operative certscan docker stack (certscan+cis+emulator). Alse provide an API to manage"
  msg "it's deployment"
  msg
  msg "Available options:"
  msg "-h, --help                         | Prints this help and exit"
  msg "-v, --version                      | Displays the script version"
  msg "-c, --config-file  <<sbom.com>>    | Processes <<sbom.conf>> generating the docker compose and folder structure"
  msg "-d, --deploy                       | Deploys the generated compose file to docker (compose up)"
  msg "-u, --undo-deploy                  | Undoes the deployment (compoese down)"
  #msg "-w, --wipe-out                     | (ALERT! data loose) Completely eliminates deployment, compose, and folder structure"
  msg
  msg "Examples:"
  msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -u -d"
  msg "- ./deploy-certscan-docker.sh -c oman_4.3.3.conf -u"
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
  local response=$(aws s3api get-object --bucket "$bucket_name" --key "$object_name" "$destination_file_name") ||
  fail "AWS reports get-object operation failed.\n$response" $?
}

docker_cleanup(){
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
      cleanLine=$(echo "$line" | sed -e 's/\r//g'); 
      # echo $cleanLine # TODO debug

      echo "$cleanLine" | grep -qx '^#.*' && [ ${PIPESTATUS[1]} -eq 0 ] && 
      continue 

      echo "$cleanLine" | grep -qx '^\[.*\]' && [ ${PIPESTATUS[1]} -eq 0 ] && 
      currentSection=$(echo "$cleanLine" | tr -d "[]") 
      
      echo "$cleanLine" | grep -qx '.*=.*' && [ ${PIPESTATUS[1]} -eq 0 ] && {                             
        key=$currentSection.$(echo "$cleanLine" | awk -F: '{ st = index($0,"=");print  substr($0,0,st-1)}') 
        value=$(echo "$cleanLine" | awk -F: '{ st = index($0,"=");print  substr($0,st+1)}')                 
        sbom_config_map[$key]=$value
      }
  done < "$1"
  # echo "###" && declare -p sbom_config_map && echo "###" # debug
  return 0
}

declare -g S3_BUCKET='s2global-test-bucket'
declare -g IP_ADDRESS="$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)"
declare -g WORKING_DIR=''
declare -g VOLUMES_FOLDER='' 
declare -g COMPOSE_FILE=''  

createFoldersAndCompose(){  
  local PREFIX="${sbom_config_map[default.tennant]}_${sbom_config_map[default.cs-version]}_"
  
  WORKING_DIR="${script_dir}/${PREFIX}dkr_stack"; 
  VOLUMES_FOLDER="${WORKING_DIR}/${PREFIX}dkr_volumes" 
  COMPOSE_FILE="${WORKING_DIR}/${PREFIX}compose.yaml"
 
  mkdir -p "$WORKING_DIR" && msg_success "Created stack folder [$WORKING_DIR] ..."

  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  aws ecr get-login-password --profile default                                    \
  --region $(aws configure get region) |                                          \
  docker login                                                                    \
  --password-stdin 585953033457.dkr.ecr.$(aws configure get region).amazonaws.com \
  --username AWS 2>&1 >"$WORKING_DIR"/aws.error.log                               &&
  msg_success "Successfuly loged in to AWS ..."

  local RKIT_ZIP_FILE="${WORKING_DIR}/${PREFIX}rkit.zip" && [ ! -f "$RKIT_ZIP_FILE" ]  && 
  dld_s3_obj "$S3_BUCKET" "${sbom_config_map[default.rel-kit-path]}" "$RKIT_ZIP_FILE"  
  msg_success "Downloaded release kit (zip) with configs files ..."                    
  
  local RKIT_FOLDER="${WORKING_DIR}/${PREFIX}rkit" && [ ! -d "$RKIT_FOLDER" ]          &&
  mkdir -p "$RKIT_FOLDER"                                                              &&
  busybox unzip "$RKIT_ZIP_FILE" -o -d "$RKIT_FOLDER"  >"$WORKING_DIR"/${PREFIX}rkit_unzip.log       
  msg_success "Uncompresed release kit (zip) file ..."                                 
   
  [ ! -d "${VOLUMES_FOLDER}" ] && mkdir -p "${VOLUMES_FOLDER}/logs"
  msg_success "Created volumes folder ..."
  
  configs="$(for e in "$RKIT_FOLDER"/*; do [[ -d "$e" ]] && { echo "$e"; break; }; done)"                       &&
  cp -v -r -p -a "$configs"/certscan-docker/h* "$VOLUMES_FOLDER"  >"$WORKING_DIR"/cp.hap.log                    &&
  cp -v -r -p -a "$configs"/certscan-docker/r* "$VOLUMES_FOLDER"  >"$WORKING_DIR"/cp.res.log                    &&
  msg_success "Copying configs folders from release kit to volumes folder ..."
  
  tee "$COMPOSE_FILE" <<EOF > /dev/null
networks:
  cs_backend:
  cis_backend:
services: 
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
  redis:
    image: "${sbom_config_map[third-party.redis]}"
    container_name: redis
    restart: always
    ports:
      - "6379"
    environment:
      REDIS_PASSWORD: 'solutions@123'
    volumes:
      - "${VOLUMES_FOLDER}/dckr-vol-redis:/data"
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    command: /bin/sh -c 'redis-server --appendonly yes --requirepass $(printf '$${REDIS_PASSWORD}')'
  #### 
  rabbitmq:
    image: "${sbom_config_map[third-party.rabbitmq]}"
    container_name: rabbitmq
    restart: always
    hostname: rabbitmq-container
    ports:
      - "15672:15672" # <- UI
      - "5672:5672" 
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
  postgres:
    image: "${sbom_config_map[third-party.postgres]}"
    container_name: postgres
    restart: always
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
    command: -c 'max_connections=500'
    healthcheck:
      test: ["CMD-SHELL", "pg_isready"]
      interval: 10s
      timeout: 5s
      retries: 5
  
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
  flyway:
    image: "${sbom_config_map[certscan.flyway]}"
    container_name: db-migration-flyway
    environment:
      DATABASE_SCHEMA_LIST: "${sbom_config_map[default.tennant]}"
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
  certscanjobs:
    image: "${sbom_config_map[certscan.certscanjobs]}"
    container_name: cs-jobs
    restart: always
    environment:
      SCHEMAS: "${sbom_config_map[default.tennant]}"
    volumes:
      - "/etc/timezone:/etc/timezone:ro" 
      - "/etc/localtime:/etc/localtime:ro"
    networks:
      - cs_backend
    depends_on:
      flyway:
        condition: service_completed_successfully
  #### 
  pgweb-cs:
    image: "${sbom_config_map[third-party.pgweb]}"
    profiles: ["monitoring"] # docker compose -f ......./csV4-compose.yml --profiles monitoring up -d
    container_name: postgres-ui-cs-db
    restart: always
    ports: 
      - "5433:8081" 
    links: 
      - postgres:postgres  
    environment:
      - PGWEB_DATABASE_URL=postgres://postgres:postgres@postgres:5432/certscandb?sslmode=disable
    networks:
      - cs_backend
    depends_on:
      flyway:
        condition: service_completed_successfully
  
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
  discovery-service:
    image: "${sbom_config_map[certscan.discoveryservice]}"
    container_name: discovery-service
    restart: always
    ports:
      - "8761:8761"
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
  #### 
  configserver:
    image: "${sbom_config_map[certscan.configserver]}"
    container_name: configserver
    restart: always
    ports:
      - "8010:8010"
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
    depends_on:
      flyway:
        condition: service_completed_successfully
  #### 
  applicationconfiguration:
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
    depends_on:
      flyway:
        condition: service_completed_successfully
  
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
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
      - "8090"
      - "7090:7090"
    depends_on:
      flyway:
        condition: service_completed_successfully
  $(echo "####" && [ ! -z ${sbom_config_map[certscan.csview]-} ]                                         && 
  {
    msg ''
    msg_important \
    "Please add entry ${BGREEN}( ${IP_ADDRESS} wajajah.certscan.rop.gov.internal )${NOFORMAT} to dns server or host file"
    msg_important \
    "Then emulator may be accessed at: ${UBLUE}https://wajajah.certscan.rop.gov.internal/csview${NOFORMAT}"
    msg ''

    printf ''
  })
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
    ports:
      - "8080:8080"
      - "9001:9001"
    networks:
      cs_backend:
        aliases:
          - "wajajah.certscan.rop.gov.internal" # TODO  <-- add place holder   
    
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
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
    #ports:
      #- "8090:8099"
    networks:
      - cs_backend
    depends_on:
      flyway:
        condition: service_completed_successfully
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
    depends_on:
      flyway:
        condition: service_completed_successfully
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
          - "wajajah.certscan.rop.gov.internal"
    ports:
      - "8030"
    depends_on:
      flyway:
        condition: service_completed_successfully
  
  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION
  
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
    #ports:
    # - "9081:9081"
    depends_on:
      flyway:
        condition: service_completed_successfully
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
    depends_on:
      flyway:
        condition: service_completed_successfully
  ####
  haproxy:
    image: "${sbom_config_map[certscan.haproxy]}"
    container_name: haproxy
    restart: always
    volumes:
      - "${VOLUMES_FOLDER}/haproxy/:/usr/local/etc/haproxy"
      - "${VOLUMES_FOLDER}/haproxy/certs/:/etc/ssl/certs"
    ports:
      - "443:8443"
    networks:
      cs_backend:
        aliases:
          - "wajajah.certscan.rop.gov.internal"
    depends_on:
      - csview
      - workflow
      - cchelp
      - converter
    # - cis-api
  $([ ! -z ${sbom_config_map[certscan.irservice]-} ]                                          && 
  echo -en "#### optional container [irservice]                                               \n\
  irservice:                                                                                  \n\
    image: ${sbom_config_map[certscan.irservice]}                                             \n\
    container_name: irservice                                                                 \n\
    restart: always                                                                           \n\
    environment:                                                                              \n\
      SERVER_HOME: /home/Server                                                               \n\
    volumes:                                                                                  \n\
      - "${VOLUMES_FOLDER}/logs:/home/Server/logs:rw"                                         \n\
      - "${VOLUMES_FOLDER}/resources/properties:/home/properties"                             \n\
      - "${VOLUMES_FOLDER}/resources/Server:/home/Server"                                     \n\
      - "${VOLUMES_FOLDER}/logs:/home/irservice/logs:rw"                                      \n\
      - "/etc/timezone:/etc/timezone:ro"                                                      \n\
      - "/etc/localtime:/etc/localtime:ro"                                                    \n\
    ports:                                                                                    \n\
      - "9099:9099"                                                                           \n\
    networks:                                                                                 \n\
      - cs_backend                                                                            \n\
  ####                                                                                        \n\
  ")
  #-------------------------------------------------------------------------------------------------------#
  $([ ! -z ${sbom_config_map[cis.cis-api]-} ]                                                 &&
  { 
    CERT_PASSWORD='!@OnDem@ndPa$$$$1234'   
    DB_CONN='Server=postgres;Port=5432;User Id=postgres;Password=postgres;Database=cis-api' 
    
    [ -z ${sbom_config_map[cis.cis-cert-path]-} ]                                             && 
    error 'CIS sub-stack could not be deployed, if "cis-api" is specified, \
    "cis-cert-path" will be mandatory'                                                        && 
    echo  '# [!ERROR] CIS sub-stack could not be deployed, if "cis-api" is specified, \
    "cis-cert-path" will be mandatory'                                                        &&
    return 1 

    echo "#### CIS SUB-STACK ######################################################################################" 
    echo "  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION"

    [ ! -f "${WORKING_DIR}/cis_certs.zip" ]                                                   && 
    dld_s3_obj "$S3_BUCKET" "${sbom_config_map[cis.cis-cert-path]}" "${WORKING_DIR}/cis_certs.zip"
    msg_success "Downloaded cis api ssl certificates (zip) ..."
    
    [ ! -d "${VOLUMES_FOLDER}/cis/certs" ] && mkdir -p "${VOLUMES_FOLDER}/cis/certs"          &&
    busybox unzip "${WORKING_DIR}/cis_certs.zip" -o -d "${VOLUMES_FOLDER}/cis/certs" 2>&1 > "$WORKING_DIR"/cis_certs_unzip.log       
    msg_success "Uncompressed cis api ssl certificates (zip) file ..." 
    
    msg ''
    msg_important \
    "Please add entry ${BGREEN}( ${IP_ADDRESS} cis-api.certscan.net )${NOFORMAT} to dns server or host file"
    msg_important \
    "Then emulator may be accessed at: ${UBLUE}https://cis-api.certscan.net:34351${NOFORMAT}"
    msg '' 
    
    printf ''
  }                                                                                           &&
  echo -en "  #### optional container [cis-api]                                               \n\
  cis-api:                                                                                    \n\
    image: ${sbom_config_map[cis.cis-api]}                                                    \n\
    container_name: cis-api                                                                   \n\
    restart: always                                                                           \n\
    volumes:                                                                                  \n\
      - "${VOLUMES_FOLDER}/cis/certs:/cis/certs"                                              \n\
      - "${VOLUMES_FOLDER}/cis/archive:/cis/storage:rw"                                       \n\
      - "${VOLUMES_FOLDER}/cis/logs:/cis/logs:rw"                                             \n\
    environment:                                                                              \n\
      - ASPNETCORE_ENVIRONMENT=Development                                                    \n\
      - Serilog__MinimumLevel__Default=Debug                                                  \n\
      - Serilog__WriteTo__1__Args__path=/cis/logs/cis-api-std-.log                            \n\
      - Serilog__WriteTo__2__Args__path=/cis/logs/cis-api-err-.log                            \n\
      - App__EventBus__Uri=amqp://rabbitmq:5672                                               \n\
      - App__EventBus__UserName=guest                                                         \n\
      - App__EventBus__Password=guest                                                         \n\
      - DB_CONN=Server=postgres;Port=5432;User Id=postgres;Password=postgres;Database=cis-api \n\
      - App__DataSettings__DataConnectionString=${DB_CONN}                                    \n\
      - App__InstallSampleData=true                                                           \n\
      - App__StorageConfig__Type=1                                                            \n\
      - App__StorageConfig__AmazonFsxConfig__SharedFolderNetworkPath=/cis/storage             \n\
      - App__EnableCors=true                                                                  \n\
      - App__AllowedHosts=http://cismgmt.certscan.net:7000,http://10.4.4.205:7000             \n\
      - App__SSL__UseSSL=false                                                                \n\
      - App__SSL__OnlineCert=false                                                            \n\
      - App__SSL__CrtPath=/cis/certs/certscan.net.crt                                         \n\
      - App__SSL__KeyPath=/cis/certs/certscan.net.encrypted.key                               \n\
      - App__SSL__KeyPass=${CERT_PASSWORD}                                                    \n\
      - App__GrpcConfig__CertscanServerEndpoint__Host=http://converter                        \n\
      - App__GrpcConfig__CertscanServerEndpoint__Port=7090                                    \n\
      - App__WebSocketConfig__BaseUrl=http://csview:8088/csview                               \n\
      - App__WebSocketConfig__EnableSSL=True                                                  \n\
      - App__WebSocketConfig__UserName=username                                               \n\
      - App__WebSocketConfig__Password=password                                               \n\
      - App__AIService__AIEndpoint=http://localhost:1880/api/v1/external/predict              \n\
      - App__AIService__ModelName=Test                                                        \n\
      - Kestrel__Certificates__Default__Path=/cis/certs/certscan.net.pfx                      \n\
      - Kestrel__Certificates__Default__Password=${CERT_PASSWORD}                             \n\
      - Kestrel__Endpoints__http__Url=http://*:34350                                          \n\
      - Kestrel__Endpoints__https__Url=https://*:34351                                        \n\
      - Kestrel__Endpoints__grpc__Url=https://*:5003                                          \n\
    ports:                                                                                    \n\
      - "34350:34350"                                                                         \n\
      - "34351:34351"                                                                         \n\
      - "5003:5003"                                                                           \n\
    networks:                                                                                 \n\
      cs_backend:                                                                             \n\
      cis_backend:                                                                            \n\
        aliases:                                                                              \n\
          - cis-api.certscan.net                                                              \n\
    depends_on:                                                                               \n\
      postgres:                                                                               \n\
        condition: service_healthy                                                            \n\
      rabbitmq:                                                                               \n\
        condition: service_healthy                                                            \n\
  ####                                                                                        \n\
  "                                                                                           &&
  [ ! -z ${sbom_config_map[cis.cis-ui]-} ]                                                    &&
  {
    msg '' 
    msg_important \
    "Please add entry ${BGREEN}( ${IP_ADDRESS} cismgmt.certscan.net  )${NOFORMAT} to dns server or host file"
    msg_important \
    "Then emulator may be accessed at: ${UBLUE}http://cismgmt.certscan.net:7000${NOFORMAT}"
    msg '' && 
    printf ''
  }                                                                                           && 
  echo -en "#### optional container [cis-ui]                                                  \n\
  cis-ui:                                                                                     \n\
    image: ${sbom_config_map[cis.cis-ui]}                                                     \n\
    container_name: cis-ui                                                                    \n\
    restart: always                                                                           \n\
    environment:                                                                              \n\
      - CIS_API_ENDPOINT=https://cis-api.certscan.net:34351                                   \n\
      - CIS_NOTIFICATION_HUB=https://cis-api.certscan.net:34351/api/notificationhub           \n\
    ports:                                                                                    \n\
      - "7000:80"                                                                             \n\
    networks:                                                                                 \n\
      cis_backend:                                                                            \n\
        aliases:                                                                              \n\
          - cismgmt.certscan.net                                                              \n\
    depends_on:                                                                               \n\
      - cis-api                                                                               \n\
  ####                                                                                        \n\
  "                                                                                           &&
  [ ! -z ${sbom_config_map[cis.cis-ps]-} ]                                                    &&
  echo -en "#### optional container [cis-ps-m60-01]                                           \n\
  cis-ps-m60-01:                                                                              \n\
    image: ${sbom_config_map[cis.cis-ps]}                                                     \n\
    container_name: cis-ps-m60-01                                                             \n\
    restart: always                                                                           \n\
    volumes:                                                                                  \n\
      - "${VOLUMES_FOLDER}/cis/logs:/cis/logs:rw"                                             \n\
    environment:                                                                              \n\
      - ASPNETCORE_ENVIRONMENT=Development                                                    \n\
      - Serilog__MinimumLevel__Default=Debug                                                  \n\
      - Serilog__WriteTo__1__Args__path=/cis/logs/cis-ps-m60-01-std-.log                      \n\
      - Serilog__WriteTo__2__Args__path=/cis/logs/cis-ps-m60-01-err-.log                      \n\
      - AppConfig__EventBus__Uri=amqp://rabbitmq:5672                                         \n\
      - AppConfig__EventBus__UserName=guest                                                   \n\
      - AppConfig__EventBus__Password=guest                                                   \n\
      - AppConfig__ServiceId=cacc3948-2934-4ce0-a8f2-b96d228510ce                             \n\
      - AppConfig__CisWebApiEndpoints__Prod__Host=https://cis-api.certscan.net                \n\
      - AppConfig__CisWebApiEndpoints__Prod__GrpcPort=5003                                    \n\
    networks:                                                                                 \n\
      - cs_backend                                                                            \n\
      - cis_backend                                                                           \n\
    depends_on:                                                                               \n\
      cis-api:                                                                                \n\
        condition: service_started                                                            \n\
      rabbitmq:                                                                               \n\
        condition: service_healthy                                                            \n\
  ####                                                                                        \n\
  ")
  #-------------------------------------------------------------------------------------------------------#
  $([ ! -z ${sbom_config_map[emulator.emu-api]-} ]                                            &&
  {
    [ -z ${sbom_config_map[emulator.emu-scans-path]-} ]                                       && 
    error 'EMU sub-stack could not be generated, if "emu-api" is specified, "emu-scans-path" will be mandatory' && 
    echo  '# [!ERROR] EMU sub-stack could not be generated, if "cis-api" is specified, "cis-cert-path" will be mandatory' &&
    return 1                                                                                      
    
    echo "#### EMU SUB-STACK ######################################################################################" 
    echo "  #### !! THIS IS A GENERATED FILE FROM A TEMPLATE, MANUALY MODIFICATIONS WON'T PERSIST AFTER RE-GENERATION"

    local SCANS_ZIP_FILE="${WORKING_DIR}/${sbom_config_map[default.tennant]}_scans.zip"       &&  
    [ ! -f "$SCANS_ZIP_FILE" ]                                                                && 
    dld_s3_obj "$S3_BUCKET" "${sbom_config_map[emulator.emu-scans-path]}" "$SCANS_ZIP_FILE"  
    msg_success "Downloaded emulator scans demo (zip) ..."
    
    local SCANS_CONTAINER="${sbom_config_map[default.tennant]}_scans"                         &&
    local SCANS_FOLDER="${VOLUMES_FOLDER}/emu/storage/${SCANS_CONTAINER}"                     && 
    [ ! -d "${SCANS_FOLDER}" ] && mkdir -p "${SCANS_FOLDER}"                                  &&
    busybox unzip "$SCANS_ZIP_FILE" -o -d "$SCANS_FOLDER" 2>&1 >"$WORKING_DIR/${SCANS_CONTAINER}_unzip.log"      
    msg_success "Uncompresed emulator scans demo (zip) file into it's volume ..." 
    
    msg ''
    msg_important \
    "Please add entry ${BGREEN}( ${IP_ADDRESS} emu-api.certscan.net )${NOFORMAT} to dns server or host file"
    msg_important \
    "Then emulator may be accessed at: ${UBLUE}http://emu-api.certscan.net:35350${NOFORMAT}" 
    msg ''                                                                        

    printf ''                                      
  }                                                                                           &&
  echo -en "  #### optional container [cis-ps-emu-api]                                        \n\
  cis-ps-emu-api:                                                                             \n\
    image: ${sbom_config_map[emulator.emu-api]}                                               \n\
    container_name: cis-ps-emu-api                                                            \n\
    restart: always                                                                           \n\
    volumes:                                                                                  \n\
      - "${VOLUMES_FOLDER}/emu/storage:/app/emu-storage:rw"                                   \n\
      - "${VOLUMES_FOLDER}/emu/logs:/app/logs:rw"                                             \n\
    environment:                                                                              \n\
      - ASPNETCORE_ENVIRONMENT=Development                                                    \n\
      - Serilog__MinimumLevel__Default=Debug                                                  \n\
      - Serilog__WriteTo__1__Args__path=/app/logs/cis-ps-emu-api-std-.log                     \n\
      - App__EventBus__Uri=amqp://rabbitmq:5672                                               \n\
      - App__EventBus__UserName=guest                                                         \n\
      - App__EventBus__Password=guest                                                         \n\
      - App__AllowedHosts="http://emumgmt.certscan.net:8000,http://${IP_ADDRESS}:8000"        \n\
      - App__CorsAllowOrigins="http://emumgmt.certscan.net:8000,http://${IP_ADDRESS}:8000"    \n\
      - App__StorageConfig__AmazonFsxConfig__SharedFolderNetworkPath=/app/emu-storage         \n\
      - App__StorageConfig__Container=${SCANS_CONTAINER}                                      \n\
    ports:                                                                                    \n\
      - "35350:35350"                                                                         \n\
    networks:                                                                                 \n\
      cs_backend:                                                                             \n\
      cis_backend:                                                                            \n\
        aliases:                                                                              \n\
          - emu-api.certscan.net                                                              \n\
    depends_on:                                                                               \n\
      rabbitmq:                                                                               \n\
        condition: service_healthy                                                            \n\
  ####                                                                                        \n\
  "                                                                                           &&
  [ ! -z ${sbom_config_map[emulator.emu-ui]-} ]                                               &&
  {
    msg ''
    msg_important \
    "Please add entry ${BGREEN}( ${IP_ADDRESS} emumgmt.certscan.net )${NOFORMAT} to dns server or host file"
    msg_important \
    "Then emulator may be accessed at: ${UBLUE}http://emumgmt.certscan.net:8000${NOFORMAT}"
    msg ''
    
    printf ''
  }                                                                                           &&
  echo -en "#### optional container [cis-ps-emu-ui]                                           \n\
  cis-ps-emu-ui:                                                                              \n\
    image: ${sbom_config_map[emulator.emu-ui]}                                                \n\
    container_name: cis-ps-emu-ui                                                             \n\
    restart: always                                                                           \n\
    environment:                                                                              \n\
      - DEBUG=TRUE                                                                            \n\
      - API_URL=http://emu-api.certscan.net:35350                                             \n\
    ports:                                                                                    \n\
      - "8000:80"                                                                             \n\
    networks:                                                                                 \n\
      cis_backend:                                                                            \n\
        aliases:                                                                              \n\
          - emumgmt.certscan.net                                                              \n\
    depends_on:                                                                               \n\
      - cis-ps-emu-api                                                                        \n\
  ####                                                                                        \n\
  ")
  #-------------------------------------------------------------------------------------------------------#
    
EOF
  
  sed -i '/^[[:space:]]*$/d' "$COMPOSE_FILE"
  return 0
}

composeDown() { docker compose -f "${COMPOSE_FILE}" --profile monitoring down 2>undo_deployment.log && sleep 3; }

composeUp() { docker compose -f "${COMPOSE_FILE}" --profile monitoring up -d 2>deployment.log && sleep 3; }

parse_params() {
  args=("$@") && [[ ${#args[@]} -eq 0 ]] && fail "Missing script arguments, try (-h) option, to understand usage"
  
  while : ; do
    case "${1-}" in
    -h | --help) help && exit ;; 
    -v | --version) version && exit ;; 
    -c | --config-file) 
      [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] && 
      fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible" 

      [[ -z "${2-}" ]] && 
      fail " ${RED}[ERROR]${NOFORMAT} With (-c, --config-file) option, file path is expected"
      
      parseIniFileToMap "${2-}" &&  
      createFoldersAndCompose   &&
      shift 
      ;;
    -d | --deploy) 
      [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] && 
      fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

      # docker compose -f "${COMPOSE_FILE}" --profile monitoring up -d && sleep 3;
      ;;
    -u | --undo-deploy)
      [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] && 
      fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

      # docker compose -f "${COMPOSE_FILE}" --profile monitoring down && sleep 3;
      ;;
    -w | --wipe-out) fail "Option (-w | --wipe-out) no yet implemented";; 
    -?*) fail "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done                         

  [[ "${args[*]}" == *"-u"* ]] || [[ "${args[*]}" == *"--undo-deploy"* ]] && composeDown 
  [[ "${args[*]}" == *"-d"* ]] || [[ "${args[*]}" == *"--deploy"* ]]      && composeUp

  return 0
}

#backup
# cat ./$(basename "${BASH_SOURCE[0]}") |                                \
# openssl aes-128-cbc -e -pbkdf2 -iter 100 -a -salt -k "solutions@123" > \
# $(basename "${BASH_SOURCE[0]}").aes

#msg && 
parse_params "$@"

#####################################################################################################################################

# tennant=oman
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
