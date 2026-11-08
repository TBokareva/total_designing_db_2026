-- FOOD-109 пользователь inspector
-- запускать под postgres в той базе куда восстановили бэкап:
--   psql -U postgres -d <база> -f db/schema/grants.sql
-- повторный запуск ничего не ломает

-- у create role нет if not exists, поэтому так
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END
$$;
-- на случай если роль уже была с другим паролем
ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';

-- имя базы заранее не знаю, поэтому через format
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO inspector', current_database());
END
$$;

-- права на схему сами по себе не дают доступ к таблицам, поэтому отдельно на всё
GRANT ALL PRIVILEGES ON SCHEMA bokareva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA bokareva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bokareva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA bokareva_food TO inspector;

-- типы
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT t.typname
             FROM pg_type t
             JOIN pg_namespace n ON n.oid = t.typnamespace
             WHERE n.nspname = 'bokareva_food' AND t.typtype = 'e'
    LOOP
        EXECUTE format('GRANT ALL PRIVILEGES ON TYPE bokareva_food.%I TO inspector', r.typname);
    END LOOP;
END
$$;

-- и на то что создадут потом
ALTER DEFAULT PRIVILEGES IN SCHEMA bokareva_food GRANT ALL PRIVILEGES ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA bokareva_food GRANT ALL PRIVILEGES ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA bokareva_food GRANT ALL PRIVILEGES ON ROUTINES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA bokareva_food GRANT ALL PRIVILEGES ON TYPES TO inspector;

-- exts нужен для uuid_generate_v4
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA exts TO inspector;

-- вообще это и так есть у всех через PUBLIC, но на всякий случай явно
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog         TO inspector;

-- чтобы после входа не писать каждый раз set search_path
ALTER ROLE inspector SET search_path = bokareva_food, exts, public;
