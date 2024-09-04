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
