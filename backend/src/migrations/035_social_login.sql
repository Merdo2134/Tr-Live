-- v2.44.0: Google / Facebook ile giriş ve telefon numarasıyla kayıt.
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone ON users(phone) WHERE phone IS NOT NULL;

-- Dış hesap bağlantısı: (sağlayıcı, sağlayıcıdaki kimlik) → kullanıcı.
CREATE TABLE IF NOT EXISTS user_identities (
  provider VARCHAR(16) NOT NULL,
  subject TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (provider, subject)
);
CREATE INDEX IF NOT EXISTS idx_user_identities_user ON user_identities(user_id);

-- Tarayıcıda yapılan Google/Facebook girişinin uygulamaya aktarılması (uygulama sonucu sorarak alır).
CREATE TABLE IF NOT EXISTS oauth_states (
  state TEXT PRIMARY KEY,
  poll_hash TEXT NOT NULL,
  code_hash TEXT,
  provider VARCHAR(16) NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'pending',
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '10 minutes'
);
ALTER TABLE oauth_states ADD COLUMN IF NOT EXISTS code_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_oauth_states_expires ON oauth_states(expires_at);
