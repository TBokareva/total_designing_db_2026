-- FOOD-101 таблицы
-- почему стоит то или иное ограничение - см constraints.md

SET search_path TO bokareva_food, exts;

-- адреса (BR-3.x)
CREATE TABLE bokareva_food.address (
    address_id       uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    street           varchar(100) NOT NULL,
    house_number     varchar(10)  NOT NULL,
    apartment_office varchar(10)  NULL,            -- у частного дома квартиры нет
    CONSTRAINT address_pk PRIMARY KEY (address_id),
    CONSTRAINT address_street_not_blank_chk CHECK (btrim(street) <> ''),
    CONSTRAINT address_house_not_blank_chk  CHECK (btrim(house_number) <> ''),
    CONSTRAINT address_apartment_not_blank_chk
        CHECK (apartment_office IS NULL OR btrim(apartment_office) <> '')
);

-- один и тот же адрес не должен лежать двумя строками, иначе два ресторана
-- спокойно поделят адрес и UNIQUE в restaurant не поможет (BR-3.3)
-- coalesce - потому что NULL-ы в уникальном индексе считаются разными
CREATE UNIQUE INDEX address_physical_uq
    ON bokareva_food.address (street, house_number, COALESCE(apartment_office, ''));


-- клиенты BR-2
CREATE TABLE bokareva_food.client (
    client_id    uuid        NOT NULL DEFAULT exts.uuid_generate_v4(),
    login        varchar(50) NOT NULL,
    password     char(32)    NOT NULL,             -- md5 всегда 32 символа
    phone_number char(12)    NOT NULL,             -- +7 и 10 цифр
    CONSTRAINT client_pk PRIMARY KEY (client_id),
    CONSTRAINT client_login_uq UNIQUE (login),
    CONSTRAINT client_phone_uq UNIQUE (phone_number),
    CONSTRAINT client_login_not_blank_chk CHECK (btrim(login) <> ''),
    CONSTRAINT client_password_md5_chk    CHECK (password ~ '^[0-9a-f]{32}$'),
    CONSTRAINT client_phone_format_chk    CHECK (phone_number ~ '^\+7[0-9]{10}$')
);


-- связь клиент-адрес, многие ко многим
CREATE TABLE bokareva_food.client_address (
    client_id  uuid NOT NULL,
    address_id uuid NOT NULL,
    -- ключ на пару, чтобы один адрес не привязали клиенту два раза (BR-2.5)
    CONSTRAINT client_address_pk PRIMARY KEY (client_id, address_id),
    CONSTRAINT client_address_client_fk FOREIGN KEY (client_id)
        REFERENCES bokareva_food.client (client_id) ON DELETE CASCADE,
    CONSTRAINT client_address_address_fk FOREIGN KEY (address_id)
        REFERENCES bokareva_food.address (address_id) ON DELETE RESTRICT
);
CREATE INDEX client_address_address_idx ON bokareva_food.client_address (address_id);


-- рестораны
CREATE TABLE bokareva_food.restaurant (
    restaurant_id   uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id      uuid         NOT NULL,
    description     text         NOT NULL,
    work_start      time         NOT NULL,
    work_end        time         NOT NULL,
    company_details text         NOT NULL,
    rating          numeric(3,2) NULL,             -- нет отзывов - нет рейтинга
    status          bokareva_food.restaurant_status NOT NULL DEFAULT 'активен',
    CONSTRAINT restaurant_pk PRIMARY KEY (restaurant_id),
    CONSTRAINT restaurant_address_uq UNIQUE (address_id),
    CONSTRAINT restaurant_address_fk FOREIGN KEY (address_id)
        REFERENCES bokareva_food.address (address_id) ON DELETE RESTRICT,
    CONSTRAINT restaurant_name_not_blank_chk    CHECK (btrim(restaurant_name) <> ''),
    CONSTRAINT restaurant_details_not_blank_chk CHECK (btrim(company_details) <> ''),
    CONSTRAINT restaurant_work_hours_chk        CHECK (work_end > work_start),
    CONSTRAINT restaurant_rating_chk            CHECK (rating BETWEEN 0 AND 5)
);


-- курьеры
CREATE TABLE bokareva_food.courier (
    courier_id     uuid         NOT NULL DEFAULT exts.uuid_generate_v4(),
    fio            varchar(150) NOT NULL,
    phone_number   char(12)     NOT NULL,
    status         bokareva_food.courier_status NOT NULL DEFAULT 'свободен',
    hire_date      date         NOT NULL DEFAULT current_date,
    dismissal_date date         NULL,              -- пока работает - пусто
    coefficient    numeric(3,2) NOT NULL DEFAULT 0.1,  -- новичкам 0.1 (BR-6.5)
    CONSTRAINT courier_pk PRIMARY KEY (courier_id),
    CONSTRAINT courier_fio_not_blank_chk  CHECK (btrim(fio) <> ''),
    CONSTRAINT courier_phone_format_chk   CHECK (phone_number ~ '^\+7[0-9]{10}$'),
    CONSTRAINT courier_coefficient_chk    CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CONSTRAINT courier_dismissed_has_date_chk
        CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT courier_dismissal_after_hire_chk
        CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);


-- зарплата курьеров по месяцам
CREATE TABLE bokareva_food.courier_pay (
    year             smallint      NOT NULL,
    month            smallint      NOT NULL,
    courier_id       uuid          NOT NULL,
    amount           numeric(12,2) NOT NULL,
    coefficient_used numeric(3,2)  NOT NULL,
    -- на курьера одна запись в месяц, BR-10.3
    CONSTRAINT courier_pay_pk PRIMARY KEY (year, month, courier_id),
    CONSTRAINT courier_pay_courier_fk FOREIGN KEY (courier_id)
        REFERENCES bokareva_food.courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT courier_pay_month_chk       CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT courier_pay_amount_chk      CHECK (amount >= 0),
    CONSTRAINT courier_pay_coefficient_chk CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);
CREATE INDEX courier_pay_courier_idx ON bokareva_food.courier_pay (courier_id);


-- категории блюд, просто справочник
CREATE TABLE bokareva_food.product_category (
    product_category_id   uuid        NOT NULL DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(50) NOT NULL,
    CONSTRAINT product_category_pk PRIMARY KEY (product_category_id),
    CONSTRAINT product_category_name_uq UNIQUE (product_category_name),
    CONSTRAINT product_category_name_not_blank_chk CHECK (btrim(product_category_name) <> '')
);


-- блюда
CREATE TABLE bokareva_food.product (
    product_id          uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    product_name        varchar(100)  NOT NULL,
    product_category_id uuid          NOT NULL,
    price               numeric(10,2) NOT NULL,
    restaurant_id       uuid          NOT NULL,
    photo_url           text          NULL,        -- фото может не быть
    rating              numeric(3,2)  NULL,        -- считает триггер, без отзывов NULL
    status              bokareva_food.product_status NOT NULL DEFAULT 'доступно',
    description         text          NOT NULL,
    CONSTRAINT product_pk PRIMARY KEY (product_id),
    CONSTRAINT product_category_fk FOREIGN KEY (product_category_id)
        REFERENCES bokareva_food.product_category (product_category_id) ON DELETE RESTRICT,
    CONSTRAINT product_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES bokareva_food.restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT product_name_not_blank_chk CHECK (btrim(product_name) <> ''),
    CONSTRAINT product_price_chk          CHECK (price >= 0),
    CONSTRAINT product_rating_chk         CHECK (rating BETWEEN 0 AND 5),
    CONSTRAINT product_photo_not_blank_chk CHECK (photo_url IS NULL OR btrim(photo_url) <> '')
);
CREATE INDEX product_restaurant_idx ON bokareva_food.product (restaurant_id);
CREATE INDEX product_category_idx   ON bokareva_food.product (product_category_id);


-- заказы. имя в кавычках - order зарезервировано, переименовывать не стала
CREATE TABLE bokareva_food."order" (
    order_id           uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    courier_id         uuid          NOT NULL,
    client_id          uuid          NOT NULL,
    address_id         uuid          NOT NULL,
    restaurant_id      uuid          NOT NULL,
    order_timestamp    timestamp     NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp     NULL,         -- заполняется когда доставили
    order_amount       numeric(12,2) NOT NULL,
    -- комиссия 10% и итог считает сама база, руками их не записать (BR-1.4, 7.10)
    commission         numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount       numeric(12,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,
    status             bokareva_food.order_status     NOT NULL DEFAULT 'создан',
    pay_status         bokareva_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description        text          NOT NULL,
    CONSTRAINT order_pk PRIMARY KEY (order_id),
    CONSTRAINT order_courier_fk FOREIGN KEY (courier_id)
        REFERENCES bokareva_food.courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT order_client_fk FOREIGN KEY (client_id)
        REFERENCES bokareva_food.client (client_id) ON DELETE RESTRICT,
    CONSTRAINT order_address_fk FOREIGN KEY (address_id)
        REFERENCES bokareva_food.address (address_id) ON DELETE RESTRICT,
    CONSTRAINT order_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES bokareva_food.restaurant (restaurant_id) ON DELETE RESTRICT,
    -- доставлять можно только на свой адрес (BR-7.4) - поэтому fk сразу на пару в client_address
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES bokareva_food.client_address (client_id, address_id) ON DELETE RESTRICT,
    -- эти два нужны только как цель для составных fk из review и payment
    CONSTRAINT order_client_uq UNIQUE (order_id, client_id),
    CONSTRAINT order_total_uq  UNIQUE (order_id, total_amount),
    CONSTRAINT order_amount_positive_chk CHECK (order_amount > 0),
    CONSTRAINT order_min_total_chk       CHECK (total_amount >= 1000),
    CONSTRAINT order_delivery_after_create_chk
        CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT order_delivered_has_time_chk
        CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL),
    CONSTRAINT order_description_not_blank_chk CHECK (btrim(description) <> '')
);
CREATE INDEX order_courier_idx    ON bokareva_food."order" (courier_id);
CREATE INDEX order_client_idx     ON bokareva_food."order" (client_id, address_id);
CREATE INDEX order_restaurant_idx ON bokareva_food."order" (restaurant_id);
CREATE INDEX order_status_ts_idx  ON bokareva_food."order" (status, order_timestamp);


-- состав заказа
CREATE TABLE bokareva_food.order_structure (
    order_id   uuid         NOT NULL,
    product_id uuid         NOT NULL,
    quantity   numeric(8,3) NOT NULL,              -- бывает 0.5 кг, поэтому не int
    -- одно блюдо в заказе один раз, иначе увеличиваем количество (BR-7.16)
    CONSTRAINT order_structure_pk PRIMARY KEY (order_id, product_id),
    CONSTRAINT order_structure_order_fk FOREIGN KEY (order_id)
        REFERENCES bokareva_food."order" (order_id) ON DELETE CASCADE,
    CONSTRAINT order_structure_product_fk FOREIGN KEY (product_id)
        REFERENCES bokareva_food.product (product_id) ON DELETE RESTRICT,
    CONSTRAINT order_structure_quantity_chk CHECK (quantity > 0)
);
CREATE INDEX order_structure_product_idx ON bokareva_food.order_structure (product_id);


-- попытки оплаты
CREATE TABLE bokareva_food.payment (
    payment_id        uuid          NOT NULL DEFAULT exts.uuid_generate_v4(),
    order_id          uuid          NOT NULL,
    payment_type      bokareva_food.payment_type   NOT NULL,
    amount            numeric(12,2) NOT NULL,
    -- id от платёжки это строка а не uuid, поэтому назвала _ref а не _id
    transaction_ref   varchar(64)   NOT NULL,
    payment_timestamp timestamp     NOT NULL DEFAULT localtimestamp,
    status            bokareva_food.payment_status NOT NULL DEFAULT 'в_обработке',
    CONSTRAINT payment_pk PRIMARY KEY (payment_id),
    CONSTRAINT payment_order_fk FOREIGN KEY (order_id)
        REFERENCES bokareva_food."order" (order_id) ON DELETE RESTRICT,
    -- сумма попытки должна совпасть с суммой заказа (BR-8.4)
    CONSTRAINT payment_order_amount_fk FOREIGN KEY (order_id, amount)
        REFERENCES bokareva_food."order" (order_id, total_amount) ON DELETE RESTRICT,
    CONSTRAINT payment_transaction_uq UNIQUE (transaction_ref),
    CONSTRAINT payment_transaction_not_blank_chk CHECK (btrim(transaction_ref) <> '')
);
CREATE INDEX payment_order_idx ON bokareva_food.payment (order_id);
-- успешная оплата у заказа может быть только одна (BR-8.1)
CREATE UNIQUE INDEX payment_one_success_uq
    ON bokareva_food.payment (order_id) WHERE status = 'успех';


-- отзывы
-- entity_id ссылается то на блюдо, то на ресторан, то на заказ, обычный fk тут не поставить,
-- проверяю триггером review_entity_check в 03_triggers.sql
CREATE TABLE bokareva_food.review (
    review_id        uuid      NOT NULL DEFAULT exts.uuid_generate_v4(),
    client_id        uuid      NOT NULL,
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id        uuid      NOT NULL,
    entity_type      bokareva_food.review_entity_type NOT NULL,
    order_id         uuid      NOT NULL,
    description      text      NOT NULL,
    photo_url        text      NULL,
    rating           smallint  NOT NULL,
    CONSTRAINT review_pk PRIMARY KEY (review_id),
    CONSTRAINT review_client_fk FOREIGN KEY (client_id)
        REFERENCES bokareva_food.client (client_id) ON DELETE RESTRICT,
    CONSTRAINT review_order_fk FOREIGN KEY (order_id)
        REFERENCES bokareva_food."order" (order_id) ON DELETE RESTRICT,
    -- писать отзыв может только тот кто заказывал (BR-9.2)
    CONSTRAINT review_order_client_fk FOREIGN KEY (order_id, client_id)
        REFERENCES bokareva_food."order" (order_id, client_id) ON DELETE RESTRICT,
    -- на каждый объект в заказе максимум один отзыв, BR-9.5
    CONSTRAINT review_one_per_entity_uq UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT review_rating_chk CHECK (rating BETWEEN 1 AND 5),
    -- отзыв на заказ - только на тот же заказ
    CONSTRAINT review_order_entity_chk CHECK (entity_type <> 'заказ' OR entity_id = order_id),
    CONSTRAINT review_description_not_blank_chk CHECK (btrim(description) <> ''),
    CONSTRAINT review_photo_not_blank_chk CHECK (photo_url IS NULL OR btrim(photo_url) <> '')
);
CREATE INDEX review_entity_idx ON bokareva_food.review (entity_type, entity_id);
CREATE INDEX review_client_idx ON bokareva_food.review (order_id, client_id);
