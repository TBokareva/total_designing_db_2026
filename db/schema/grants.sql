-- FOOD-109 пользователь inspector
-- Бэкап восстанавливается в базу foodexpress_bokareva (по имени файла бэкапа), права выдаются
-- на неё. Запускать под postgres, подключившись к этой базе:
--   psql -U postgres -d foodexpress_bokareva -f db/schema/grants.sql

-- Создаю роль, только если её ещё нет. Если inspector уже существует, её не трогаю:
-- пароль и другие настройки чужой учётной записи скрипт менять не должен.
-- У CREATE ROLE нет IF NOT EXISTS, поэтому проверка в DO-блоке; без неё повторный
-- запуск падал бы с ошибкой "role already exists".
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END
$$;

-- права на ту базу, куда восстанавливается бэкап
GRANT CONNECT ON DATABASE foodexpress_bokareva TO inspector;

-- ALL PRIVILEGES на схему. Права на схему не дают доступа к объектам внутри неё,
-- поэтому отдельно на таблицы (вместе с представлением how_much_money) и процедуры/функции.
-- Последовательностей в схеме нет: все ключи uuid.
GRANT ALL PRIVILEGES ON SCHEMA bokareva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES   IN SCHEMA bokareva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA bokareva_food TO inspector;
-- На типы (enum) отдельно не выдаю: USAGE на типы по умолчанию есть у PUBLIC.

-- exts - для uuid_generate_v4 (AC). EXECUTE на функции по умолчанию есть у PUBLIC.
GRANT USAGE ON SCHEMA exts TO inspector;

-- USAGE на information_schema и pg_catalog требует AC FOOD-109: inspector должен читать
-- каталоги (проверки G.3, G.4). У PUBLIC это право есть по умолчанию, здесь оно выдаётся
-- именно inspector, как требует задание.
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog         TO inspector;
