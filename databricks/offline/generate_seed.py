#!/usr/bin/env python3
"""generate_seed.py — deterministic WWI-shaped seed data for the offline demo.

Emits six CSVs whose headers are the exact WideWorldImportersDW source column
names (spaces included) that the bronze layer lands with SELECT * and the
silver layer consumes:

  dim_city, dim_customer, dim_stock_item, dim_date, fact_sale, fact_stockholding

The seed is the *contract* for offline mode: source_fed tables created from
these CSVs must look like the federation views they replace. Column inventory
was taken from the vendored bacpac model.xml and the silver/gold SQL.

Deterministic (--seed), stdlib only. Strings never contain commas or quotes
so the CSVs load with plain COPY INTO ... FILEFORMAT = CSV.

Usage:
  python3 generate_seed.py --out /tmp/wwi_seed [--sales 25000] [--seed 42]
"""
import argparse
import csv
import os
import random
from datetime import date, timedelta

END_OF_TIME = "9999-12-31 00:00:00"
VALID_FROM = "2013-01-01 00:00:00"
DATE_START = date(2014, 1, 1)
DATE_END = date(2016, 12, 31)
SALE_START = date(2015, 1, 1)

CITIES = [
    ("New York", "New York", "United States", 8400000),
    ("Los Angeles", "California", "United States", 3900000),
    ("Chicago", "Illinois", "United States", 2700000),
    ("Houston", "Texas", "United States", 2300000),
    ("Phoenix", "Arizona", "United States", 1600000),
    ("Seattle", "Washington", "United States", 750000),
    ("Denver", "Colorado", "United States", 715000),
    ("Boston", "Massachusetts", "United States", 675000),
    ("Atlanta", "Georgia", "United States", 500000),
    ("Minneapolis", "Minnesota", "United States", 430000),
    ("Auckland", "Auckland", "New Zealand", 1650000),
    ("Wellington", "Wellington", "New Zealand", 215000),
    ("Christchurch", "Canterbury", "New Zealand", 390000),
    ("Sydney", "New South Wales", "Australia", 5300000),
    ("Melbourne", "Victoria", "Australia", 5200000),
    ("Brisbane", "Queensland", "Australia", 2500000),
    ("London", "England", "United Kingdom", 8900000),
    ("Manchester", "England", "United Kingdom", 550000),
    ("Toronto", "Ontario", "Canada", 2900000),
    ("Vancouver", "British Columbia", "Canada", 675000),
    ("Berlin", "Berlin", "Germany", 3700000),
    ("Munich", "Bavaria", "Germany", 1500000),
    ("Paris", "Ile-de-France", "France", 2100000),
    ("Lyon", "Auvergne-Rhone-Alpes", "France", 520000),
    ("Tokyo", "Tokyo", "Japan", 14000000),
    ("Osaka", "Osaka", "Japan", 2700000),
    ("Singapore", "Singapore", "Singapore", 5900000),
    ("Dubai", "Dubai", "United Arab Emirates", 3500000),
    ("Mumbai", "Maharashtra", "India", 12500000),
    ("Bangalore", "Karnataka", "India", 8500000),
]

CUSTOMER_CATEGORIES = ["Novelty Shop", "Supermarket", "Computer Store",
                       "Gift Shop", "Corporate", "Wholesale"]
BUYING_GROUPS = ["Wingtip", "Tailspin Toys", "Contoso", ""]
CUSTOMER_PREFIXES = ["Tailspin Toys", "Wingtip Stores", "Contoso Retail",
                     "Fabrikam Grocers", "Northwind Traders", "Litware Gifts"]
BRANDS = ["Northwind", "Contoso", "Fabrikam", "Adventure Works", ""]
SIZES = ["S", "M", "L", "XL", "100g", "250g", "1L", "N/A"]
ITEM_WORDS = [
    ("USB food flash drive", "chocolate"),
    ("USB food flash drive", "sushi"),
    ("Novelty chilli chocolate", "large"),
    ("Ride on toy sedan", "red"),
    ("Ride on toy sedan", "blue"),
    ("Developer joke mug", "white"),
    ("SQL stress ball", "green"),
    ("Pack of action figures", "12 pack"),
    ("Halloween skull mask", "black"),
    ("Furry animal slippers", "pink"),
    ("Dinosaur battery clock", "yellow"),
    ("Retro lunch box", "silver"),
]


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def gen_dim_city(rng):
    rows = []
    for i, (city, state, country, pop) in enumerate(CITIES, start=1):
        jittered = int(pop * rng.uniform(0.9, 1.1))
        rows.append([i, i, city, state, country, jittered, VALID_FROM, END_OF_TIME])
    return (["City Key", "WWI City ID", "City", "State Province", "Country",
             "Latest Recorded Population", "Valid From", "Valid To"], rows)


def gen_dim_customer(rng, n_current=500, n_history=25):
    rows = []
    key = 0
    history_of = rng.sample(range(1, n_current + 1), n_history)
    for wwi_id in range(1, n_current + 1):
        name = f"{rng.choice(CUSTOMER_PREFIXES)} ({rng.choice([c[0] for c in CITIES])}) {wwi_id}"
        city_id = rng.randint(1, len(CITIES))
        category = rng.choice(CUSTOMER_CATEGORIES)
        group = rng.choice(BUYING_GROUPS)
        if wwi_id in history_of:
            key += 1
            rows.append([key, wwi_id, name, name, category, group, city_id,
                         VALID_FROM, "2015-06-01 00:00:00"])
            key += 1
            rows.append([key, wwi_id, name, name, category, group, city_id,
                         "2015-06-02 00:00:00", END_OF_TIME])
        else:
            key += 1
            rows.append([key, wwi_id, name, name, category, group, city_id,
                         VALID_FROM, END_OF_TIME])
    header = ["Customer Key", "WWI Customer ID", "Customer", "Bill To Customer",
              "Category", "Buying Group", "City", "Valid From", "Valid To"]
    current_keys = [r[0] for r in rows if r[8] == END_OF_TIME]
    return header, rows, current_keys


def gen_dim_stock_item(rng, n=200):
    rows = []
    key = 0
    prices = []
    while len(rows) < n:
        base, variant = ITEM_WORDS[(key // 8) % len(ITEM_WORDS)]
        key += 1
        name = f"{base} {variant} {key}"
        price = round(rng.uniform(2.0, 90.0), 2)
        prices.append(price)
        rows.append([key, key, name, rng.choice(BRANDS), rng.choice(SIZES),
                     rng.randint(1, 28), VALID_FROM, END_OF_TIME])
    header = ["Stock Item Key", "WWI Stock Item ID", "Stock Item", "Brand",
              "Size", "Lead Time Days", "Valid From", "Valid To"]
    return header, rows, prices


def gen_dim_date():
    rows = []
    d = DATE_START
    while d <= DATE_END:
        rows.append([d.isoformat(), d.day, d.strftime("%A"), d.strftime("%B"),
                     d.year, d.month, (d.month - 1) // 3 + 1])
        d += timedelta(days=1)
    header = ["Date", "Day Number", "Day", "Month", "Calendar Year",
              "Calendar Month Number", "Calendar Quarter"]
    return header, rows


def gen_fact_sale(rng, n_sales, customer_keys, item_keys, prices):
    rows = []
    sale_days = (DATE_END - SALE_START).days
    for sale_key in range(1, n_sales + 1):
        invoice_date = SALE_START + timedelta(days=rng.randint(0, sale_days))
        cust_key = rng.choice(customer_keys)
        item_idx = rng.randrange(len(item_keys))
        qty = rng.randint(1, 40)
        price = prices[item_idx]
        total = round(qty * price * 1.15, 2)
        profit = round(total * rng.uniform(0.2, 0.4), 2)
        rows.append([sale_key, invoice_date.isoformat(), cust_key,
                     item_keys[item_idx], qty, price, total, profit,
                     (sale_key - 1) // 10 + 1, cust_key, item_keys[item_idx]])
    header = ["Sale Key", "Invoice Date Key", "Customer Key", "Stock Item Key",
              "Quantity", "Unit Price", "Total Including Tax", "Profit",
              "WWI Invoice ID", "WWI Customer ID", "WWI Stock Item ID"]
    return header, rows


def gen_fact_stockholding(rng, item_keys):
    rows = []
    for key in item_keys:
        on_hand = rng.randint(0, 5000)
        rows.append([key, on_hand, rng.randint(0, min(400, on_hand)),
                     "2016-12-31 00:00:00"])
    header = ["Stock Item Key", "Quantity On Hand", "Quantity Allocated",
              "Last Edited When"]
    return header, rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="output directory for CSVs")
    ap.add_argument("--sales", type=int, default=25000, help="fact_sale rows")
    ap.add_argument("--seed", type=int, default=42, help="RNG seed")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    header, rows = gen_dim_city(rng)
    write_csv(os.path.join(args.out, "dim_city.csv"), header, rows)
    n_city = len(rows)

    header, rows, current_keys = gen_dim_customer(rng)
    write_csv(os.path.join(args.out, "dim_customer.csv"), header, rows)
    n_customer = len(rows)

    header, rows, prices = gen_dim_stock_item(rng)
    write_csv(os.path.join(args.out, "dim_stock_item.csv"), header, rows)
    item_keys = [r[0] for r in rows]
    n_item = len(rows)

    header, rows = gen_dim_date()
    write_csv(os.path.join(args.out, "dim_date.csv"), header, rows)
    n_date = len(rows)

    header, rows = gen_fact_sale(rng, args.sales, current_keys, item_keys, prices)
    write_csv(os.path.join(args.out, "fact_sale.csv"), header, rows)
    n_sale = len(rows)

    header, rows = gen_fact_stockholding(rng, item_keys)
    write_csv(os.path.join(args.out, "fact_stockholding.csv"), header, rows)
    n_stock = len(rows)

    print(f"seed written to {args.out} (seed={args.seed})")
    print(f"  dim_city={n_city} dim_customer={n_customer} "
          f"dim_stock_item={n_item} dim_date={n_date} "
          f"fact_sale={n_sale} fact_stockholding={n_stock}")


if __name__ == "__main__":
    main()
