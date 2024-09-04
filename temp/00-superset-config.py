print("\n!!!!!!!!!!!!!!!!!!!!!!!!INIT SUPERSET_CONFIG.PY!!!!!!!!!!!!!!!!!!!!!!!!!")

SECRET_KEY = 'HWtMOvJRkUvqp/Wls1tZZaMZObWCtSXkTdPDzRCmrvEN6zWgpm3eHTzF'
TALISMAN_ENABLED = False
CONTENT_SECURITY_POLICY_WARNING = False

import os;

SQLALCHEMY_DATABASE_URI = f'{os.environ["SUPERSET_DB_ENGINE"]}://{os.environ["POSTGRES_USER"]}:{os.environ["POSTGRES_PASSWORD"]}@{os.environ["DATABASE_URL"]}/{os.environ["SUPERSET>

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
