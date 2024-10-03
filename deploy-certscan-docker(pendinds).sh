
# Stop all containers
docker stop `docker ps -qa` && docker rm `docker ps -qa`

# Remove all containers
docker rm `docker ps -qa`

# Remove all volumes
docker volume rm $(docker volume ls -q)

# Remove all networks
docker network rm `docker network ls -q`

# The following commands should not output any items:
docker ps -a
docker images -a 
docker volume ls
# The following command show only show the default networks:
docker network ls

docker ps --format '{{ .ID }}\t{{.Names}}\t{{ .Ports }}'

docker ps | perl -ne '@cols = split /\s{2,}/, $_; printf "%30s|%20s|%20s\n", $cols[0], $cols[6], $cols[5]' | column -t -s "|"

# Remove all images
docker rmi -f `docker images -qa`


############################################


# Stop all containers
docker stop `docker ps -qa` && docker rm `docker ps -qa`

# Remove all containers
docker rm `docker ps -qa`

# Remove all volumes
docker volume rm $(docker volume ls -q)

# Remove all networks
docker network rm `docker network ls -q`

docker rmi -f `docker images -qa`






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
