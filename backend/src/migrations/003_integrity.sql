CREATE UNIQUE INDEX IF NOT EXISTS idx_family_members_one_family_per_user
ON family_members(user_id);

ALTER TABLE inventory_items
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_user_wip_active
ON user_wip(user_id,is_active,expires_at);

CREATE INDEX IF NOT EXISTS idx_dealer_transactions_dealer_created
ON dealer_transactions(dealer_id,created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gift_transactions_room_created
ON gift_transactions(room_id,created_at DESC);

CREATE INDEX IF NOT EXISTS idx_financial_audit_user_created
ON financial_audit_logs(user_id,created_at DESC);
