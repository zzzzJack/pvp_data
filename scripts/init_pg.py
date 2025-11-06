import psycopg2


SQL_CREATE_ROLE = """
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='app') THEN
    CREATE ROLE app LOGIN PASSWORD 'app';
  END IF;
END$$;
"""

SQL_CREATE_DB = """
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname='pvp') THEN
    CREATE DATABASE pvp OWNER app;
  END IF;
END$$;
"""


def main():
    conn = psycopg2.connect(dbname='postgres', user='postgres')
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(SQL_CREATE_ROLE)
        cur.execute(SQL_CREATE_DB)
        cur.execute("ALTER ROLE app CREATEDB;")
    conn.close()
    print("PostgreSQL role/db prepared.")


if __name__ == '__main__':
    main()


