  pgadmin:
    container_name: pgadmin-http-5433
    image: dpage/pgadmin4
    ports:
      - 5433:80
    environment:
      PGADMIN_DEFAULT_EMAIL: superadmin@certscan.net
      PGADMIN_DEFAULT_PASSWORD: Test@123
      PGADMIN_SERVER_JSON_FILE: "/pgadmin4/servers/servers.json"
    volumes:
      - "/opt/certscan/<define>/pgadmin-servers:/pgadmin4/servers"
      - "/opt/certscan/<define>/pgadmin-db-backups:/mnt/backups"
    networks:
      - cs_backend

 servers.json: |
{
    "Servers": {
        "1": {
            "Group": "Servers",
            "Name": "postgres",
            "Host": "postgres",
            "Port": 5432,
            "MaintenanceDB": "postgres",
            "Username": "postgres",
            "Password": "postgres"
        }
    }
}

-----------------------------

  redisinsight:
    container_name: redis-mgmt-http-6380
    image: redislabs/redisinsight:1.14.0
    ports:
      - '6380:8001'
    volumes:
      - ${VOLUMES_FOLDER}/redisinsight:/data
    networks:
      - cs_backend

-----------------------------

  #redis-mgmt:
    # image: redislabs/redisinsight:1.14.0 # TODO <-- move to conf file third party
    # container_name: redis-mgmt-pt-6380
    # volumes:
    #   - ${VOLUMES_FOLDER}/redisinsight:/data
    # networks:
    #   - cs_backend
    # ports:
    #   - '6380:8001'

------------------------------

  mongo-mgmt:
    image: mongo-express # TODO <-- move to conf file third party
    container_name: mongo-mgmt-http-27018
    environment:
      ME_CONFIG_MONGODB_SERVER: mongodb
      ME_CONFIG_MONGODB_ADMINUSERNAME: admin
      ME_CONFIG_MONGODB_ADMINPASSWORD: admin
    networks:
      - cs_backend
    ports:
      - 27018:8081