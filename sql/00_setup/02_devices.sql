CREATE TABLE devices(
device_id SERIAL PRIMARY KEY,
user_id INT NOT NULL REFERENCES users(user_id),
device_type VARCHAR(20) CHECK(device_type IN ('Android','iOS','Web','Tablet')),
manufacturer VARCHAR(50),model VARCHAR(80),os_version VARCHAR(20),app_version VARCHAR(20),
push_notification_enabled BOOLEAN DEFAULT TRUE,
rooted_device BOOLEAN DEFAULT FALSE,
first_seen_at TIMESTAMP NOT NULL,last_active_at TIMESTAMP,
is_active BOOLEAN DEFAULT TRUE,
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);