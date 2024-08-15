#!/bin/bash

cd "$SUPERSET_SCRIPTS"

tee "00-superset-config.py" <<EOF > /dev/null
print("\n!!!!!!!!!!!!!!!!!!!!!!!!INIT SUPERSET_CONFIG.PY!!!!!!!!!!!!!!!!!!!!!!!!!")

SECRET_KEY = 'HWtMOvJRkUvqp/Wls1tZZaMZObWCtSXkTdPDzRCmrvEN6zWgpm3eHTzF'
TALISMAN_ENABLED = False
CONTENT_SECURITY_POLICY_WARNING = False

import os;

SQLALCHEMY_DATABASE_URI = f'{os.environ["SUPERSET_DB_ENGINE"]}://{os.environ["POSTGRES_USER"]}:{os.environ["POSTGRES_PASSWORD"]}@{os.environ["DATABASE_URL"]}/{os.environ["SUPERSET_DB_NAME"]}'

####################################################################################

from flask import Flask, redirect, g, flash, request
from flask_appbuilder.security.views import UserDBModelView,AuthDBView
from superset.security import SupersetSecurityManager
from flask_appbuilder.security.views import expose
from flask_appbuilder.security.manager import BaseSecurityManager
from flask_login import login_user, logout_user

class CustomAuthDBView(AuthDBView):
    login_template = 'appbuilder/general/security/login_db.html'

    @expose('/login', methods=['GET', 'POST'])
    def login(self):
        return super(CustomAuthDBView,self).login()

    @expose('/login/', methods=['GET', 'POST'])
    def login(self):
        return super(CustomAuthDBView,self).login()

    @expose('/secret', methods=['GET', 'POST'])
    def secret(self):
        redirect_url = self.appbuilder.get_url_for_index
        if request.args.get('redirect') is not None:
            redirect_url = request.args.get('redirect')

        if request.args.get('username') is None:
            return redirect('login')
        else:
            user = self.appbuilder.sm.find_user(username=request.args.get('username'))
            login_user(user, remember=False)
            return redirect(redirect_url)

class CustomSecurityManager(SupersetSecurityManager):
    authdbview = CustomAuthDBView

    def __init__(self, appbuilder):
        super(CustomSecurityManager, self).__init__(appbuilder)

CUSTOM_SECURITY_MANAGER = CustomSecurityManager

print("\nTo access reports please navigate to:")
print("\nhttp(s)://<<superset ip or fqdn>>/secret?username=superadmin&redirect=/dashboard/list\n")

print("!!!!!!!!!!!!!!!!!!!!!!!!SUPERSET_CONFIG.PY DONE!!!!!!!!!!!!!!!!!!!!!!!!!\n")
EOF

tee "01-postgres-ready.py" <<EOF > /dev/null
#!/usr/local/bin/python3
import psycopg2; import os;
def do():
    try:
        pgconn = psycopg2.connect(
            connect_timeout=1,
            host=os.environ["DATABASE_URL"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"]
        )
        pgconn.close(); print("OK"); os._exit(os.EX_OK)
    except Exception as e:
        print(f"{type(e).__name__}: {e}"); os._exit(1)

do()
EOF

tee "02-superset-db-exists.py" <<EOF > /dev/null
#!/usr/local/bin/python3
import psycopg2; import os;
def do():
    try:
        pgconn = psycopg2.connect(
            connect_timeout=1,
            host=os.environ["DATABASE_URL"],
            dbname=os.environ["SUPERSET_DB_NAME"],
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"]
        )
        pgconn.close(); print("OK"); os._exit(os.EX_OK)
    except Exception as e:
        print(f"{type(e).__name__}: {e}"); os._exit(1)

do()
EOF

tee "03-create-superset-db.py" <<EOF > /dev/null
#!/usr/local/bin/python3
import psycopg2; import os;
def do():
    try:
        pgconn = psycopg2.connect(
            connect_timeout=1,
            host=os.environ["DATABASE_URL"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"]
        )
        pgconn.autocommit = True
        pgcurs = pgconn.cursor()
        pgcurs.execute('CREATE DATABASE ' + os.environ["SUPERSET_DB_NAME"])
        pgcurs.close()
        pgconn.close()

        SQLALCHEMY_DATABASE_URI = f'{os.environ["SUPERSET_DB_ENGINE"]}://{os.environ["POSTGRES_USER"]}:{os.environ["POSTGRES_PASSWORD"]}@{os.environ["DATABASE_URL"]}/{os.environ["SUPERSET_DB_NAME"]}'

        print("OK"); os._exit(os.EX_OK)
    except Exception as e:
        print(f"{type(e).__name__}: {e}")
        os._exit(1)

do()
EOF

chmod +x *

exec &> >(tee -a "/app/superset_home/logs/superset-$(date +"%Y%m%d").log") # TODO needs logs rotation

until python3 01-postgres-ready.py && printf "\n$(date +"%Y%m%d %H:%M:%S"): postgres already accepting connections ...\n\n"
do printf "\n$(date +"%Y%m%d %H:%M:%S"): Waiting for postgres to be ready ...\n"; sleep 5; done

if python3 02-superset-db-exists.py; then
printf "\n$(date +"%Y%m%d %H:%M:%S"): Superset initilized already. Starting...\n\n"
else
printf "\n$(date +"%Y%m%d %H:%M:%S"): creating superset postgres db ...\n\n"
python3 03-create-superset-db.py
printf "\n$(date +"%Y%m%d %H:%M:%S"): Migrating superset DB to latest...\n\n"
python3 02-superset-db-exists.py && superset db upgrade 2>&1
printf "\n$(date +"%Y%m%d %H:%M:%S"): Creating superset admin account...\n\n"
superset fab create-admin \
--username ${SUPERSET_USER} \
--password ${SUPERSET_PASSWORD} \
--firstname ${SUPERSET_USER} \
--lastname ${SUPERSET_USER}  \
--email ${SUPERSET_USER_EMAIL} 2>&1
printf "\n$(date +"%Y%m%d %H:%M:%S"): Initilizing superset...\n\n"
superset init 2>&1
printf "\n$(date +"%Y%m%d %H:%M:%S"): Superset has been succefully initialized, starting the server...\n\n"
fi

TXT="\033[0;30m"
BG="\033[47m"
RESET="\033[0m"

while :; do echo -en "\n${TXT}${BG}http(s)://<<superset ip or fqdn>>/secret?username=superadmin&redirect=/dashboard/list${RESET}\n\n" > /dev/stdout 2>&1; sleep 180; done &

/usr/bin/run-server.sh
