-- FOOD-102 insert_test_data(value)
-- можно вызывать сколько угодно раз подряд, каждый вызов добавляет новую порцию данных

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.insert_test_data(value int)
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    c_street_kinds text[] := ARRAY['ул.', 'пр-т', 'пер.', 'б-р', 'наб.'];
    c_streets      text[] := ARRAY['Ленина', 'Мира', 'Советская', 'Гагарина', 'Садовая',
                                   'Лесная', 'Школьная', 'Молодёжная', 'Пушкина', 'Кирова',
                                   'Зелёная', 'Центральная', 'Победы', 'Строителей'];
    c_letters      text[] := ARRAY['', '', '', 'А', 'Б', 'В'];
    c_categories   text[] := ARRAY['Пицца', 'Суши', 'Бургеры', 'Супы', 'Салаты', 'Десерты',
                                   'Напитки', 'Паста', 'Завтраки', 'Шашлык', 'Выпечка', 'Вок'];
    c_dishes       text[] := ARRAY['борщ', 'пицца', 'ролл', 'бургер', 'салат', 'суп', 'стейк',
                                   'паста', 'пельмени', 'блины', 'плов', 'лагман', 'чизкейк'];
    c_adjectives   text[] := ARRAY['Домашний', 'Острый', 'Фирменный', 'Сытный', 'Лёгкий',
                                   'Классический', 'Пикантный', 'Нежный'];
    c_rest_words   text[] := ARRAY['Вкусно', 'Самовар', 'Пельменная', 'Солнце', 'Терраса',
                                   'Уголок', 'Огонёк', 'Дача', 'Восток', 'Причал'];
    c_surnames_m   text[] := ARRAY['Иванов', 'Петров', 'Сидоров', 'Смирнов', 'Кузнецов', 'Попов'];
    c_names_m      text[] := ARRAY['Иван', 'Пётр', 'Алексей', 'Дмитрий', 'Сергей', 'Олег'];
    c_patron_m     text[] := ARRAY['Иванович', 'Петрович', 'Сергеевич', 'Олегович'];
    c_surnames_f   text[] := ARRAY['Иванова', 'Петрова', 'Сидорова', 'Смирнова', 'Кузнецова'];
    c_names_f      text[] := ARRAY['Анна', 'Мария', 'Ольга', 'Елена', 'Татьяна', 'Наталья'];
    c_patron_f     text[] := ARRAY['Ивановна', 'Петровна', 'Сергеевна', 'Олеговна'];
    c_comments     text[] := ARRAY['Позвонить за 10 минут', 'Без лука', 'Домофон не работает',
                                   'Оставить у двери', 'Побольше салфеток', 'Без комментариев'];
    c_reviews      text[] := ARRAY['Очень вкусно!', 'Привезли быстро', 'Блюдо остыло',
                                   'Всё отлично', 'Порция маленькая', 'Закажу ещё', 'Средне'];

    v_window_start date := date_trunc('month', current_date - interval '5 months')::date;

    v_category_ids   uuid[] := '{}';
    v_courier_ids    uuid[] := '{}';
    v_courier_hire   date[] := '{}';
    v_courier_fire   date[] := '{}';
    v_address_ids    uuid[] := '{}';
    v_restaurant_ids uuid[] := '{}';
    v_client_ids     uuid[] := '{}';
    v_product_ids    uuid[] := '{}';
    v_product_prices numeric[] := '{}';
    v_order_ids      uuid[] := '{}';
    v_order_clients  uuid[] := '{}';
    v_order_rests    uuid[] := '{}';
    v_order_done_ts  timestamp[] := '{}';
    v_item_start     int[] := '{}';
    v_item_cnt       int[] := '{}';
    v_items          uuid[] := '{}';


    v_id        uuid;
    v_total     numeric;
    i int; j int; k int;
    v_c int; v_r int; v_k int;   -- клиент, ресторан, курьер (номера в массивах)
    v_status    courier_status;
    v_rstatus   restaurant_status;
    v_prstatus  product_status;
    v_active_rests   int[] := '{}';
    v_product_avail  boolean[] := '{}';
    v_avail          int[];      -- что можно заказать в выбранном ресторане
    v_delivered      int[] := '{}';
    v_hire      date;
    v_fire      date;
    v_male      boolean;
    v_ws        time;
    v_lo        timestamp;
    v_hi        timestamp;
    v_ts        timestamp;
    v_dts       timestamp;
    v_ostatus   order_status;
    v_pstatus   payment_status;
    v_paystatus order_pay_status;
    v_n int; v_off int;
    v_qty       numeric[];
    v_q         numeric;
    v_amount    numeric;
    v_etype     review_entity_type;
    v_entity    uuid;
    v_attempts  int;
    v_month     date;
    v_cnt       bigint[];
    v_comm      numeric[];
    v_coef      numeric[];
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'insert_test_data: value должно быть >= 1 (получено %)', value;
    END IF;

    -- категории. название с числом, чтобы не упираться в unique при повторных вызовах
    FOR i IN 1 .. value LOOP
        LOOP
            INSERT INTO product_category (product_category_id, product_category_name)
            VALUES (exts.uuid_generate_v4(),
                    c_categories[1 + floor(random() * array_length(c_categories, 1))::int]
                    || ' ' || (1 + floor(random() * 999999))::int)
            ON CONFLICT DO NOTHING
            RETURNING product_category_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
        END LOOP;
        v_category_ids := v_category_ids || v_id;
    END LOOP;


    -- курьеры. первый всегда работает - нужен хотя бы один активный (BR-6.6)
    FOR i IN 1 .. value LOOP
        IF i = 1 THEN
            v_status := 'свободен';
        ELSE
            v_status := (enum_range(NULL::courier_status))
                [1 + floor(random() * cardinality(enum_range(NULL::courier_status)))::int];
        END IF;

        v_hire := v_window_start
                  + floor(random() * ((current_date - 7) - v_window_start + 1))::int;
        v_fire := CASE WHEN v_status = 'уволен'
                       THEN v_hire + floor(random() * (current_date - v_hire + 1))::int
                  END;
        v_male := random() < 0.5;

        INSERT INTO courier (courier_id, fio, phone_number, status,
                             hire_date, dismissal_date, coefficient)
        VALUES (exts.uuid_generate_v4(),
                CASE WHEN v_male THEN
                     c_surnames_m[1 + floor(random() * array_length(c_surnames_m, 1))::int] || ' ' ||
                     c_names_m   [1 + floor(random() * array_length(c_names_m, 1))::int]    || ' ' ||
                     c_patron_m  [1 + floor(random() * array_length(c_patron_m, 1))::int]
                ELSE
                     c_surnames_f[1 + floor(random() * array_length(c_surnames_f, 1))::int] || ' ' ||
                     c_names_f   [1 + floor(random() * array_length(c_names_f, 1))::int]    || ' ' ||
                     c_patron_f  [1 + floor(random() * array_length(c_patron_f, 1))::int]
                END,
                '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
                v_status, v_hire, v_fire, 0.1)
        RETURNING courier_id INTO v_id;

        v_courier_ids  := v_courier_ids  || v_id;
        v_courier_hire := v_courier_hire || v_hire;
        v_courier_fire := v_courier_fire || v_fire;
    END LOOP;


    -- адреса: первые value для ресторанов, остальные клиентам
    FOR i IN 1 .. value * 5 LOOP
        LOOP
            INSERT INTO address (address_id, street, house_number, apartment_office)
            VALUES (exts.uuid_generate_v4(),
                    c_street_kinds[1 + floor(random() * array_length(c_street_kinds, 1))::int] || ' ' ||
                    c_streets     [1 + floor(random() * array_length(c_streets, 1))::int],
                    (1 + floor(random() * 200))::int ||
                    c_letters[1 + floor(random() * array_length(c_letters, 1))::int],
                    CASE
                        WHEN random() < 0.4 THEN NULL      -- частный дом
                        WHEN i <= value THEN 'оф. ' || (1 + floor(random() * 50))::int
                        ELSE (1 + floor(random() * 300))::int::text
                    END)
            ON CONFLICT DO NOTHING
            RETURNING address_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
        END LOOP;
        v_address_ids := v_address_ids || v_id;
    END LOOP;


    -- рестораны
    FOR i IN 1 .. value LOOP
        v_ws := time '07:00' + floor(random() * 9) * interval '30 minutes';
        -- заказывать будем только в активные, так что первый пусть всегда будет активным
        v_rstatus := CASE WHEN i = 1 THEN 'активен'::restaurant_status
                          ELSE (enum_range(NULL::restaurant_status))
                               [1 + floor(random() * cardinality(enum_range(NULL::restaurant_status)))::int]
                     END;

        INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description,
                                work_start, work_end, company_details, rating, status)
        VALUES (exts.uuid_generate_v4(),
                'Ресторан «' || c_rest_words[1 + floor(random() * array_length(c_rest_words, 1))::int] || '»',
                v_address_ids[i],
                'Кухня: ' || c_categories[1 + floor(random() * array_length(c_categories, 1))::int],
                v_ws,
                v_ws + interval '8 hours' + floor(random() * 9) * interval '30 minutes',
                'ИНН '     || lpad(floor(random() * 1e10)::bigint::text, 10, '0') ||
                ', ОГРН '  || lpad(floor(random() * 1e13)::bigint::text, 13, '0') ||
                ', р/с 40702810' || lpad(floor(random() * 1e12)::bigint::text, 12, '0'),
                NULL,               -- рейтинг поставлю в конце
                v_rstatus)
        RETURNING restaurant_id INTO v_id;

        v_restaurant_ids := v_restaurant_ids || v_id;
        IF v_rstatus = 'активен' THEN
            v_active_rests := v_active_rests || i;
        END IF;
    END LOOP;


    -- клиенты. логин и телефон уникальные, если вдруг совпало - пробуем ещё раз
    FOR i IN 1 .. value LOOP
        LOOP
            INSERT INTO client (client_id, login, password, phone_number)
            VALUES (exts.uuid_generate_v4(),
                    'user_' || substr(md5(random()::text), 1, 4 + floor(random() * 9)::int),
                    md5(random()::text),
                    '+7' || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'))
            ON CONFLICT DO NOTHING
            RETURNING client_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
        END LOOP;
        v_client_ids := v_client_ids || v_id;
    END LOOP;


    -- каждому клиенту по 4 своих адреса, плюс иногда чужой (общий адрес допустим)
    FOR k IN 1 .. value * 4 LOOP
        INSERT INTO client_address (client_id, address_id)
        VALUES (v_client_ids[1 + (k - 1) % value], v_address_ids[value + k]);
    END LOOP;

    FOR i IN 1 .. value LOOP
        IF random() < 0.3 THEN
            INSERT INTO client_address (client_id, address_id)
            VALUES (v_client_ids[i],
                    v_address_ids[value + 1 + floor(random() * value * 4)::int])
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;


    -- блюда: по 5 на ресторан, блюдо i -> ресторан (i-1) % value + 1
    -- первое блюдо у каждого ресторана всегда доступно, иначе может оказаться нечего заказать
    FOR i IN 1 .. value * 5 LOOP
        v_amount := round((150 + random() * 1350)::numeric, -1);
        v_prstatus := CASE WHEN i <= value THEN 'доступно'::product_status
                           ELSE (enum_range(NULL::product_status))
                                [1 + floor(random() * cardinality(enum_range(NULL::product_status)))::int]
                      END;

        INSERT INTO product (product_id, product_name, product_category_id, price,
                             restaurant_id, photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(),
                c_adjectives[1 + floor(random() * array_length(c_adjectives, 1))::int] || ' ' ||
                c_dishes    [1 + floor(random() * array_length(c_dishes, 1))::int],
                v_category_ids[1 + floor(random() * value)::int],
                v_amount,
                v_restaurant_ids[1 + (i - 1) % value],
                CASE WHEN random() < 0.3 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg'
                END,
                NULL,
                v_prstatus,
                'Состав и описание: ' || c_dishes[1 + floor(random() * array_length(c_dishes, 1))::int])
        RETURNING product_id INTO v_id;

        v_product_ids    := v_product_ids    || v_id;
        v_product_prices := v_product_prices || v_amount;
        v_product_avail  := v_product_avail  || (v_prstatus = 'доступно');
    END LOOP;


    -- заказы
    FOR i IN 1 .. value * 5 LOOP
        v_c := 1 + floor(random() * value)::int;
        v_r := v_active_rests[1 + floor(random() * cardinality(v_active_rests))::int];
        v_k := 1 + floor(random() * value)::int;

        -- время заказа - пока курьер работал (между наймом и увольнением)

        v_lo := v_courier_hire[v_k] + time '08:00';
        v_hi := least(localtimestamp - interval '2 hours',
                      coalesce(v_courier_fire[v_k] + time '22:00', 'infinity'::timestamp));
        v_ts := date_trunc('second', v_lo + random() * (v_hi - v_lo));


        -- каждый нечетный заказ точно доставлен. отзывы пишем только на доставленные,
        -- и так их всегда хватит даже при value=1
        IF i % 2 = 1 THEN
            v_ostatus := 'доставлен';
        ELSIF v_courier_fire[v_k] IS NOT NULL THEN
            v_ostatus := CASE WHEN random() < 0.85 THEN 'доставлен' ELSE 'отменён' END;
        ELSIF random() < 0.6 THEN
            v_ostatus := 'доставлен';
        ELSE
            v_ostatus := (enum_range(NULL::order_status))
                [1 + floor(random() * cardinality(enum_range(NULL::order_status)))::int];
        END IF;


        v_dts := CASE WHEN v_ostatus = 'доставлен'
                      THEN v_ts + (20 + floor(random() * 71)) * interval '1 minute'
                 END;


        -- в заказ кладём только доступные блюда этого ресторана (архив и "нет в наличии" не берём)
        v_avail := '{}';
        FOR j IN 0 .. 4 LOOP
            IF v_product_avail[v_r + value * j] THEN
                v_avail := v_avail || (v_r + value * j);
            END IF;
        END LOOP;

        v_n   := 1 + floor(random() * cardinality(v_avail))::int;
        v_off := floor(random() * cardinality(v_avail))::int;
        v_qty := '{}';
        v_amount := 0;
        v_item_start := v_item_start || (coalesce(array_length(v_items, 1), 0) + 1);
        v_item_cnt   := v_item_cnt   || v_n;

        FOR j IN 0 .. v_n - 1 LOOP
            k   := v_avail[1 + (v_off + j) % cardinality(v_avail)];
            v_q := CASE WHEN random() < 0.1 THEN 0.5
                        ELSE 1 + floor(random() * 3) END;
            v_items  := v_items || v_product_ids[k];
            v_qty    := v_qty || v_q;
            v_amount := v_amount + v_product_prices[k] * v_q;
        END LOOP;


        -- меньше 1000 с комиссией нельзя (BR-1.8), докидываем первое блюдо пока не наберётся
        WHILE v_amount + round(v_amount * 0.10, 2) < 1000 LOOP
            v_qty[1] := v_qty[1] + 1;
            v_amount := v_amount + v_product_prices[v_avail[1 + v_off]];
        END LOOP;


        -- если заказ уже готовят или везут - значит он оплачен
        IF v_ostatus IN ('доставлен', 'в_доставке', 'готовится') THEN
            v_pstatus := 'успех';
        ELSE
            v_pstatus := (enum_range(NULL::payment_status))
                [1 + floor(random() * cardinality(enum_range(NULL::payment_status)))::int];
        END IF;
        v_paystatus := CASE v_pstatus WHEN 'успех'  THEN 'оплачен'
                                      WHEN 'ошибка' THEN 'ошибка'
                                      ELSE 'ожидает' END;

        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                             order_timestamp, delivery_timestamp, order_amount,
                             status, pay_status, description)
        VALUES (exts.uuid_generate_v4(),
                v_courier_ids[v_k],
                v_client_ids[v_c],
                -- один из 4 адресов этого клиента
                v_address_ids[value + v_c + value * floor(random() * 4)::int],
                v_restaurant_ids[v_r],
                v_ts, v_dts, round(v_amount, 2),
                v_ostatus, v_paystatus,
                c_comments[1 + floor(random() * array_length(c_comments, 1))::int])
        RETURNING order_id, total_amount INTO v_id, v_total;

        FOR j IN 1 .. v_n LOOP
            INSERT INTO order_structure (order_id, product_id, quantity)
            VALUES (v_id, v_items[v_item_start[i] + j - 1], v_qty[j]);
        END LOOP;


        LOOP
            INSERT INTO payment (payment_id, order_id, payment_type, amount,
                                 transaction_ref, payment_timestamp, status)
            VALUES (exts.uuid_generate_v4(), v_id,
                    (enum_range(NULL::payment_type))
                        [1 + floor(random() * cardinality(enum_range(NULL::payment_type)))::int],
                    v_total,
                    'TXN-' || upper(substr(md5(random()::text), 1, 24)),
                    v_ts + floor(random() * 10) * interval '1 minute',
                    v_pstatus)
            ON CONFLICT DO NOTHING
            RETURNING payment_id INTO v_entity;
            EXIT WHEN v_entity IS NOT NULL;
        END LOOP;

        v_order_ids     := v_order_ids     || v_id;
        v_order_clients := v_order_clients || v_client_ids[v_c];
        v_order_rests   := v_order_rests   || v_restaurant_ids[v_r];
        v_order_done_ts := v_order_done_ts || coalesce(v_dts, v_ts);
        IF v_ostatus = 'доставлен' THEN
            v_delivered := v_delivered || i;
        END IF;
    END LOOP;


    -- отзывы. случайно может выпасть то, на что уже есть отзыв (unique), тогда просто пробуем снова
    i := 0;
    v_attempts := 0;
    WHILE i < value * 5 LOOP
        v_attempts := v_attempts + 1;
        IF v_attempts > value * 500 THEN
            RAISE EXCEPTION 'insert_test_data: не удалось сгенерировать отзывы';
        END IF;

        k := v_delivered[1 + floor(random() * cardinality(v_delivered))::int];
        v_etype := (enum_range(NULL::review_entity_type))
            [1 + floor(random() * cardinality(enum_range(NULL::review_entity_type)))::int];
        v_entity := CASE v_etype
                        WHEN 'заказ'    THEN v_order_ids[k]
                        WHEN 'ресторан' THEN v_order_rests[k]
                        ELSE v_items[v_item_start[k] + floor(random() * v_item_cnt[k])::int]
                    END;

        INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type,
                            order_id, description, photo_url, rating)
        VALUES (exts.uuid_generate_v4(),
                v_order_clients[k],
                least(localtimestamp,
                      v_order_done_ts[k] + (1 + floor(random() * 72)) * interval '1 hour'),
                v_entity, v_etype, v_order_ids[k],
                c_reviews[1 + floor(random() * array_length(c_reviews, 1))::int],
                CASE WHEN random() < 0.5 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/review/' || md5(random()::text) || '.jpg'
                END,
                1 + floor(random() * 5)::int)
        ON CONFLICT DO NOTHING
        RETURNING review_id INTO v_id;

        IF v_id IS NOT NULL THEN
            i := i + 1;
        END IF;
    END LOOP;


    -- рейтинги считаю тут сама, через rating_change в генераторе нельзя (samples п.10)
    UPDATE product p
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM review r
          WHERE r.entity_type = 'блюдо' AND r.entity_id = ANY (v_product_ids)
          GROUP BY r.entity_id) s
    WHERE p.product_id = s.entity_id;

    UPDATE restaurant rs
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM review r
          WHERE r.entity_type = 'ресторан' AND r.entity_id = ANY (v_restaurant_ids)
          GROUP BY r.entity_id) s
    WHERE rs.restaurant_id = s.entity_id;


    -- courier_pay за 6 месяцев, по тем же правилам что в courier_salary:
    -- платим по коэффициенту текущего месяца, а по числу доставок считаем коэффициент на следующий
    v_coef := array_fill(0.1::numeric, ARRAY[value]);

    FOR j IN 0 .. 5 LOOP
        v_month := (v_window_start + make_interval(months => j))::date;

        SELECT array_agg(t.cnt ORDER BY t.ord), array_agg(t.comm ORDER BY t.ord)
        INTO v_cnt, v_comm
        FROM (SELECT c.ord,
                     count(o.order_id)              AS cnt,
                     coalesce(sum(o.commission), 0) AS comm
              FROM unnest(v_courier_ids) WITH ORDINALITY AS c(courier_id, ord)
              LEFT JOIN "order" o
                     ON o.courier_id = c.courier_id
                    AND o.status = 'доставлен'
                    AND o.order_timestamp >= v_month
                    AND o.order_timestamp <  v_month + interval '1 month'
              GROUP BY c.ord) t;

        FOR k IN 1 .. value LOOP
            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (extract(year FROM v_month)::int,
                    extract(month FROM v_month)::int,
                    v_courier_ids[k],
                    round(v_coef[k] * v_comm[k], 2),
                    v_coef[k]);

            -- уволенному новый коэффициент не ставим
            IF v_courier_fire[k] IS NULL
               OR v_courier_fire[k] >= (v_month + interval '1 month')::date THEN
                v_coef[k] := CASE WHEN v_cnt[k] <= 150 THEN 0.1
                                  WHEN v_cnt[k] <= 250 THEN 0.2
                                  WHEN v_cnt[k] <= 500 THEN 0.3
                                  ELSE 0.5 END;
            END IF;
        END LOOP;
    END LOOP;

    UPDATE courier c
    SET coefficient = least(x.coef, 0.5)
    FROM unnest(v_courier_ids, v_coef) AS x(courier_id, coef)
    WHERE c.courier_id = x.courier_id;

    RAISE NOTICE 'insert_test_data(%): добавлено клиентов %, курьеров %, ресторанов %, заказов %',
        value, value, value, value, value * 5;
END;
$$;
