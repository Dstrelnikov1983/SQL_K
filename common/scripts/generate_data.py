# -*- coding: utf-8 -*-
"""
Генератор сквозного набора данных компании «Питание +».

Создаёт детерминированный (seed = 2024) набор данных за 2024–2025 гг.
и выгружает его:
  * в CSV-файлы  ../data/<table>.csv  (UTF-8, разделитель ';')
  * в SQL-скрипт 02_insert_data.sql (INSERT-ы для схемы pitanie)

В данные намеренно заложены «точки потерь» — ситуации, где компания
работает неэффективно. Их описание — в common/instructor_insights.md
(файл для преподавателя).

Запуск:  python generate_data.py
"""
import csv
import os
import random
from datetime import date, datetime, timedelta

random.seed(2024)

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "..", "data")
SQL_FILE = os.path.join(HERE, "02_insert_data.sql")

START = date(2024, 1, 1)
END = date(2025, 12, 31)
DAYS = (END - START).days + 1


def d_range():
    for i in range(DAYS):
        yield START + timedelta(days=i)


def r2(x):
    return round(x + 1e-9, 2)


tables = {}  # name -> (columns, rows)

# ---------------------------------------------------------------------------
# 1. Регионы
# ---------------------------------------------------------------------------
regions = [
    (1, "Москва и МО", "Центральный"),
    (2, "Санкт-Петербург и ЛО", "Северо-Западный"),
    (3, "Тверская область", "Центральный"),
    (4, "Нижегородская область", "Приволжский"),
    (5, "Республика Татарстан", "Приволжский"),
    (6, "Краснодарский край", "Южный"),
    (7, "Ростовская область", "Южный"),
    (8, "Свердловская область", "Уральский"),
    (9, "Новосибирская область", "Сибирский"),
    (10, "Красноярский край", "Сибирский"),
    (11, "Воронежская область", "Центральный"),
    (12, "Самарская область", "Приволжский"),
]
tables["regions"] = (["region_id", "region_name", "federal_district"], regions)
# «Дальние» регионы — долгая доставка
FAR_REGIONS = {9, 10}

# ---------------------------------------------------------------------------
# 2. Сотрудники (иерархия manager_id -> self join)
# ---------------------------------------------------------------------------
emp_rows = []


def emp(eid, name, pos, dept, mgr, hire, salary, email, phone):
    emp_rows.append((eid, name, pos, dept, mgr, hire, salary, email, phone))


emp(1, "Орлов Виктор Петрович", "Генеральный директор", "Дирекция", None, date(2012, 3, 1), 450000, "v.orlov@pitanie-plus.ru", "+7 (495) 100-00-01")
emp(2, "Белова Марина Сергеевна", "Финансовый директор", "Финансы", 1, date(2015, 6, 15), 320000, "m.belova@pitanie-plus.ru", "+7 (495) 100-00-02")
emp(3, "Громов Алексей Иванович", "Коммерческий директор", "Продажи", 1, date(2014, 2, 10), 330000, "a.gromov@pitanie-plus.ru", "+7 (495) 100-00-03")
emp(4, "Лебедев Андрей Николаевич", "Директор по производству", "Производство", 1, date(2013, 9, 1), 310000, "a.lebedev@pitanie-plus.ru", "+7 (495) 100-00-04")
emp(5, "Кузнецов Олег Викторович", "Начальник отдела закупок", "Закупки", 1, date(2018, 4, 2), 210000, "o.kuznetsov@pitanie-plus.ru", "+7 (495) 100-00-05")
# Продажи
sales_mgrs = [
    (10, "Соколов Игорь Андреевич", date(2019, 5, 20)),
    (11, "Морозова Елена Павловна", date(2017, 8, 1)),
    (12, "Волков Денис Сергеевич", date(2020, 1, 13)),
    (13, "Новикова Ольга Игоревна", date(2016, 11, 7)),
    (14, "Федоров Павел Олегович", date(2021, 3, 15)),
    (15, "Зайцева Анна Викторовна", date(2022, 6, 1)),
    (16, "Павлов Сергей Дмитриевич", date(2018, 10, 22)),
    (17, "Семенова Ирина Алексеевна", date(2023, 2, 6)),
]
emp(9, "Ершова Татьяна Юрьевна", "Руководитель отдела продаж", "Продажи", 3, date(2016, 4, 4), 230000, "t.ershova@pitanie-plus.ru", "+7 (495) 100-00-09")
for eid, nm, hd in sales_mgrs:
    login = nm.split()[0].lower()
    emp(eid, nm, "Менеджер по продажам", "Продажи", 9, hd, random.choice([110000, 120000, 125000, 135000, 140000]),
        None if eid == 17 else f"{login}@pitanie-plus.ru", f"8-916-{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(10,99)}")
# Финансы
emp(20, "Котова Наталья Михайловна", "Главный бухгалтер", "Финансы", 2, date(2015, 9, 1), 190000, "n.kotova@pitanie-plus.ru", "+7 (495) 100-00-20")
emp(21, "Егоров Максим Ильич", "Финансовый аналитик", "Финансы", 2, date(2022, 9, 5), 140000, "m.egorov@pitanie-plus.ru", "+7 (495) 100-00-21")
emp(22, "Тихонова Вера Андреевна", "Специалист по дебиторской задолженности", "Финансы", 20, date(2021, 1, 18), 95000, "v.tikhonova@pitanie-plus.ru", None)
# Закупки
emp(30, "Карпов Роман Евгеньевич", "Менеджер по закупкам", "Закупки", 5, date(2019, 7, 1), 115000, "r.karpov@pitanie-plus.ru", "+7 (495) 100-00-30")
emp(31, "Сидорова Юлия Олеговна", "Менеджер по закупкам", "Закупки", 5, date(2020, 10, 12), 110000, "y.sidorova@pitanie-plus.ru", "+7 (495) 100-00-31")
emp(32, "Абрамов Кирилл Петрович", "Менеджер по закупкам", "Закупки", 5, date(2023, 4, 3), 98000, "k.abramov@pitanie-plus.ru", "+7(495)1000032")
# Производство
emp(40, "Михайлов Георгий Ильич", "Начальник цеха молочной продукции", "Производство", 4, date(2014, 5, 12), 180000, "g.mikhailov@pitanie-plus.ru", "+7 (495) 100-00-40")
emp(41, "Степанова Людмила Васильевна", "Начальник цеха кондитерских изделий", "Производство", 4, date(2016, 3, 21), 175000, "l.stepanova@pitanie-plus.ru", "+7 (495) 100-00-41")
emp(42, "Яковлев Борис Николаевич", "Главный механик", "Производство", 4, date(2011, 1, 10), 165000, "b.yakovlev@pitanie-plus.ru", "+7 (495) 100-00-42")
emp(43, "Захарова Светлана Петровна", "Начальник ОТК", "Производство", 4, date(2017, 8, 14), 150000, "s.zakharova@pitanie-plus.ru", "+7 (495) 100-00-43")
operators = [
    (50, "Борисов Артём Сергеевич", 40), (51, "Гусева Дарья Ивановна", 40),
    (52, "Комаров Илья Петрович", 40), (53, "Виноградов Тимур Ринатович", 40),
    (54, "Титова Ксения Андреевна", 41), (55, "Орехов Никита Владимирович", 41),
    (56, "Филиппова Алина Романовна", 41), (57, "Медведев Глеб Олегович", 41),
    (58, "Савельев Ринат Маратович", 40), (59, "Куликова Полина Сергеевна", 41),
]
for eid, nm, mgr in operators:
    emp(eid, nm, "Оператор линии", "Производство", mgr, date(2018 + eid % 6, 1 + eid % 12, 1 + eid % 27),
        random.choice([72000, 76000, 80000, 85000]), None, None)
# Уволенный сотрудник (для NULL/дат)
emp(60, "Попов Станислав Игоревич", "Менеджер по продажам", "Продажи", 9, date(2017, 2, 1), 118000, "s.popov@pitanie-plus.ru", None)
tables["employees"] = (["employee_id", "full_name", "position", "department", "manager_id", "hire_date", "salary", "email", "phone"], emp_rows)
emp_term = {60: date(2024, 6, 30)}

# ---------------------------------------------------------------------------
# 3. Категории и продукты
# ---------------------------------------------------------------------------
categories = [
    (1, "Молочная продукция", None),
    (2, "Кондитерские изделия", None),
    (3, "Бакалея", None),
    (11, "Молоко и сливки", 1),
    (12, "Кисломолочные продукты", 1),
    (13, "Сыры и масло", 1),
    (21, "Печенье и вафли", 2),
    (22, "Шоколад и конфеты", 2),
    (31, "Каши и хлопья", 3),
    (32, "Соусы", 3),
]
tables["product_categories"] = (["category_id", "category_name", "parent_category_id"], categories)

# product_id, sku, name, cat, unit, weight, shelf, base_price, std_cost, line
products_def = [
    (1, "MLK-001", "Молоко пастеризованное 2,5% 1 л", 11, "шт", 1.03, 10, 89.0, 61.0, 1),
    (2, "MLK-002", "Молоко пастеризованное 3,2% 1 л", 11, "шт", 1.03, 10, 95.0, 66.0, 1),
    (3, "MLK-003", "Молоко ультрапастеризованное 3,2% 1 л", 11, "шт", 1.03, 180, 112.0, 74.0, 1),
    (4, "MLK-004", "Сливки 20% 0,5 л", 11, "шт", 0.52, 14, 165.0, 112.0, 1),
    (5, "MLK-005", "Сливки 33% 0,5 л", 11, "шт", 0.52, 14, 245.0, 171.0, 1),
    (6, "KSM-001", "Кефир 2,5% 0,9 л", 12, "шт", 0.93, 10, 92.0, 60.0, 3),
    (7, "KSM-002", "Ряженка 4% 0,5 л", 12, "шт", 0.52, 10, 78.0, 50.0, 3),
    (8, "KSM-003", "Йогурт клубничный 2,5% 0,3 кг", 12, "шт", 0.31, 7, 69.0, 41.0, 3),
    (9, "KSM-004", "Йогурт черничный 2,5% 0,3 кг", 12, "шт", 0.31, 7, 72.0, 43.0, 3),
    (10, "KSM-005", "Творог 9% 0,2 кг", 12, "шт", 0.21, 12, 115.0, 76.0, 3),
    (11, "KSM-006", "Сметана 20% 0,3 кг", 12, "шт", 0.31, 14, 98.0, 64.0, 3),
    (12, "KSM-007", "Творожный сырок ванильный 50 г", 12, "шт", 0.05, 15, 45.0, 27.0, 3),
    # Себестоимость масла выросла с 03.2025 (молочный жир +28 %), прайс не пересмотрен
    (13, "SYR-001", "Масло сливочное 82,5% 180 г", 13, "шт", 0.18, 60, 189.0, 205.0, 2),
    (14, "SYR-002", "Масло сливочное 72,5% 180 г", 13, "шт", 0.18, 60, 159.0, 151.0, 2),
    (15, "SYR-003", "Сыр Российский 45% 1 кг", 13, "кг", 1.0, 90, 690.0, 470.0, 2),
    (16, "SYR-004", "Сыр Гауда 45% 1 кг", 13, "кг", 1.0, 120, 780.0, 530.0, 2),
    (17, "SYR-005", "Сыр плавленый 150 г", 13, "шт", 0.15, 180, 95.0, 58.0, 2),
    (18, "PEC-001", "Печенье сахарное 300 г", 21, "шт", 0.3, 180, 79.0, 42.0, 4),
    (19, "PEC-002", "Печенье овсяное 400 г", 21, "шт", 0.4, 150, 99.0, 55.0, 4),
    (20, "PEC-003", "Вафли сливочные 200 г", 21, "шт", 0.2, 240, 69.0, 36.0, 4),
    (21, "PEC-004", "Вафли шоколадные 200 г", 21, "шт", 0.2, 240, 75.0, 41.0, 4),
    (22, "PEC-005", "Крекер солёный 250 г", 21, "шт", 0.25, 270, 65.0, 33.0, 4),
    (23, "SHK-001", "Шоколад молочный 90 г", 22, "шт", 0.09, 365, 95.0, 52.0, 5),
    (24, "SHK-002", "Шоколад горький 70% 90 г", 22, "шт", 0.09, 365, 125.0, 68.0, 5),
    (25, "SHK-003", "Конфеты «Птичье молоко» 250 г", 22, "шт", 0.25, 120, 245.0, 150.0, 5),
    (26, "SHK-004", "Конфеты шоколадные ассорти 200 г", 22, "шт", 0.2, 270, 299.0, 175.0, 5),
    (27, "SHK-005", "Батончик шоколадный с нугой 50 г", 22, "шт", 0.05, 270, 49.0, 26.0, 5),
    (28, "BAK-001", "Овсяные хлопья 500 г", 31, "шт", 0.5, 365, 89.0, 48.0, 4),
    (29, "BAK-002", "Мюсли с фруктами 400 г", 31, "шт", 0.4, 300, 159.0, 92.0, 4),
    (30, "BAK-003", "Каша овсяная быстрого приготовления 6×40 г", 31, "шт", 0.24, 365, 119.0, 66.0, 4),
    (31, "SOU-001", "Соус сырный 200 г", 32, "шт", 0.2, 120, 129.0, 78.0, 2),
    (32, "SOU-002", "Соус сливочно-чесночный 200 г", 32, "шт", 0.2, 120, 119.0, 71.0, 2),
    (33, "KSM-008", "Биойогурт питьевой персик 0,27 л", 12, "шт", 0.28, 14, 65.0, 39.0, 3),
    (34, "SHK-006", "Шоколад белый 90 г", 22, "шт", 0.09, 365, 99.0, 55.0, 5),
    (35, "PEC-006", "Пряники мятные 350 г", 21, "шт", 0.35, 90, 85.0, 47.0, 4),
]
# Снятые с производства
discontinued = {35: date(2025, 3, 31), 12: None}
launch = {33: date(2024, 9, 1), 34: date(2025, 2, 1)}
products = []
for p in products_def:
    pid = p[0]
    products.append((pid, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8],
                     pid not in (35,),
                     launch.get(pid, date(2019, 1, 1) + timedelta(days=pid * 37)),
                     discontinued.get(pid)))
tables["products"] = (["product_id", "sku", "product_name", "category_id", "unit", "weight_kg", "shelf_life_days",
                        "base_price", "standard_cost", "is_active", "launch_date", "discontinued_date"], products)
prod_by_id = {p[0]: p for p in products_def}
prod_line = {p[0]: p[9] for p in products_def}

# История цен
price_hist = []
phid = 1
for p in products_def:
    pid, base = p[0], p[7]
    price_hist.append((phid, pid, date(2024, 1, 1), date(2024, 12, 31), r2(base * 0.94))); phid += 1
    if pid in (13, 14):
        price_hist.append((phid, pid, date(2025, 1, 1), None, base)); phid += 1
    else:
        price_hist.append((phid, pid, date(2025, 1, 1), None, base)); phid += 1
tables["price_history"] = (["price_id", "product_id", "valid_from", "valid_to", "price"], price_hist)


def list_price(pid, dt):
    base = prod_by_id[pid][7]
    return r2(base * 0.94) if dt.year == 2024 else base

# ---------------------------------------------------------------------------
# 4. Клиенты
# ---------------------------------------------------------------------------
cust_types = ["Федеральная сеть", "Региональная сеть", "Дистрибьютор", "HoReCa", "Розница", "Маркетплейс"]
name_parts = ["Вектор", "Ромашка", "Северный двор", "Продторг", "Гастроном №1", "Вкусный дом", "Магнит-Регион",
              "Свежесть", "Колос", "Берёзка", "Уральский продукт", "Сибирская торговая", "Южный берег",
              "Кубань-Опт", "Волга-Маркет", "Невский пассаж", "Тверской купец", "ПродМаркет", "Фермер", "Корзинка",
              "Добрый день", "Семейный", "Пятёрочка-Партнёр", "Лента-Сервис", "Перекрёсток Регион", "Хлеб-Соль",
              "Кафе Уют", "Ресторан Пушкин", "Столовая №7", "Кофейня Зерно", "ОЗОН-Партнёр", "Вайлдберриз-Поставка",
              "Самокат-Снаб", "Азбука вкуса", "Глобус", "Призма", "Гулливер", "Восход", "Рассвет", "Империя вкуса",
              "Дары природы", "Мираж", "Альфа", "Бета-Трейд", "Гамма", "Дельта", "Омега-Опт", "Сигма", "Тандем",
              "Партнёр", "Бриз", "Камелия", "Лотос", "Мегаполис", "Орбита", "Полюс", "Радуга", "Сатурн", "Титан",
              "Уралочка", "Факел", "Хорошие продукты", "Цитадель", "Чайка", "Шанс", "Экспресс", "Юпитер", "Яблонька"]
forms = ["ООО", "АО", "ИП", "ООО", "ООО", "ПАО"]
customers = []
cid = 1
cust_meta = {}
for i, nm in enumerate(name_parts):
    if "Кафе" in nm or "Ресторан" in nm or "Столовая" in nm or "Кофейня" in nm:
        ctype = "HoReCa"
    elif "ОЗОН" in nm or "Вайлдберриз" in nm or "Самокат" in nm:
        ctype = "Маркетплейс"
    elif nm in ("Магнит-Регион", "Пятёрочка-Партнёр", "Лента-Сервис", "Перекрёсток Регион", "Азбука вкуса", "Глобус"):
        ctype = "Федеральная сеть"
    else:
        ctype = random.choice(["Региональная сеть", "Дистрибьютор", "Розница", "Розница", "Дистрибьютор"])
    form = "ИП" if ctype == "Розница" and random.random() < 0.3 else random.choice(["ООО", "ООО", "АО"])
    if form == "ИП":
        full = f"ИП {random.choice(['Иванов','Петров','Смирнов','Кузьмин','Шевченко','Носов'])} ({nm})"
    else:
        full = f'{form} "{nm}"'
    region = random.choice([1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    if nm in ("Сибирская торговая",):
        region = 9
    if nm in ("Уральский продукт", "Уралочка"):
        region = 8
    if nm == "Кубань-Опт":
        region = 6
    if nm == "Невский пассаж":
        region = 2
    if nm == "Тверской купец":
        region = 3
    if nm in ("Полюс", "Сатурн", "Орбита"):
        region = 10
    if nm in ("Чайка", "Восход"):
        region = 9
    inn = "".join(str(random.randint(0, 9)) for _ in range(10 if form != "ИП" else 12))
    phone_fmt = random.choice(["+7 (9{a}) {b}-{c}-{d}", "8-9{a}-{b}-{c}-{d}", "+79{a}{b}{c}{d}", "8 (9{a}) {b} {c} {d}"])
    phone = phone_fmt.format(a=random.randint(10, 99), b=random.randint(100, 999), c=random.randint(10, 99), d=random.randint(10, 99))
    email_login = f"info{cid}" if random.random() < 0.5 else f"zakaz.{cid}"
    email = random.choice([f"{email_login}@mail.ru", f"{email_login.upper()}@YANDEX.RU", f" {email_login}@company.ru ", None])
    reg_date = date(2016, 1, 1) + timedelta(days=random.randint(0, 3000))
    credit = {"Федеральная сеть": 15000000, "Региональная сеть": 5000000, "Дистрибьютор": 4000000,
              "HoReCa": 500000, "Розница": 300000, "Маркетплейс": 6000000}[ctype]
    terms = {"Федеральная сеть": 45, "Региональная сеть": 30, "Дистрибьютор": 30,
             "HoReCa": 14, "Розница": 7, "Маркетплейс": 30}[ctype]
    if region is not None and random.random() < 0.06:
        region_v = None
    else:
        region_v = region
    mgr = random.choice([10, 11, 12, 13, 14, 15, 16, 17, 11, 13, 16])
    if nm in ("Вектор", "Восход", "Полюс", "Сатурн", "Дельта", "Бриз", "Факел", "Орбита", "Чайка"):
        mgr = 10  # портфель Соколова
    if nm == "Вектор":
        ctype, credit, terms, region_v = "Дистрибьютор", 3000000, 30, 1
        full = 'ООО "Торговый дом Вектор"'
    customers.append([cid, full, ctype, region_v, inn, phone, email, reg_date, credit, terms, mgr])
    cust_meta[cid] = dict(name=nm, type=ctype, region=region_v, mgr=mgr, terms=terms)
    cid += 1

# Дубликаты клиентов (качество данных)
dups = [('Ромашка ООО', "Ромашка"), ('ООО  "РОМАШКА"', "Ромашка"), ('ооо "Свежесть" ', "Свежесть"), ('ООО "Колос" (дубль)', "Колос")]
for full, base in dups:
    orig = next(c for c in customers if cust_meta[c[0]]["name"] == base)
    customers.append([cid, full, orig[2], orig[3], orig[4], orig[5], None, date(2024, random.randint(2, 11), random.randint(1, 28)),
                      orig[8], orig[9], random.choice([12, 14, 15])])
    cust_meta[cid] = dict(name=base + "_dup", type=orig[2], region=orig[3], mgr=customers[-1][10], terms=orig[9])
    cid += 1
# Клиент без заказов
customers.append([cid, 'ООО "Новый горизонт"', "Розница", 4, "7701234567", "8-912-000-11-22", "ng@mail.ru", date(2025, 11, 20), 300000, 7, 17])
cust_meta[cid] = dict(name="Новый горизонт", type="Розница", region=4, mgr=17, terms=7)
no_order_cust = {cid}
cid += 1
tables["customers"] = (["customer_id", "customer_name", "customer_type", "region_id", "inn", "phone", "email",
                         "registration_date", "credit_limit", "payment_terms_days", "manager_id"], [tuple(c) for c in customers])
vector_id = next(c[0] for c in customers if cust_meta[c[0]]["name"] == "Вектор")

# ---------------------------------------------------------------------------
# 5. Заказы / позиции / счета / оплаты / возвраты
# ---------------------------------------------------------------------------
channel_by_type = {"Федеральная сеть": "Прямые продажи", "Региональная сеть": "Прямые продажи", "Дистрибьютор": "Дистрибуция",
                   "HoReCa": "Прямые продажи", "Розница": "Дистрибуция", "Маркетплейс": "Маркетплейс"}
type_weight = {"Федеральная сеть": 6, "Региональная сеть": 3, "Дистрибьютор": 4, "HoReCa": 1.5, "Розница": 1, "Маркетплейс": 3}
qty_scale = {"Федеральная сеть": 900, "Региональная сеть": 350, "Дистрибьютор": 500, "HoReCa": 40, "Розница": 30, "Маркетплейс": 300}
active_customers = [c[0] for c in customers if c[0] not in no_order_cust]
weights = []
for c in active_customers:
    w = type_weight[cust_meta[c]["type"]]
    if c == vector_id:
        w = 5
    weights.append(w)

orders, items, invoices, payments, returns_ = [], [], [], [], []
oid = iid = inv_id = pay_id = ret_id = 1
comments = [None] * 12 + ["Срочно!", "доставка до 10:00", "Позвонить перед доставкой", "ПОВТОРНЫЙ ЗАКАЗ",
                          "акция", "Акция -10%", "  тендер №45/2025 ", "оплата по факту"]
for dt in d_range():
    season = 1.0 + 0.15 * (1 if dt.month in (11, 12) else 0) - 0.1 * (1 if dt.month in (6, 7) else 0)
    growth = 1.0 + 0.10 * (dt.year - 2024)
    n_orders = max(0, int(random.gauss(7 * season * growth, 2)))
    if dt.weekday() == 6:
        n_orders = n_orders // 3
    for _ in range(n_orders):
        c = random.choices(active_customers, weights)[0]
        meta = cust_meta[c]
        if "_dup" in meta["name"] and dt < date(2024, 3, 1):
            continue
        if c == vector_id and dt < date(2024, 4, 1):
            continue
        mgr = meta["mgr"]
        if mgr == 17 and dt < date(2023, 2, 6):
            mgr = 16
        # уволенный Попов вел часть клиентов до середины 2024
        if mgr == 16 and dt <= date(2024, 6, 30) and random.random() < 0.3:
            mgr = 60
        region = meta["region"]
        lead = random.randint(1, 3) + (random.randint(3, 6) if region in FAR_REGIONS else 0)
        status_r = random.random()
        if dt > END - timedelta(days=5):
            status = random.choice(["Новый", "В работе"])
        elif status_r < 0.04:
            status = "Отменён"
        else:
            status = "Доставлен" if dt < END - timedelta(days=15) else random.choice(["Отгружен", "Доставлен"])
        shipped = None if status in ("Новый", "В работе", "Отменён") else dt + timedelta(days=lead)
        required = dt + timedelta(days=random.choice([2, 3, 5, 7]))
        channel = channel_by_type[meta["type"]]
        if meta["type"] == "Федеральная сеть" and random.random() < 0.08:
            channel = "Тендер"
        onum = f"ЗК-{dt.year}-{oid:05d}"
        orders.append((oid, onum, c, mgr, dt, required, shipped, status, channel, random.choice(comments)))
        # позиции
        n_items = random.randint(1, 7)
        avail = [p[0] for p in products_def
                 if (p[0] not in launch or dt >= launch[p[0]]) and not (p[0] == 35 and dt > date(2025, 3, 31))]
        if meta["type"] == "HoReCa":
            avail = [p for p in avail if p in (2, 4, 5, 10, 11, 13, 15, 16, 31, 32)]
        chosen = random.sample(avail, min(n_items, len(avail)))
        order_total = 0.0
        for pid in chosen:
            q = max(5, int(random.gauss(qty_scale[meta["type"]], qty_scale[meta["type"]] * 0.4)))
            if prod_by_id[pid][4] == "кг":
                q = max(2, q // 8)
            price = list_price(pid, dt)
            # Политика скидок: до 10 %. Федеральные сети — 5–10 %, остальные 0–7 %.
            if meta["type"] == "Федеральная сеть":
                disc = random.choice([5, 7, 8, 10])
            elif meta["type"] == "Маркетплейс":
                disc = random.choice([3, 5, 7])
            else:
                disc = random.choice([0, 0, 2, 3, 5, 7])
            if mgr == 10:  # Соколов систематически превышает лимит скидки
                disc = random.choice([12, 15, 18, 20, 25])
            if mgr == 60 and random.random() < 0.3:
                disc = 12
            items.append((iid, oid, pid, q, price, disc))
            order_total += q * price * (1 - disc / 100)
            iid += 1
        order_total = r2(order_total)
        if shipped is None:
            oid += 1
            continue
        # счёт
        terms = meta["terms"]
        inv_date = shipped
        due = inv_date + timedelta(days=terms)
        invoices.append((inv_id, oid, f"СЧ-{inv_date.year}-{inv_id:05d}", inv_date, due, order_total))
        # оплаты
        if c == vector_id:
            # Вектор: с 2025 года платит всё хуже, отгрузки продолжаются
            if inv_date < date(2025, 1, 1):
                delay = random.randint(0, 25)
                parts = [(1.0, delay)]
            elif inv_date < date(2025, 6, 1):
                parts = [(0.5, random.randint(40, 90))] if random.random() < 0.7 else []
            else:
                parts = [] if random.random() < 0.85 else [(0.3, random.randint(30, 60))]
        elif meta["type"] == "Маркетплейс":
            parts = [(1.0, random.randint(5, 25))]
        elif meta["type"] == "Федеральная сеть":
            parts = [(1.0, random.randint(-5, 12))] if random.random() < 0.85 else [(0.6, random.randint(0, 10)), (0.4, random.randint(15, 40))]
        else:
            r = random.random()
            if r < 0.80:
                parts = [(1.0, random.randint(-10, 5))]
            elif r < 0.95:
                parts = [(0.5, random.randint(-5, 5)), (0.5, random.randint(5, 35))]
            else:
                parts = [(1.0, random.randint(20, 75))]
        for frac, delay in parts:
            pdt = due + timedelta(days=delay)
            if pdt < inv_date:
                pdt = inv_date
            if pdt > END:
                continue
            payments.append((pay_id, inv_id, pdt, r2(order_total * frac), random.choice(["Банковский перевод"] * 9 + ["Взаимозачёт"])))
            pay_id += 1
        inv_id += 1
        # возвраты
        for (it_id, it_oid, pid, q, price, disc) in [x for x in items if x[1] == oid]:
            p_ret = 0.004
            shelf = prod_by_id[pid][6]
            if shelf <= 7 and region in FAR_REGIONS:
                p_ret = 0.45  # короткий срок + долгая доставка
            elif shelf <= 10 and region in FAR_REGIONS:
                p_ret = 0.15
            elif shelf <= 10:
                p_ret = 0.03
            if random.random() < p_ret:
                rq = max(1, int(q * random.uniform(0.1, 0.4 if region in FAR_REGIONS else 0.15)))
                reason = "Истёк срок годности" if shelf <= 14 and region in FAR_REGIONS else random.choice(
                    ["Повреждение упаковки", "Несоответствие заказу", "Истёк срок годности", "Брак"])
                returns_.append((ret_id, oid, pid, shipped + timedelta(days=random.randint(1, 6)), rq, reason))
                ret_id += 1
        oid += 1

tables["orders"] = (["order_id", "order_number", "customer_id", "employee_id", "order_date", "required_date", "shipped_date",
                      "status", "channel", "comment"], orders)
tables["order_items"] = (["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount_pct"], items)
tables["invoices"] = (["invoice_id", "order_id", "invoice_number", "invoice_date", "due_date", "amount"], invoices)
tables["payments"] = (["payment_id", "invoice_id", "payment_date", "amount", "payment_method"], payments)
tables["returns"] = (["return_id", "order_id", "product_id", "return_date", "quantity", "reason"], returns_)

# ---------------------------------------------------------------------------
# 6. План продаж (по месяцам и категориям верхнего уровня)
# ---------------------------------------------------------------------------
from collections import defaultdict
fact = defaultdict(float)
cat_parent = {c[0]: c[2] for c in categories}
ord_date = {o[0]: o[4] for o in orders}
ord_status = {o[0]: o[7] for o in orders}
for (it_id, o, pid, q, price, disc) in items:
    if ord_status[o] == "Отменён":
        continue
    d0 = ord_date[o]
    fact[(d0.year, d0.month, cat_parent[prod_by_id[pid][3]])] += q * price * (1 - disc / 100)
plans = []
plid = 1
for y in (2024, 2025):
    for m in range(1, 13):
        for cat in (1, 2, 3):
            f = fact[(y, m, cat)]
            k = random.uniform(0.95, 1.12)
            if y == 2025 and cat == 2 and m >= 7:
                k = 1.25
            plans.append((plid, y, m, cat, round(f * k, -3)))
            plid += 1
tables["sales_plan"] = (["plan_id", "plan_year", "plan_month", "category_id", "plan_amount"], plans)

# ---------------------------------------------------------------------------
# 7. Расходы (финансы)
# ---------------------------------------------------------------------------
expenses = []
exid = 1
exp_cats = [("Логистика", "Продажи"), ("Маркетинг", "Продажи"), ("Аренда", "Дирекция"), ("Энергоресурсы", "Производство"),
            ("Ремонт оборудования", "Производство"), ("Комиссия маркетплейса", "Продажи"), ("ИТ", "Дирекция"),
            ("Командировки", "Продажи"), ("Списание продукции", "Продажи"), ("Списание сырья", "Производство")]
for y in (2024, 2025):
    for m in range(1, 13):
        base_rev = sum(v for (yy, mm, _), v in fact.items() if yy == y and mm == m)
        d0 = date(y, m, 1)
        def add(cat, dept, amt, descr, ch=None):
            global exid
            day = random.randint(1, 28)
            expenses.append((exid, date(y, m, day), cat, dept, ch, r2(amt), descr))
            exid += 1
        add("Логистика", "Продажи", base_rev * random.uniform(0.035, 0.045), "Транспортные услуги, Центр", "Прямые продажи")
        add("Логистика", "Продажи", base_rev * random.uniform(0.012, 0.016), "Транспортные услуги, Дистрибуция", "Дистрибуция")
        add("Логистика", "Продажи", base_rev * random.uniform(0.02, 0.03) * (1.3 if y == 2025 else 1.0), "Доставка на склады маркетплейсов", "Маркетплейс")
        add("Комиссия маркетплейса", "Продажи", base_rev * random.uniform(0.025, 0.03) * (1.25 if y == 2025 else 1), "Комиссия площадок", "Маркетплейс")
        mk = base_rev * random.uniform(0.015, 0.02)
        if y == 2025 and m >= 9:
            mk *= 3.2  # дорогая рекламная кампания без роста продаж
        add("Маркетинг", "Продажи", mk, "Рекламная кампания" + (" «Осень вкуса»" if y == 2025 and m >= 9 else ""))
        add("Аренда", "Дирекция", 1850000 if y == 2024 else 1980000, "Аренда офиса и склада")
        add("Энергоресурсы", "Производство", random.uniform(2.4e6, 3.1e6) * (1.12 if y == 2025 else 1), "Электроэнергия, газ, вода")
        add("Ремонт оборудования", "Производство", random.uniform(300000, 500000) * (2.5 if y == 2025 else 1.3), "Ремонт и ТО, Линия 2")
        add("Ремонт оборудования", "Производство", random.uniform(150000, 260000), "Плановое ТО, прочие линии")
        add("ИТ", "Дирекция", random.uniform(280000, 340000), "Лицензии и обслуживание")
        if random.random() < 0.7:
            add("Командировки", "Продажи", random.uniform(90000, 260000), None)
tables["expenses"] = (["expense_id", "expense_date", "expense_category", "department", "sales_channel", "amount", "description"], expenses)

# ---------------------------------------------------------------------------
# 8. Поставщики, сырьё, закупки
# ---------------------------------------------------------------------------
suppliers = [
    (1, 'ООО "МолПром Регион"', 3, "6950123456", 4.1, date(2018, 2, 1), 14, "+7 (4822) 55-10-10"),
    (2, 'АО "Тверское молоко"', 3, "6950654321", 4.7, date(2016, 5, 12), 21, "+7 (4822) 44-20-20"),
    (3, 'ООО "АгроСнаб-М"', 1, "7701987654", 3.9, date(2021, 8, 1), 7, "+7 (495) 777-11-22"),
    (4, 'АО "Сахарный комбинат Воронеж"', 11, "3601112233", 4.8, date(2015, 1, 15), 30, "+7 (473) 222-33-44"),
    (5, 'ООО "Кубань-Сахар"', 6, "2301445566", 4.5, date(2019, 3, 1), 30, "+7 (861) 333-44-55"),
    (6, 'ООО "Мука Поволжья"', 12, "6301778899", 4.6, date(2017, 6, 20), 21, "+7 (846) 111-22-33"),
    (7, 'ООО "КакаоТрейд"', 1, "7702334455", 4.2, date(2020, 9, 9), 14, "+7 (495) 555-66-77"),
    (8, 'ООО "ЯгодаПрод"', 6, "2302556677", 3.6, date(2022, 4, 1), 14, "+7 (861) 999-88-77"),
    (9, 'АО "УпакСервис"', 1, "7703667788", 4.4, date(2016, 11, 1), 30, "+7 (495) 123-45-67"),
    (10, 'ООО "Масложир Юг"', 7, "6101889900", 4.3, date(2018, 7, 1), 21, "+7 (863) 200-30-40"),
    (11, 'ООО "Зерно Сибири"', 9, "5401990011", 4.0, date(2023, 1, 10), 21, "+7 (383) 300-40-50"),
    (12, 'ООО "Специи и Ко"', 1, "7704001122", None, date(2025, 6, 1), 14, None),
]
tables["suppliers"] = (["supplier_id", "supplier_name", "region_id", "inn", "rating", "contract_date", "payment_terms_days", "phone"], suppliers)

# material_id, name, group, unit, shelf_days, min_stock, base_price, suppliers(primary list)
materials = [
    (1, "Молоко сырое", "Молочное сырьё", "л", 3, 20000, 38.0, [1, 2]),
    (2, "Сливки сырые 35%", "Молочное сырьё", "л", 5, 2000, 245.0, [1, 2]),
    (3, "Закваска кисломолочная", "Молочное сырьё", "кг", 180, 20, 5200.0, [2, 3]),
    (4, "Сахар-песок", "Сахар и сиропы", "кг", 730, 8000, 62.0, [4, 5, 3]),
    (5, "Глюкозный сироп", "Сахар и сиропы", "кг", 365, 1000, 78.0, [4, 3]),
    (6, "Мука пшеничная в/с", "Мука и зерно", "кг", 365, 6000, 34.0, [6, 11]),
    (7, "Хлопья овсяные (сырьё)", "Мука и зерно", "кг", 365, 4000, 41.0, [6, 11]),
    (8, "Какао-порошок", "Какао и шоколад", "кг", 540, 800, 690.0, [7, 3]),
    (9, "Какао-масло", "Какао и шоколад", "кг", 540, 500, 1450.0, [7]),
    (10, "Наполнитель клубничный", "Фрукты и наполнители", "кг", 90, 600, 320.0, [8]),
    (11, "Наполнитель черничный", "Фрукты и наполнители", "кг", 90, 400, 360.0, [8]),
    (12, "Наполнитель персиковый", "Фрукты и наполнители", "кг", 90, 200, 300.0, [8]),
    (13, "Масло растительное", "Жиры", "л", 365, 1500, 135.0, [10, 3]),
    (14, "Молочный жир", "Жиры", "кг", 120, 800, 720.0, [10, 2]),
    (15, "Соль пищевая", "Прочее сырьё", "кг", 1825, 300, 14.0, [12, 3]),
    (16, "Ванилин", "Прочее сырьё", "кг", 730, 20, 2900.0, [12, 3]),
    (17, "Сухофрукты микс", "Фрукты и наполнители", "кг", 270, 300, 520.0, [8, 3]),
    (18, "Желатин", "Прочее сырьё", "кг", 730, 50, 980.0, [12, 3]),
    (19, "Сычужный фермент", "Молочное сырьё", "кг", 365, 10, 9800.0, [2]),
    (20, "Пакет тетра-пак 1 л", "Упаковка", "шт", 1095, 50000, 7.2, [9]),
    (21, "Стаканчик 0,3 кг с крышкой", "Упаковка", "шт", 1095, 30000, 4.8, [9]),
    (22, "Флоу-пак плёнка", "Упаковка", "кг", 1095, 500, 410.0, [9]),
    (23, "Коробка картонная", "Упаковка", "шт", 1825, 5000, 18.0, [9]),
    (24, "Чеснок сушёный", "Прочее сырьё", "кг", 365, 30, 640.0, [12, 3]),
]
tables["raw_materials"] = (["material_id", "material_name", "material_group", "unit", "shelf_life_days", "min_stock"],
                           [m[:6] for m in materials])
mat = {m[0]: m for m in materials}

# Рецептуры (норма расхода на единицу продукции)
recipes_def = {
    1: [(1, 1.02), (20, 1)], 2: [(1, 1.03), (20, 1)], 3: [(1, 1.03), (20, 1)],
    4: [(2, 0.32), (1, 0.2), (20, 0.5)], 5: [(2, 0.48), (20, 0.5)],
    6: [(1, 0.92), (3, 0.0005), (20, 1)], 7: [(1, 0.5), (3, 0.0003), (21, 1)],
    8: [(1, 0.26), (10, 0.045), (4, 0.02), (3, 0.0002), (21, 1)],
    9: [(1, 0.26), (11, 0.045), (4, 0.02), (3, 0.0002), (21, 1)],
    10: [(1, 1.1), (3, 0.0004), (21, 1)], 11: [(1, 0.4), (2, 0.1), (3, 0.0003), (21, 1)],
    12: [(1, 0.25), (4, 0.008), (16, 0.0001), (22, 0.002)],
    13: [(14, 0.15), (2, 0.08), (22, 0.003)], 14: [(14, 0.12), (13, 0.02), (22, 0.003)],
    15: [(1, 10.0), (19, 0.0003), (15, 0.02)], 16: [(1, 10.5), (19, 0.0003), (15, 0.02)],
    17: [(1, 0.8), (14, 0.02), (15, 0.003), (22, 0.002)],
    18: [(6, 0.16), (4, 0.08), (13, 0.03), (22, 0.004), (23, 0.05)],
    19: [(6, 0.12), (7, 0.12), (4, 0.09), (13, 0.04), (22, 0.004), (23, 0.05)],
    20: [(6, 0.09), (4, 0.06), (13, 0.04), (16, 0.0001), (22, 0.003), (23, 0.05)],
    21: [(6, 0.08), (4, 0.06), (8, 0.012), (13, 0.04), (22, 0.003), (23, 0.05)],
    22: [(6, 0.18), (13, 0.03), (15, 0.004), (22, 0.004), (23, 0.05)],
    23: [(8, 0.018), (9, 0.022), (4, 0.04), (14, 0.008), (22, 0.001), (23, 0.02)],
    24: [(8, 0.038), (9, 0.025), (4, 0.025), (22, 0.001), (23, 0.02)],
    25: [(4, 0.08), (18, 0.003), (8, 0.02), (9, 0.02), (14, 0.03), (23, 0.05)],
    26: [(8, 0.03), (9, 0.04), (4, 0.06), (5, 0.03), (23, 0.05)],
    27: [(8, 0.006), (9, 0.008), (4, 0.012), (5, 0.012), (22, 0.0008)],
    28: [(7, 0.5), (22, 0.004), (23, 0.05)],
    29: [(7, 0.3), (17, 0.08), (4, 0.02), (22, 0.004), (23, 0.05)],
    30: [(7, 0.22), (4, 0.015), (17, 0.01), (22, 0.004), (23, 0.05)],
    31: [(1, 0.08), (14, 0.02), (15, 0.002), (21, 1)], 32: [(2, 0.06), (24, 0.004), (15, 0.002), (21, 1)],
    33: [(1, 0.24), (12, 0.03), (4, 0.015), (3, 0.0002), (20, 0.3)],
    34: [(9, 0.03), (4, 0.04), (14, 0.012), (16, 0.0001), (22, 0.001), (23, 0.02)],
    35: [(6, 0.17), (4, 0.09), (16, 0.0001), (22, 0.004), (23, 0.05)],
}
recipes = []
rid = 1
for pid, lst in recipes_def.items():
    for m_id, q in lst:
        recipes.append((rid, pid, m_id, q)); rid += 1
tables["recipes"] = (["recipe_id", "product_id", "material_id", "qty_per_unit"], recipes)

# Линии
lines = [
    (1, "Линия 1 — розлив молока", "Цех молочной продукции", 6000, 2017, 40),
    (2, "Линия 2 — масло, сыры, соусы", "Цех молочной продукции", 1500, 2009, 40),
    (3, "Линия 3 — кисломолочная", "Цех молочной продукции", 4000, 2015, 40),
    (4, "Линия 4 — печенье, вафли, хлопья", "Цех кондитерских изделий", 3000, 2019, 41),
    (5, "Линия 5 — шоколад и конфеты", "Цех кондитерских изделий", 2000, 2021, 41),
]
tables["production_lines"] = (["line_id", "line_name", "workshop", "capacity_per_hour", "launch_year", "responsible_id"], lines)

# Объём продаж по продукту/месяцу -> план производства
sold = defaultdict(float)
for (it_id, o, pid, q, price, disc) in items:
    d0 = ord_date[o]
    sold[(d0.year, d0.month, pid)] += q

line_products = defaultdict(list)
for pid, ln in prod_line.items():
    line_products[ln].append(pid)

batches, consumption, downtime = [], [], []
bid = cons_id = dt_id = 1
ops_by_line = {1: [50, 51, 58], 2: [52, 53], 3: [50, 51, 52, 58], 4: [54, 55, 59], 5: [56, 57, 59]}
mat_usage = defaultdict(float)  # (date, material) -> qty
for dt in d_range():
    if dt.weekday() == 6:
        continue
    for ln in range(1, 6):
        for shift in ("День", "Ночь"):
            if ln in (4, 5) and shift == "Ночь" and dt.weekday() == 5:
                continue
            # продукт этой смены
            pool = [p for p in line_products[ln] if (p not in launch or dt >= launch[p]) and not (p == 35 and dt > date(2025, 3, 31))]
            mweights = [max(1.0, sold[(dt.year, dt.month, p)]) for p in pool]
            pid = random.choices(pool, mweights)[0]
            monthly = sold[(dt.year, dt.month, pid)]
            share = mweights[pool.index(pid)] / sum(mweights)
            planned = int(max(200, monthly / (26 * 2 * max(share, 0.05)) * 1.05 * random.uniform(0.8, 1.2)))
            planned = int(round(planned, -1))
            if prod_by_id[pid][4] == "кг":
                planned = max(50, planned // 2)
            # выполнение плана
            eff = random.uniform(0.95, 1.01)
            if ln == 2:
                # стареющая линия: падение выпуска в 2025
                eff = random.uniform(0.86, 0.97) if dt.year == 2025 else random.uniform(0.92, 1.0)
            produced = int(planned * eff)
            # брак
            defect_rate = random.uniform(0.008, 0.025)
            if ln == 3 and shift == "Ночь":
                defect_rate = random.uniform(0.06, 0.10)
            if ln == 2 and dt.year == 2025:
                defect_rate += 0.015
            defect = int(produced * defect_rate)
            op = random.choice(ops_by_line[ln])
            if ln == 3 and shift == "Ночь":
                op = random.choice([52, 58])
            batches.append((bid, f"П{dt.strftime('%y%m%d')}-{ln}{'Д' if shift == 'День' else 'Н'}", pid, ln, dt, shift,
                            planned, produced, defect, op))
            # расход сырья
            for m_id, norm in recipes_def[pid]:
                over = random.uniform(0.99, 1.03)
                if ln == 5 and m_id in (8, 9):
                    over = random.uniform(1.09, 1.16)  # перерасход какао на линии 5
                if ln == 3 and shift == "Ночь" and m_id == 1:
                    over = random.uniform(1.04, 1.08)
                qty = round(norm * produced * over, 3)
                consumption.append((cons_id, bid, m_id, qty))
                mat_usage[(dt, m_id)] += qty
                cons_id += 1
            bid += 1
    # простои
    for ln in range(1, 6):
        p = 0.05
        if ln == 2:
            p = 0.12 if dt.year == 2024 else 0.30
        if random.random() < p and dt.weekday() != 6:
            if ln == 2:
                reason, cat = random.choice([("Поломка гомогенизатора", "Поломка оборудования"),
                                             ("Износ уплотнений маслообразователя", "Поломка оборудования"),
                                             ("Отказ насоса", "Поломка оборудования"),
                                             ("Плановое ТО", "Плановое обслуживание"),
                                             ("Нет сырья (молочный жир)", "Отсутствие сырья")])
            else:
                reason, cat = random.choice([("Плановое ТО", "Плановое обслуживание"),
                                             ("Санобработка внеплановая", "Санитарная обработка"),
                                             ("Переналадка на другой SKU", "Переналадка"),
                                             ("Отказ датчика", "Поломка оборудования"),
                                             ("Нет сырья (молоко)", "Отсутствие сырья") if ln in (1, 3) else ("Нет упаковки", "Отсутствие сырья")])
            start = datetime(dt.year, dt.month, dt.day, random.randint(0, 22), random.choice([0, 15, 30, 45]))
            dur = random.randint(20, 180) if cat != "Поломка оборудования" else random.randint(60, 600)
            if ln == 2 and cat == "Поломка оборудования" and dt.year == 2025:
                dur = random.randint(180, 900)
            end = start + timedelta(minutes=dur)
            if random.random() < 0.01:
                end = None  # простой не закрыт
            downtime.append((dt_id, ln, start, end, reason, cat))
            dt_id += 1

tables["production_batches"] = (["batch_id", "batch_number", "product_id", "line_id", "production_date", "shift",
                                  "planned_qty", "produced_qty", "defect_qty", "operator_id"], batches)
tables["material_consumption"] = (["consumption_id", "batch_id", "material_id", "quantity"], consumption)
tables["equipment_downtime"] = (["downtime_id", "line_id", "start_time", "end_time", "reason", "downtime_category"], downtime)

# Закупки: еженедельно по каждому материалу на объём расхода
weekly = defaultdict(float)
for (dt, m_id), q in mat_usage.items():
    wk = dt - timedelta(days=dt.weekday())
    weekly[(wk, m_id)] += q

pos, po_items = [], []
po_id = poi_id = 1
buyers = {"Молочное сырьё": 30, "Сахар и сиропы": 31, "Мука и зерно": 31, "Какао и шоколад": 32,
          "Фрукты и наполнители": 32, "Жиры": 30, "Прочее сырьё": 32, "Упаковка": 31}
writeoffs = []
wo_id = 1
weeks = sorted({w for (w, _) in weekly})
for wk in weeks:
    by_sup = defaultdict(list)
    for m_id in mat:
        need = weekly.get((wk, m_id), 0)
        if need <= 0:
            continue
        m = mat[m_id]
        sups = m[7]
        # выбор поставщика
        if m_id in (4, 5) and 3 in sups:
            # АгроСнаб-М получает >50% заказов на сахар, несмотря на высокую цену
            sup = 3 if random.random() < 0.55 else random.choice([4, 5] if m_id == 4 else [4])
        elif 3 in sups and random.random() < 0.15:
            sup = 3
        else:
            sup = random.choice([s for s in sups if s != 3] or sups)
        if sup == 12 and wk < date(2025, 6, 1):
            sup = 3
        qty = need * random.uniform(1.0, 1.1)
        if m_id == 10:
            qty = need * random.uniform(1.6, 2.0)  # закупают клубничный наполнитель с избытком -> списания
        price = m[6] * (1 + 0.07 * (wk.year - 2024)) * random.uniform(0.97, 1.03)
        if m_id == 14 and wk >= date(2025, 2, 17):
            price *= 1.28  # рост цены молочного жира
        if sup == 3:
            price *= random.uniform(1.22, 1.30)  # переплата у АгроСнаб-М
        if sup == 8 and m_id in (10, 11, 12):
            price *= 1.0
        by_sup[sup].append((m_id, qty, price))
    for sup, lst in by_sup.items():
        odate = wk - timedelta(days=random.randint(3, 6))
        if odate < START:
            odate = START
        exp = odate + timedelta(days=random.randint(3, 7))
        buyer = buyers[mat[lst[0][0]][2]]
        if sup == 3:
            buyer = 31 if random.random() < 0.8 else 30
        status = "Получен"
        if odate > END - timedelta(days=7):
            status = "Отправлен"
        pos.append((po_id, f"ЗП-{odate.year}-{po_id:05d}", sup, buyer, odate, exp, status))
        for m_id, qty, price in lst:
            unit = mat[m_id][3]
            q = round(qty, 0) if unit == "шт" else round(qty, 1)
            if q <= 0:
                q = 1
            if status == "Получен":
                delay = random.choice([0, 0, 0, 1])
                if sup == 1:
                    delay = random.choice([0, 1, 2, 3, 4, 5, 6])  # МолПром Регион опаздывает
                if sup == 8:
                    delay = random.choice([0, 1, 2, 3])
                rdate = exp + timedelta(days=delay)
                quality = "Принято"
                rq = q
                if sup == 1 and random.random() < 0.14:
                    quality = "Принято частично"
                    rq = round(q * random.uniform(0.6, 0.9), 1)
                elif sup == 8 and random.random() < 0.10:
                    quality = "Принято частично"
                    rq = round(q * random.uniform(0.7, 0.9), 1)
                elif random.random() < 0.02:
                    quality = "Принято частично"
                    rq = round(q * 0.95, 1)
                if sup == 1 and random.random() < 0.03:
                    quality = "Отклонено"
                    rq = 0
            else:
                rdate, quality, rq = None, None, None
            po_items.append((poi_id, po_id, m_id, q, r2(price), rq, rdate, quality))
            poi_id += 1
        po_id += 1

tables["purchase_orders"] = (["po_id", "po_number", "supplier_id", "employee_id", "order_date", "expected_date", "status"], pos)
tables["purchase_order_items"] = (["po_item_id", "po_id", "material_id", "quantity", "unit_price", "received_qty",
                                    "received_date", "quality_status"], po_items)

# Списания сырья
avg_price = defaultdict(list)
for x in po_items:
    avg_price[x[2]].append(x[4])
for dt in d_range():
    if dt.day not in (10, 25):
        continue
    for m_id in mat:
        p = 0.08
        k = random.uniform(0.005, 0.02)
        if m_id == 10:
            p, k = 0.95, random.uniform(0.25, 0.40)  # излишки клубничного наполнителя
        elif m_id in (1, 2):
            p, k = 0.4, random.uniform(0.003, 0.01)
        if random.random() < p:
            month_use = sum(mat_usage.get((dt - timedelta(days=i), m_id), 0) for i in range(15))
            if month_use <= 0:
                continue
            q = round(month_use * k, 1)
            reason = "Истёк срок годности" if m_id in (10, 11, 12, 1, 2, 14) else random.choice(["Повреждение тары", "Истёк срок годности", "Несоответствие качества"])
            price = sum(avg_price[m_id]) / len(avg_price[m_id])
            writeoffs.append((wo_id, m_id, dt, q, reason, r2(q * price)))
            wo_id += 1
tables["material_writeoffs"] = (["writeoff_id", "material_id", "writeoff_date", "quantity", "reason", "amount"], writeoffs)

# ---------------------------------------------------------------------------
# Выгрузка
# ---------------------------------------------------------------------------
ORDER = ["regions", "employees", "product_categories", "products", "price_history", "customers", "orders", "order_items",
         "invoices", "payments", "returns", "sales_plan", "expenses", "suppliers", "raw_materials", "recipes",
         "production_lines", "production_batches", "material_consumption", "equipment_downtime",
         "purchase_orders", "purchase_order_items", "material_writeoffs"]


def sql_val(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, int) else ("%.4f" % v).rstrip("0").rstrip(".")
    if isinstance(v, datetime):
        return "'" + v.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''") + "'"


def csv_val(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".")
    return v


os.makedirs(DATA_DIR, exist_ok=True)
for t in ORDER:
    cols, rows = tables[t]
    with open(os.path.join(DATA_DIR, f"{t}.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(cols)
        for r in rows:
            w.writerow([csv_val(v) for v in r])

with open(SQL_FILE, "w", encoding="utf-8", newline="\n") as f:
    f.write("-- =====================================================================\n")
    f.write("-- Курс «Углублённый SQL». Сквозной пример «Питание +»\n")
    f.write("-- Скрипт 02: загрузка данных (сгенерирован generate_data.py, не редактировать вручную)\n")
    f.write("-- Предварительно выполните 01_create_schema.sql\n")
    f.write("-- =====================================================================\n\n")
    f.write("SET search_path TO pitanie;\n\nBEGIN;\n\n")
    for t in ORDER:
        cols, rows = tables[t]
        f.write(f"-- {t}: {len(rows)} строк\n")
        for i in range(0, len(rows), 500):
            chunk = rows[i:i + 500]
            f.write(f"INSERT INTO {t} ({', '.join(cols)}) VALUES\n")
            f.write(",\n".join("(" + ", ".join(sql_val(v) for v in r) + ")" for r in chunk))
            f.write(";\n")
        f.write("\n")
    f.write("COMMIT;\n\nANALYZE;\n")

for t in ORDER:
    print(f"{t:25s} {len(tables[t][1]):7d}")
