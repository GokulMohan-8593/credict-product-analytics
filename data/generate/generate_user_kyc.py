
import random
from datetime import timedelta
import pandas as pd
import psycopg2
from psycopg2.extras import execute_batch

DB = {
    "host":"localhost",
    "port":5432,
    "database":"credict",
    "user":"postgres",
    "password":"YOUR_PASSWORD"
}

PROVIDERS=["Signzy","HyperVerge","Karza","Surepass"]
REJECTION_REASONS=[
    "PAN name mismatch","Aadhaar verification failed","Blurred selfie",
    "Duplicate account","Fraud suspected","Expired PAN","Manual verification failed"
]

conn=psycopg2.connect(**DB)
cur=conn.cursor()

users=pd.read_sql("""
SELECT user_id, signup_date
FROM users
ORDER BY user_id;
""",conn)

print(f"Loaded {len(users):,} users")

records=[]
stats=dict(phone=0,pan_sub=0,pan_ver=0,aadhaar=0,selfie=0,approved=0,rejected=0,pending=0)

for _,r in users.iterrows():
    signup=r.signup_date

    phone=False; pan_sub=False; pan_ver=False
    aadhaar=False; selfie=False
    phone_at=pan_sub_at=pan_ver_at=aadhaar_at=selfie_at=approved_at=None
    status="pending"
    reject=None
    provider=random.choice(PROVIDERS)

    if random.random()<0.99:
        phone=True; stats["phone"]+=1
        phone_at=signup+timedelta(minutes=random.randint(1,30))

        if random.random()<0.98:
            pan_sub=True; stats["pan_sub"]+=1
            pan_sub_at=phone_at+timedelta(minutes=random.randint(5,180))

            if random.random()<0.99:
                pan_ver=True; stats["pan_ver"]+=1
                pan_ver_at=pan_sub_at+timedelta(minutes=random.randint(2,60))

                if random.random()<0.97:
                    aadhaar=True; stats["aadhaar"]+=1
                    aadhaar_at=pan_ver_at+timedelta(minutes=random.randint(5,120))

                    if random.random()<0.96:
                        selfie=True; stats["selfie"]+=1
                        selfie_at=aadhaar_at+timedelta(minutes=random.randint(1,45))

                        d=random.random()
                        if d<0.95:
                            status="approved"; stats["approved"]+=1
                            approved_at=selfie_at+timedelta(minutes=random.randint(2,20))
                        elif d<0.98:
                            status="rejected"; stats["rejected"]+=1
                            reject=random.choice(REJECTION_REASONS)
                        else:
                            status="pending"; stats["pending"]+=1

    records.append((
        int(r.user_id),phone,phone_at,pan_sub,pan_sub_at,
        pan_ver,pan_ver_at,aadhaar,aadhaar_at,selfie,selfie_at,
        status,approved_at,reject,provider,signup,signup
    ))

sql="""
INSERT INTO user_kyc
(user_id,phone_verified,phone_verified_at,pan_submitted,pan_submitted_at,
pan_verified,pan_verified_at,aadhaar_linked,aadhaar_linked_at,
selfie_submitted,selfie_submitted_at,kyc_status,kyc_approved_at,
rejection_reason,kyc_provider,created_at,updated_at)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);
"""

execute_batch(cur,sql,records,page_size=5000)
conn.commit()

print("\nSummary")
print(f"Users              : {len(users):,}")
for k,v in stats.items():
    print(f"{k:18}: {v:,}")

cur.close()
conn.close()
print("Done.")
