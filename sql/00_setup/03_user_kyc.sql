CREATE TABLE user_kyc(
kyc_id SERIAL PRIMARY KEY,
user_id INT UNIQUE NOT NULL REFERENCES users(user_id),
device_id INT REFERENCES devices(device_id),
phone_verified BOOLEAN DEFAULT FALSE,phone_verified_at TIMESTAMP,
pan_submitted BOOLEAN DEFAULT FALSE,pan_submitted_at TIMESTAMP,
pan_verified BOOLEAN DEFAULT FALSE,pan_verified_at TIMESTAMP,
aadhaar_linked BOOLEAN DEFAULT FALSE,aadhaar_linked_at TIMESTAMP,
selfie_submitted BOOLEAN DEFAULT FALSE,selfie_submitted_at TIMESTAMP,
kyc_status VARCHAR(20) DEFAULT 'pending' CHECK(kyc_status IN('pending','approved','rejected')),
kyc_approved_at TIMESTAMP,rejection_reason VARCHAR(100),
kyc_provider VARCHAR(50),risk_score NUMERIC(5,2),
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);