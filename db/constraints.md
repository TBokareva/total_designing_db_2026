# Обоснование ограничений

Схема `bokareva_food`. Сам SQL лежит в `db/schema/02_tables.sql` и `03_triggers.sql`.
Ограничения названы явно (типа `order_min_total_chk`), так по тексту ошибки сразу понятно что нарушено.

---

## Enum-типы

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `'активен'`, `'неактивен'` | BR-4.3 |
| `product_status` | `'доступно'`, `'нет_в_наличии'`, `'архив'` | BR-5.5 |
| `courier_status` | `'свободен'`, `'занят'`, `'на_доставке'`, `'уволен'` | BR-6.2 |
| `order_status` | `'создан'`, `'готовится'`, `'в_доставке'`, `'доставлен'`, `'отменён'` | BR-7.7 |
| `order_pay_status` | `'ожидает'`, `'оплачен'`, `'ошибка'` | BR-7.9 |
| `payment_status` | `'успех'`, `'ошибка'`, `'в_обработке'` | BR-8.2 |
| `payment_type` | `'карта'`, `'наличные'`, `'безнал'` | BR-8.2 |
| `review_entity_type` | `'блюдо'`, `'ресторан'`, `'заказ'` | BR-9.1 |

Значения взяты из BR как есть, ничего не добавлено. Именно enum, а не varchar - этого требует BR-11.5.

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавлены в `payment` и почему** (BR-8.2):

```
payment_type       - тип оплаты (BR-8.2, BR-8.6)
amount             - сумма попытки, равна total_amount заказа (BR-8.4)
transaction_ref    - id транзакции от платёжного провайдера, уникальный (BR-8.3)
payment_timestamp  - когда была транзакция
status             - успех / ошибка / в_обработке

Данных карты нет совсем, только id транзакции (BR-1.7, BR-8.5).
transaction_ref, а не transaction_id - это не uuid, а строка от провайдера,
а _id - везде uuid-ключи (и проверка B.4 как раз ищет *_id не uuid).
```

**Где хранится тип оплаты — `payment` или `order`** (BR-8.6):

```
В payment. Клиент может начать платить картой, потом заплатить наличными -
у одного заказа получаются попытки разных типов. В order это не уложить.
```

Ещё по оплатам:

```
BR-8.4 сумма попытки = сумма заказа: составной FK
  payment(order_id, amount) -> "order"(order_id, total_amount)
  под него в "order" есть UNIQUE (order_id, total_amount). Сумму не ту база просто не примет.

BR-8.1 ровно одна успешная: частичный уникальный индекс
  UNIQUE (order_id) WHERE status = 'успех' - больше одной успешной не будет.
  "Хотя бы одну" схемой не гарантирую - только что созданный заказ ещё не оплачен
  (pay_status = 'ожидает'). В тестовых данных у всех готовящихся/едущих/доставленных
  заказов успешная оплата есть.
```

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

```
Составной FK:
  FOREIGN KEY (client_id, address_id) REFERENCES client_address (client_id, address_id)

То есть пара клиент+адрес из заказа обязана быть в client_address.
Ссылаюсь на PK client_address, отдельный unique не понадобился.
Триггер тут не нужен - FK проверяет и вставку, и update заказа, и не даст
удалить привязку адреса, пока на неё есть заказы (RESTRICT).
Обычные FK на client и address тоже оставила, они есть в ERD.
```

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

```
Триггер check_order_restaurant() на order_structure (before insert/update):
сравнивает ресторан заказа и ресторан блюда, если разные - ошибка.

Та же функция висит ещё на product и "order" (before update of restaurant_id),
иначе правило можно было бы обойти - поменять ресторан у блюда или заказа
уже после того как позиции добавлены.

Через составной FK не стала - пришлось бы добавить restaurant_id в order_structure,
а он зависит только от order_id, т.е. от части ключа. Это уже нарушение 2НФ.
```

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

```
Оставила полиморфизм entity_type + entity_id как в ERD (и rating_change в FOOD-105
описан как раз через них). Обычный FK на entity_id невозможен - он ссылается
на разные таблицы в зависимости от типа.

Что проверяет корректность:
1) FK review.order_id -> "order" и составной (order_id, client_id) -> "order":
   отзыв всегда к реальному заказу и от того клиента, который его делал (BR-9.2)
2) CHECK (entity_type <> 'заказ' OR entity_id = order_id) - отзыв на заказ = на свой заказ
3) триггер review_entity_check():
     ресторан - должен быть ресторан этого заказа
     блюдо    - должно быть в составе этого заказа
   это даже строже обычного FK: FK проверил бы только что блюдо существует,
   а тут - что клиент его реально заказывал
4) UNIQUE (order_id, entity_type, entity_id) - BR-9.5

Нормализацию (три nullable FK + check что заполнен один) рассматривала,
но триггер для BR-9.2 всё равно был бы нужен, а выигрыша почти никакого.

Есть одна дыра: если удалить позицию из заказа, на который уже есть отзыв,
отзыв останется. Но состав заказа после оформления по бизнесу не меняется,
поэтому отдельный триггер на это не делала.
```

---

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `restaurant` | `rating` | `rating BETWEEN 0 AND 5` | BR-4.2 | рейтинг ресторана от 0 до 5 |
| `restaurant` | `work_start`, `work_end` | `work_end > work_start` | BR-4.4 | закрывается позже чем открывается |
| `product` | `price` | `price >= 0` | BR-5.3 | цена не отрицательная |
| `product` | `rating` | `rating BETWEEN 0 AND 5` | BR-5.4 | |
| `courier` | `coefficient` | `coefficient BETWEEN 0.1 AND 0.5` | BR-6.4 | границы включительно |
| `courier` | `status`, `dismissal_date` | `status <> 'уволен' OR dismissal_date IS NOT NULL` | BR-6.3 | уволенный обязан иметь дату увольнения. Обратное не проверяю - у работающего дата "не обязательна", а не "запрещена" |
| `courier` | `dismissal_date` | `dismissal_date IS NULL OR dismissal_date >= hire_date` | BR-6.1, BR-6.3 | уволить раньше чем наняли нельзя |
| `courier_pay` | `month` | `month BETWEEN 1 AND 12` | BR-10.3 | номер месяца |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | зарплата неотрицательная |
| `courier_pay` | `coefficient_used` | `BETWEEN 0.1 AND 0.5` | BR-6.4, BR-10.2 | тот же диапазон что у курьера |
| `"order"` | `order_amount` | `order_amount > 0` | BR-7.10, BR-7.14 | в заказе есть хоть одна позиция, значит сумма больше нуля |
| `"order"` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | минималка 1000 ₽ |
| `"order"` | `delivery_timestamp` | `delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp` | BR-7.13 | доставили не раньше чем заказали |
| `"order"` | `status`, `delivery_timestamp` | `status <> 'доставлен' OR delivery_timestamp IS NOT NULL` | BR-7.12 | у доставленного время доставки должно быть |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | количество положительное, дробное можно |
| `review` | `rating` | `rating BETWEEN 1 AND 5` | BR-9.4 | у отзыва 1..5 (не 0..5 как у блюда!) |
| `review` | `entity_type`, `entity_id` | `entity_type <> 'заказ' OR entity_id = order_id` | BR-9.2 | отзыв на заказ только на свой |
| `client` | `password` | `password ~ '^[0-9a-f]{32}$'` | BR-2.3 | храним md5, это всегда 32 hex-символа |
| `client` | `phone_number` | `~ '^\+7[0-9]{10}$'` | BR-2.2 | один формат номера. Без этого `8900...` и `+7900...` прошли бы unique как разные |
| `courier` | `phone_number` | `~ '^\+7[0-9]{10}$'` | BR-6.1 | так же как у клиента |
| `client` | `login` | `btrim(login) <> ''` | BR-2.1, BR-11.4 | пустой логин = нет логина |
| `address` | `street`, `house_number` | `btrim(...) <> ''` | BR-3.1 | обязательные части адреса |
| `address` | `apartment_office` | `IS NULL OR btrim(...) <> ''` | BR-3.2 | нет квартиры - значит NULL, а не пустая строка |
| `restaurant` | `restaurant_name`, `company_details` | `btrim(...) <> ''` | BR-4.1, BR-4.5 | |
| `courier` | `fio` | `btrim(fio) <> ''` | BR-6.1 | |
| `product_category` | `product_category_name` | `btrim(...) <> ''` | BR-5.7 | |
| `product` | `product_name` | `btrim(...) <> ''` | BR-5.2 | |
| `product`, `review` | `photo_url` | `IS NULL OR btrim(...) <> ''` | BR-5.6, BR-9.3 | нет фото = NULL |
| `"order"` | `description` | `btrim(...) <> ''` | BR-11.3 | |
| `review` | `description` | `btrim(...) <> ''` | BR-9.3 | у отзыва есть текст |
| `payment` | `transaction_ref` | `btrim(...) <> ''` | BR-8.2, BR-8.3 | |

Зачем вообще `btrim(x) <> ''`: NOT NULL спокойно пропускает пустую строку или строку из пробелов. А по BR-11.4 "не может быть пустым" - требование к схеме, не к приложению.

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | логин уникален |
| `client` | `phone_number` | BR-2.2 | телефон тоже |
| `client_address` | PK `(client_id, address_id)` | BR-2.5 | один адрес одному клиенту только один раз |
| `restaurant` | `address_id` | BR-3.3 | два ресторана на одном адресе нельзя |
| `address` | `(street, house_number, COALESCE(apartment_office, ''))`, уникальный индекс | BR-3.3, BR-3.4 | без этого один и тот же адрес можно завести двумя строками и unique на restaurant.address_id не сработает. coalesce - т.к. два NULL в unique считаются разными |
| `product_category` | `product_category_name` | BR-5.7 | две одинаковые категории в справочнике - путаница |
| `order_structure` | PK `(order_id, product_id)` | BR-7.16 | блюдо в заказе один раз, вместо дубля растёт quantity |
| `courier_pay` | PK `(year, month, courier_id)` | BR-10.3 | одна выплата в месяц на курьера |
| `payment` | `transaction_ref` | BR-8.3 | id транзакции уникален |
| `payment` | `(order_id) WHERE status = 'успех'`, частичный | BR-8.1 | не больше одной успешной оплаты |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | на один объект в заказе один отзыв |
| `"order"` | `(order_id, client_id)` | BR-9.2 | нужен как цель для составного FK из review |
| `"order"` | `(order_id, total_amount)` | BR-8.4 | цель для составного FK из payment |

---

## FK-ограничения

Удаление почти везде RESTRICT - заказы и всё что с ними связано это история, её терять нельзя (BR-3.5). CASCADE только там где дочерняя строка без родителя не имеет смысла.

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client` | BR-2.4 | CASCADE: удалили клиента - удалилась привязка, сам адрес остаётся (BR-3.5) |
| `client_address` | `address_id` | `address` | BR-2.4, BR-3.5 | RESTRICT, адрес не удаляем пока он используется |
| `restaurant` | `address_id` | `address` | BR-3.3 | у ресторана один адрес |
| `product` | `restaurant_id` | `restaurant` | BR-5.1 | блюдо принадлежит ресторану |
| `product` | `product_category_id` | `product_category` | BR-5.1, BR-5.7 | и одной категории |
| `courier_pay` | `courier_id` | `courier` | BR-10.2 | выплата конкретному курьеру |
| `"order"` | `client_id` | `client` | BR-7.2 | |
| `"order"` | `restaurant_id` | `restaurant` | BR-7.2 | |
| `"order"` | `courier_id` | `courier` | BR-7.5 | везёт курьер |
| `"order"` | `address_id` | `address` | BR-7.4 | |
| `"order"` | `(client_id, address_id)` | `client_address (client_id, address_id)` | BR-7.4 | адрес именно этого клиента, см. ловушку 2 |
| `order_structure` | `order_id` | `"order"` | BR-7.14 | CASCADE - позиции без заказа не нужны |
| `order_structure` | `product_id` | `product` | BR-7.14 | |
| `payment` | `order_id` | `"order"` | BR-8.1 | |
| `payment` | `(order_id, amount)` | `"order" (order_id, total_amount)` | BR-8.4 | сумма оплаты = сумма заказа |
| `review` | `order_id` | `"order"` | BR-9.2 | отзыв всегда по заказу |
| `review` | `client_id` | `client` | BR-9.1 | связь есть в ERD |
| `review` | `(order_id, client_id)` | `"order" (order_id, client_id)` | BR-9.2 | отзыв от того кто заказывал |

Всего 18 FK: всё из ERD плюс три составных.

---

## NOT NULL (только бизнес-обязательные)

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `"order"` | `courier_id` | BR-1.3, BR-7.5 | самовывоза нет, у любого заказа есть курьер |
| `"order"` | `description` | BR-11.3 | BR нигде не говорит что комментарий необязательный, а NULL можно только где явно разрешено. Если клиент ничего не написал - пишем `'Без комментариев'` |
| `courier` | `coefficient` | BR-6.4, BR-6.5 | коэффициент есть всегда, у новичка 0.1 |
| `payment` | `payment_type`, `amount`, `transaction_ref`, `payment_timestamp`, `status` | BR-8.2 | "каждая попытка оплаты имеет" - все пять |
| `restaurant` | `description`, `company_details` | BR-4.1 | перечислены как атрибуты ресторана, пустыми быть не могут |
| `product` | `description` | BR-5.2 | |
| все статусы | `status`, `pay_status` | BR-4.3, BR-5.5, BR-6.2, BR-7.6, BR-7.8, BR-8.2 | статус у сущности есть всегда |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2 | частный дом, отдельный вход |
| `courier` | `dismissal_date` | BR-6.3 | пока работает - не уволен |
| `"order"` | `delivery_timestamp` | BR-7.12 | ещё не доставили |
| `product` | `photo_url` | BR-5.6 | фото необязательно |
| `review` | `photo_url` | BR-9.3 | |
| `product` | `rating` | BR-9.7 | отзывов нет → NULL. Не 0, потому что 0 это "очень плохо" |
| `restaurant` | `rating` | BR-9.7 | так же |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| все | PK `*_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1, BR-13.3 |
| `"order"` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4, BR-7.10 - ровно 10%, база считает сама |
| `"order"` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | BR-7.10. Формулу комиссии пришлось повторить - generated столбец не может ссылаться на другой generated |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5 |
| `courier` | `hire_date` | `DEFAULT current_date` | удобно, если нанимаем сегодня |
| `courier` / `restaurant` / `product` | `status` | `'свободен'` / `'активен'` / `'доступно'` | нормальное начальное состояние |
| `"order"` | `status`, `pay_status` | `'создан'`, `'ожидает'` | с этого начинается любой заказ (BR-7.7, BR-8.7) |
| `"order"`, `review`, `payment` | `*_timestamp` | `DEFAULT localtimestamp` | BR-11.2, время сервера |
| `payment` | `status` | `DEFAULT 'в_обработке'` | |

Почему generated а не обычные поля с check: с check кто-то всё равно должен посчитать комиссию сам и может ошибиться. А generated руками вообще не записать, база посчитает правильно всегда.

---

## Нормализация (3НФ)

```
1НФ - всё атомарно: адрес разбит на улицу/дом/квартиру, списков в полях нет.

2НФ - в таблицах с составным ключом (client_address, order_structure, courier_pay)
неключевые поля зависят от всего ключа: quantity от (order_id, product_id),
amount и coefficient_used от (year, month, courier_id).
Как раз поэтому BR-7.3 сделала триггером а не столбцом restaurant_id в order_structure.

3НФ - транзитивных зависимостей нет. Категории в отдельном справочнике,
адреса в address, а не копией у каждого клиента и ресторана.

Дополнительные таблицы не понадобились, 12 таблиц из ERD уже в 3НФ.

Что формально выбивается и почему так оставила:
- order.commission и order.total_amount считаются из order_amount.
  Сделала GENERATED STORED - руками не поменять, значит и аномалий нет.
  Храню, потому что их постоянно суммируют отчёты (get_statistic, how_much_money, courier_salary).
- order.pay_status - агрегат по оплатам, но BR-7.8 прямо говорит что он есть у заказа.
- product.rating и restaurant.rating - средние по отзывам, держит в актуальном виде
  триггер rating_change. Денормализация ради чтения: рейтинг показывается в каждом списке,
  а меняется только когда пишут отзыв. Каждый раз считать AVG - дорого.
- review.client_id можно вывести через заказ, но он есть в ERD. Разойтись с заказом
  не может - мешает составной FK (order_id, client_id).
- payment.amount = order.total_amount - то же самое, держится составным FK.
- entity_id + entity_type - полиморфизм, 3НФ не ломает (зависит только от review_id),
  но FK на него не повесить - см. ловушку 4.
```

---

## Прочие решения

- Таблицу назвала `"order"` в кавычках, не переименовывала (BR-13.1 разрешает оба варианта). Так совпадает с ERD и с запросами из протокола.
- Типы: телефон `char(12)` (+7 и 10 цифр, в char(11) не влезет), пароль `char(32)`, деньги `numeric(12,2)`, рейтинг и коэффициент `numeric(3,2)`, количество `numeric(8,3)` - бывает 0.5 кг.
- Месяц заказа везде считаю по `order_timestamp` - и в генераторе, и в courier_salary, и в how_much_money. Проверка C.8 считает так же.
- `insert_test_data` при повторном вызове **добавляет** новую порцию, ничего не удаляет. Где есть unique (логин, телефон, адрес, категория) - вставка через `ON CONFLICT DO NOTHING` и повтор.
- В генераторе отзывы пишутся только на доставленные заказы и после времени доставки. Заказы - только в активные рестораны и только из блюд со статусом `'доступно'`. Чтобы всегда было что заказать, первый ресторан в порции всегда активный, а первое блюдо у каждого ресторана всегда доступно. Схемой это не запрещаю: старый заказ может ссылаться на блюдо, которое потом ушло в архив, это нормально.
- Рейтинги в генераторе ставлю сама в конце, не через `rating_change` (samples, п.10). Триггер смотрит стек вызовов и, если его вызвал `insert_test_data`, ничего не делает. Сначала была настройка сессии через `set_config`, но её мог включить кто угодно и отключить пересчёт - переделала.
- `courier_salary` берёт текущий коэффициент из уже существующей записи за этот месяц, если она есть. Иначе второй запуск посчитал бы зарплату по коэффициенту следующего месяца.
- У всех функций `SET search_path = bokareva_food, exts` - работают одинаково с любым search_path у того кто вызывает.
- Бэкап: `pg_dump -Fc -n bokareva_food --no-owner --no-privileges`, снят на 15.18 после `insert_test_data(10)`. no-owner/no-privileges - чтобы восстанавливалось без ошибок там, где роли inspector ещё нет. Права потом даёт `grants.sql`.
