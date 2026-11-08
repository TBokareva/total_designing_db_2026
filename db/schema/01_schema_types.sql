-- FOOD-101 схема и enum-типы
-- exts с uuid-ossp уже есть в базе (BR-13.3), тут её не создаю, только пользуюсь exts.uuid_generate_v4()

CREATE SCHEMA IF NOT EXISTS bokareva_food;

SET search_path TO bokareva_food, exts;

-- статусы ресторана BR-4.3
CREATE TYPE bokareva_food.restaurant_status AS ENUM ('активен', 'неактивен');

-- блюдо BR-5.5
CREATE TYPE bokareva_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');

-- курьер (BR-6.2)
CREATE TYPE bokareva_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');

-- заказ BR-7.7
CREATE TYPE bokareva_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');

-- общий статус оплаты у заказа, BR-7.9
CREATE TYPE bokareva_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');

-- статус отдельной попытки оплаты BR-8.2
CREATE TYPE bokareva_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');

-- тип оплаты висит на попытке, не на заказе (BR-8.2, 8.6)
CREATE TYPE bokareva_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');

-- на что отзыв BR-9.1
CREATE TYPE bokareva_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');
