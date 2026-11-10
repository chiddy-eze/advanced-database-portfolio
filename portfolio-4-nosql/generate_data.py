"""
Otigba MFB - Portfolio 4: generates the MongoDB sample data as Extended JSON.
  data/customers.json     500 customer documents (accounts embedded)
  data/transactions.json  ~5,500 transaction documents (deposits + transfers)
Amounts use {"$numberDecimal": ...} (exact money, never floating point) and
dates use {"$date": ...}, so MongoDB Compass imports them with the right types.
All data is fictitious. Run:  python generate_data.py
"""
import json, random
from datetime import datetime, timedelta, timezone
from decimal import Decimal

random.seed(42)
NOW = datetime(2026, 11, 10, 12, 0, 0, tzinfo=timezone.utc)
D = lambda dt: {"$date": dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")}
M = lambda x: {"$numberDecimal": f"{Decimal(x):.2f}"}

BRANCHES = {"LAG001": ("Yaba Hub", "Lagos", "Lagos", [3.3792, 6.5095]),
            "ABJ001": ("Wuse II Hub", "Abuja", "FCT", [7.4706, 9.0765]),
            "ONI001": ("Onitsha Main", "Onitsha", "Anambra", [6.7893, 6.1413]),
            "DIG001": ("Digital (App-only)", "Lagos", "Lagos", [3.3792, 6.5095])}

# The six Portfolio 1 customers, with the same accounts and opening balances
SEED = [
 ("Adaeze", "Okonkwo", "22100000001", "1990-04-12", 3, "LAG001", [("3010000001", "SAV_T3", 250000), ("3010000002", "TARGET", 0)]),
 ("Tunde", "Bakare", "22100000002", "1985-11-03", 3, "LAG001", [("3010000003", "CURRENT", 900000)]),
 ("Halima", "Musa", "22100000003", "1998-07-21", 2, "ABJ001", [("3010000004", "SAV_T3", 120000)]),
 ("Emeka", "Nwosu", "22100000004", "1979-01-30", 3, "ONI001", [("3010000005", "CURRENT", 1500000)]),
 ("Funmi", "Adeyemi", "22100000005", "2000-09-09", 1, "DIG001", [("3010000006", "SAV_T1", 15000)]),
 ("Ibrahim", "Sani", "22100000006", "1993-02-17", 2, "ABJ001", [("3010000007", "SAV_T3", 60000)]),
]
FIRST = ["Chinedu", "Aisha", "Kelechi", "Bola", "Ngozi", "Yusuf", "Ifeoma", "Segun", "Zainab", "Obinna"]
LAST = ["Eze", "Abubakar", "Okafor", "Adebayo", "Uche", "Bello", "Nnamdi", "Ogun", "Lawal", "Obi"]

customers, txns, balances, owner = [], [], {}, {}

def kyc_docs(tier):
    docs = [{"type": "BVN_VERIFICATION", "status": "VERIFIED"}]
    if tier >= 2: docs.append({"type": "NIN", "status": "VERIFIED"})
    if tier == 3: docs.append({"type": "UTILITY_BILL", "status": "VERIFIED"})
    return docs

def add_customer(i, first, last, bvn, dob, tier, branch, accts, extra=None):
    cid = f"CUS-{i:06d}"
    b = BRANCHES[branch]
    doc = {
        "_id": cid, "bvn": bvn,
        "name": {"first": first, "last": last},
        "contact": {"email": f"{first.lower()}.{last.lower()}.{i}@example.com",
                    "phone": f"+234803{i:07d}"},
        "date_of_birth": D(datetime.fromisoformat(dob).replace(tzinfo=timezone.utc)),
        "kyc": {"tier": tier, "documents": kyc_docs(tier)},
        "address": {"city": b[1], "state": b[2]},
        "home_branch": {"code": branch, "name": b[0]},        # denormalised snapshot
        "accounts": [], "created_at": D(NOW - timedelta(days=400)),
    }
    for num, typ, opening in accts:
        doc["accounts"].append({"account_number": num, "type": typ, "currency": "NGN",
                                "balance": None, "status": "ACTIVE",
                                "opened_at": D(NOW - timedelta(days=400))})
        balances[num] = Decimal(opening); owner[num] = cid
        if opening > 0:
            txns.append({"_id": f"OPN-{num}", "type": "DEPOSIT", "amount": M(opening),
                         "currency": "NGN", "status": "SUCCESSFUL", "channel": "BRANCH",
                         "created_at": D(NOW - timedelta(days=400)),
                         "legs": [{"account_number": num, "customer_id": cid, "direction": "CREDIT"}],
                         "narration": "Opening deposit"})
    if extra: doc.update(extra)
    customers.append(doc)

for i, s in enumerate(SEED, start=1):
    add_customer(i, *s)

# 494 generated customers; some have optional fields (flexible schema)
for i in range(7, 501):
    tier = random.choice([1, 2, 2, 3, 3])
    branch = random.choice(list(BRANCHES))
    accts = [(f"303{i:07d}", random.choice(["SAV_T1", "SAV_T3", "CURRENT"]), 1000000)]
    extra = {}
    if random.random() < 0.6:
        extra["devices"] = [{"device_id": f"DEV-{i:05d}", "os": random.choice(["Android", "iOS"]),
                             "last_login": D(NOW - timedelta(hours=random.randint(1, 500)))}]
    if random.random() < 0.1:   # small business owners only
        extra["business_profile"] = {"business_name": f"{random.choice(LAST)} Ventures",
                                     "cac_number": f"RC{random.randint(100000, 999999)}",
                                     "sector": random.choice(["Retail", "Logistics", "Agriculture"])}
        accts.append((f"304{i:07d}", "CURRENT", 1000000))
    add_customer(i, random.choice(FIRST), random.choice(LAST), f"222{i:08d}",
                 f"{random.randint(1960, 2004)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}",
                 tier, branch, accts, extra)

# 5,000 transfers between generated accounts over the last 90 days
pool = [n for n in balances if n.startswith(("303", "304"))]
for k in range(1, 5001):
    a, b = random.sample(pool, 2)
    amt = Decimal(random.randint(10000, 5000000)) / 100
    status = "FAILED" if random.random() < 0.03 else "SUCCESSFUL"
    if status == "SUCCESSFUL" and balances[a] < amt:
        status = "FAILED"
    channel = random.choice(["MOBILE", "MOBILE", "MOBILE", "USSD", "POS", "WEB"])
    if channel == "MOBILE":
        home = BRANCHES[random.choice(["LAG001", "ABJ001", "ONI001"])][3]
        details = {"device_id": f"DEV-{random.randint(7, 500):05d}", "app_version": "4.2.1",
                   "geo": {"type": "Point", "coordinates": [round(home[0] + random.uniform(-0.3, 0.3), 5),
                                                            round(home[1] + random.uniform(-0.3, 0.3), 5)]}}
    elif channel == "POS":
        details = {"terminal_id": f"2OTG{random.randint(1000, 9999)}",
                   "merchant_name": random.choice(["Shoprite Ikeja", "Chicken Republic", "Total Filling Station", "Jumia Pickup"]),
                   "mcc": random.choice(["5411", "5812", "5541"])}
    elif channel == "USSD":
        details = {"short_code": "*5573#", "telco": random.choice(["MTN", "Airtel", "Glo", "9mobile"])}
    else:
        details = {"browser": random.choice(["Chrome", "Safari", "Edge"]), "ip_country": "NG"}
    if status == "SUCCESSFUL":
        balances[a] -= amt; balances[b] += amt
    txns.append({"_id": f"TRF-{k:07d}", "type": "TRANSFER", "amount": M(amt), "currency": "NGN",
                 "status": status, "channel": channel,
                 "created_at": D(NOW - timedelta(minutes=random.randint(1, 90 * 24 * 60))),
                 "legs": [{"account_number": a, "customer_id": owner[a], "direction": "DEBIT"},
                          {"account_number": b, "customer_id": owner[b], "direction": "CREDIT"}],
                 "channel_details": details, "narration": f"Transfer to {b}"})

# Final embedded balances = opening deposit + all successful movements
for c in customers:
    for acc in c["accounts"]:
        acc["balance"] = M(balances[acc["account_number"]])
        assert balances[acc["account_number"]] >= 0

json.dump(customers, open("data/customers.json", "w"), indent=1)
json.dump(txns, open("data/transactions.json", "w"), indent=1)
print(f"customers: {len(customers)}  accounts: {len(balances)}  transactions: {len(txns)}")
