CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_kyc_status ON user_kyc(kyc_status);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_events_session ON app_events(session_id);
CREATE INDEX idx_txn_user ON transactions(user_id);
CREATE INDEX idx_loans_user ON loans(user_id);