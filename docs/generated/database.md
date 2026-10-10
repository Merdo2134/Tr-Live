# Veritabanı şeması

> Otomatik üretildi: `node backend/scripts/gen_docs.mjs`. Elle düzenlemeyin.

**75 tablo**, 29 migration dosyası (PostgreSQL 16).

[agencies](#agencies) · [agency_commission_tiers](#agency_commission_tiers) · [agency_commissions](#agency_commissions) · [agency_requests](#agency_requests) · [agency_settings](#agency_settings) · [agency_statements](#agency_statements) · [announcements](#announcements) · [app_config](#app_config) · [banners](#banners) · [broadcast_sessions](#broadcast_sessions) · [broadcasters](#broadcasters) · [client_errors](#client_errors) · [coin_packages](#coin_packages) · [daily_progress](#daily_progress) · [daily_streak](#daily_streak) · [dealer_accounts](#dealer_accounts) · [dealer_transactions](#dealer_transactions) · [direct_messages](#direct_messages) · [entrance_effects](#entrance_effects) · [families](#families) · [family_members](#family_members) · [favorite_hosts](#favorite_hosts) · [financial_audit_logs](#financial_audit_logs) · [firewall_blocks](#firewall_blocks) · [follows](#follows) · [frames](#frames) · [friend_requests](#friend_requests) · [gift_transactions](#gift_transactions) · [gifts](#gifts) · [global_gift_events](#global_gift_events) · [host_salary_tiers](#host_salary_tiers) · [host_statements](#host_statements) · [idempotency_keys](#idempotency_keys) · [inventory_items](#inventory_items) · [lucky_bag_claims](#lucky_bag_claims) · [lucky_bags](#lucky_bags) · [media_files](#media_files) · [mic_sessions](#mic_sessions) · [moderation_strikes](#moderation_strikes) · [music_tracks](#music_tracks) · [official_event_attendance](#official_event_attendance) · [official_events](#official_events) · [payout_periods](#payout_periods) · [pk_battles](#pk_battles) · [pk_supporters](#pk_supporters) · [post_comments](#post_comments) · [post_likes](#post_likes) · [posts](#posts) · [profile_visitors](#profile_visitors) · [recent_rooms](#recent_rooms) · [reports](#reports) · [room_blocks](#room_blocks) · [room_game_players](#room_game_players) · [room_games](#room_games) · [room_gift_totals](#room_gift_totals) · [room_members](#room_members) · [room_messages](#room_messages) · [room_mic_queue](#room_mic_queue) · [room_music](#room_music) · [room_music_queue](#room_music_queue) · [room_mutes](#room_mutes) · [room_profiles](#room_profiles) · [room_staff](#room_staff) · [rooms](#rooms) · [security_events](#security_events) · [store_items](#store_items) · [support_messages](#support_messages) · [upload_owners](#upload_owners) · [user_blocks](#user_blocks) · [user_sessions](#user_sessions) · [user_wip](#user_wip) · [users](#users) · [wallet_transactions](#wallet_transactions) · [wip_plans](#wip_plans) · [wip_tiers](#wip_tiers)

## agencies

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 004 |
| name | `VARCHAR(80) NOT NULL` | 004 |
| owner_id | `UUID NOT NULL REFERENCES users(id)` | 004 |
| logo_url | `TEXT` | 004 |
| description | `TEXT` | 004 |
| commission_bps | `INT NOT NULL DEFAULT 0 CHECK (commission_bps BETWEEN 0 AND 10000)` | 004 |
| status | `VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended','rejected'))` | 004 |
| approved_by | `UUID REFERENCES users(id)` | 004 |
| approved_at | `TIMESTAMPTZ` | 004 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |
| agency_code | `VARCHAR(8)` | 006 |
| commission_override_bps | `INT CHECK (commission_override_bps IS NULL OR commission_override_bps BETWEEN 0 AND 10000)` | 006 |

İndeksler:
- `UNIQUE idx_agencies_name_lower (lower(name)) WHERE status <> 'rejected'`
- `UNIQUE idx_agencies_owner (owner_id) WHERE status <> 'rejected'`
- `UNIQUE idx_agencies_code (agency_code) WHERE agency_code IS NOT NULL`

## agency_commission_tiers

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| level | `INT PRIMARY KEY CHECK (level BETWEEN 1 AND 10)` | 006 |
| min_team_diamonds | `BIGINT NOT NULL CHECK (min_team_diamonds >= 0)` | 006 |
| commission_bps | `INT NOT NULL CHECK (commission_bps BETWEEN 0 AND 10000)` | 006 |

## agency_commissions

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 004 |
| agency_id | `UUID NOT NULL REFERENCES agencies(id)` | 004 |
| broadcaster_id | `UUID NOT NULL REFERENCES users(id)` | 004 |
| gift_transaction_id | `UUID REFERENCES gift_transactions(id)` | 004 |
| diamond_amount | `BIGINT NOT NULL CHECK (diamond_amount > 0)` | 004 |
| period | `CHAR(7) NOT NULL` | 004 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'accrued' CHECK (status IN ('accrued','paid'))` | 004 |
| paid_at | `TIMESTAMPTZ` | 004 |
| paid_by | `UUID REFERENCES users(id)` | 004 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |

İndeksler:
- `idx_agency_commissions_lookup (agency_id, period, status)`
- `idx_agency_commissions_broadcaster (broadcaster_id, period)`

## agency_requests

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 004 |
| agency_id | `UUID NOT NULL REFERENCES agencies(id) ON DELETE CASCADE` | 004 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 004 |
| direction | `VARCHAR(10) NOT NULL CHECK (direction IN ('invite','apply'))` | 004 |
| status | `VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','cancelled'))` | 004 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |
| responded_at | `TIMESTAMPTZ` | 004 |

İndeksler:
- `UNIQUE idx_agency_requests_one_pending (agency_id, user_id) WHERE status = 'pending'`
- `idx_agency_requests_user (user_id, status)`

## agency_settings

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `INT PRIMARY KEY DEFAULT 1 CHECK (id = 1)` | 006 |
| cycle | `VARCHAR(10) NOT NULL DEFAULT 'monthly' CHECK (cycle IN ('weekly','monthly'))` | 006 |
| penalty_bps | `INT NOT NULL DEFAULT 5000 CHECK (penalty_bps BETWEEN 0 AND 10000)` | 006 |
| require_official_events | `BOOLEAN NOT NULL DEFAULT FALSE` | 006 |
| min_event_count | `INT NOT NULL DEFAULT 0 CHECK (min_event_count BETWEEN 0 AND 50)` | 006 |
| currency | `VARCHAR(3) NOT NULL DEFAULT 'USD'` | 006 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |

## agency_statements

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| period_id | `UUID NOT NULL REFERENCES payout_periods(id) ON DELETE CASCADE` | 006 |
| agency_id | `UUID NOT NULL REFERENCES agencies(id)` | 006 |
| team_diamonds | `BIGINT NOT NULL DEFAULT 0` | 006 |
| host_count | `INT NOT NULL DEFAULT 0` | 006 |
| commission_bps | `INT NOT NULL DEFAULT 0` | 006 |
| commission_diamonds | `BIGINT NOT NULL DEFAULT 0` | 006 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','void'))` | 006 |
| paid_at | `TIMESTAMPTZ` | 006 |
| paid_by | `UUID REFERENCES users(id)` | 006 |

Kısıtlar: `UNIQUE (period_id, agency_id)`

İndeksler:
- `idx_agency_statements_agency (agency_id)`

## announcements

Oluşturan: `009_feed_banners_announcements.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 009 |
| kind | `VARCHAR(10) NOT NULL CHECK (kind IN ('team', 'event', 'reward'))` | 009 |
| title | `VARCHAR(80) NOT NULL` | 009 |
| body | `TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000)` | 009 |
| created_by | `UUID REFERENCES users(id) ON DELETE SET NULL` | 009 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |

İndeksler:
- `announcements_idx (kind, created_at DESC)`

## app_config

Oluşturan: `027_sessions_presence_moderation.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| key | `VARCHAR(40) PRIMARY KEY` | 027 |
| value | `JSONB NOT NULL` | 027 |
| updated_by | `UUID REFERENCES users(id) ON DELETE SET NULL` | 027 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 027 |

## banners

Oluşturan: `009_feed_banners_announcements.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 009 |
| image_url | `TEXT NOT NULL` | 009 |
| title | `VARCHAR(80)` | 009 |
| link_url | `TEXT` | 009 |
| sort_order | `INT NOT NULL DEFAULT 0` | 009 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 009 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |

## broadcast_sessions

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 004 |
| user_id | `UUID NOT NULL REFERENCES users(id)` | 004 |
| room_id | `UUID REFERENCES rooms(id)` | 004 |
| agency_id | `UUID REFERENCES agencies(id) ON DELETE SET NULL` | 004 |
| started_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |
| ended_at | `TIMESTAMPTZ` | 004 |

İndeksler:
- `idx_broadcast_sessions_user (user_id, started_at DESC)`
- `idx_broadcast_sessions_open (room_id) WHERE ended_at IS NULL`

## broadcasters

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE` | 004 |
| agency_id | `UUID REFERENCES agencies(id) ON DELETE SET NULL` | 004 |
| status | `VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','suspended'))` | 004 |
| applied_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |
| approved_by | `UUID REFERENCES users(id)` | 004 |
| approved_at | `TIMESTAMPTZ` | 004 |
| joined_agency_at | `TIMESTAMPTZ` | 004 |
| contract_tier | `INT` | 006 |

İndeksler:
- `idx_broadcasters_agency (agency_id)`

## client_errors

Oluşturan: `027_sessions_presence_moderation.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `BIGSERIAL PRIMARY KEY` | 027 |
| user_id | `UUID REFERENCES users(id) ON DELETE SET NULL` | 027 |
| app_version | `VARCHAR(20)` | 027 |
| device | `VARCHAR(80)` | 027 |
| source | `VARCHAR(80) NOT NULL` | 027 |
| message | `VARCHAR(1000) NOT NULL` | 027 |
| stack | `VARCHAR(2000)` | 027 |
| occurred_at | `TIMESTAMPTZ` | 027 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 027 |

İndeksler:
- `idx_client_errors_created (created_at DESC)`

## coin_packages

Oluşturan: `024_levels_packages_support.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 024 |
| coins | `BIGINT NOT NULL CHECK (coins > 0)` | 024 |
| price_cents | `BIGINT NOT NULL CHECK (price_cents >= 0)` | 024 |
| currency | `VARCHAR(3) NOT NULL DEFAULT 'TRY'` | 024 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 024 |
| sort_order | `INT NOT NULL DEFAULT 0` | 024 |

## daily_progress

Oluşturan: `016_daily_luckybag.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 016 |
| day | `DATE NOT NULL` | 016 |
| task_key | `VARCHAR(30) NOT NULL` | 016 |
| count | `INT NOT NULL DEFAULT 0` | 016 |
| done | `BOOLEAN NOT NULL DEFAULT FALSE` | 016 |

Kısıtlar: `PRIMARY KEY (user_id, day, task_key)`

## daily_streak

Oluşturan: `016_daily_luckybag.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE` | 016 |
| streak | `INT NOT NULL DEFAULT 0` | 016 |
| last_day | `DATE` | 016 |

## dealer_accounts

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| name | `VARCHAR(100) NOT NULL` | 002 |
| owner_user_id | `UUID REFERENCES users(id)` | 002 |
| coin_balance | `BIGINT NOT NULL DEFAULT 0` | 002 |
| commission_bps | `INT NOT NULL DEFAULT 0` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |

## dealer_transactions

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| dealer_id | `UUID NOT NULL REFERENCES dealer_accounts(id)` | 002 |
| admin_id | `UUID REFERENCES users(id)` | 002 |
| user_id | `UUID REFERENCES users(id)` | 002 |
| type | `VARCHAR(30) NOT NULL` | 002 |
| coin_amount | `BIGINT NOT NULL` | 002 |
| description | `TEXT` | 002 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |

İndeksler:
- `idx_dealer_transactions_dealer_created (dealer_id,created_at DESC)`

## direct_messages

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| sender_id | `UUID NOT NULL REFERENCES users(id)` | 005 |
| receiver_id | `UUID NOT NULL REFERENCES users(id)` | 005 |
| body | `VARCHAR(1000) NOT NULL` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |
| read_at | `TIMESTAMPTZ` | 005 |

Kısıtlar: `CHECK (sender_id <> receiver_id)`

İndeksler:
- `idx_dm_pair (sender_id, receiver_id, created_at DESC)`
- `idx_dm_receiver (receiver_id, sender_id, created_at DESC)`
- `idx_dm_unread (receiver_id) WHERE read_at IS NULL`
- `idx_direct_messages_created (created_at)`

## entrance_effects

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| name | `VARCHAR(100) NOT NULL` | 002 |
| animation_url | `TEXT NOT NULL` | 002 |
| duration_ms | `INT NOT NULL DEFAULT 4000` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |

## families

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| name | `VARCHAR(80) UNIQUE NOT NULL` | 002 |
| logo_url | `TEXT` | 002 |
| owner_id | `UUID NOT NULL REFERENCES users(id)` | 002 |
| level | `INT NOT NULL DEFAULT 1` | 002 |
| total_points | `BIGINT NOT NULL DEFAULT 0` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |
| description | `TEXT` | 004 |

İndeksler:
- `UNIQUE idx_families_name_active (lower(name)) WHERE is_active = TRUE`

## family_members

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| family_id | `UUID REFERENCES families(id) ON DELETE CASCADE` | 002 |
| user_id | `UUID REFERENCES users(id) ON DELETE CASCADE` | 002 |
| role | `VARCHAR(20) NOT NULL DEFAULT 'member'` | 002 |
| joined_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |

Kısıtlar: `PRIMARY KEY(family_id,user_id)`

İndeksler:
- `UNIQUE idx_family_members_one_family_per_user (user_id)`

## favorite_hosts

Oluşturan: `008_favorites_recent_mic_queue.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 008 |
| host_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 008 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 008 |

Kısıtlar: `PRIMARY KEY(user_id, host_id)`, `CHECK (user_id <> host_id)`

## financial_audit_logs

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| admin_id | `UUID REFERENCES users(id)` | 001 |
| user_id | `UUID REFERENCES users(id)` | 001 |
| action | `VARCHAR(80) NOT NULL` | 001 |
| reference_type | `VARCHAR(50)` | 001 |
| reference_id | `TEXT` | 001 |
| amount_coins | `BIGINT DEFAULT 0` | 001 |
| amount_diamonds | `BIGINT DEFAULT 0` | 001 |
| balance_before | `BIGINT` | 001 |
| balance_after | `BIGINT` | 001 |
| metadata | `JSONB` | 001 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 001 |

İndeksler:
- `idx_financial_audit_user_created (user_id,created_at DESC)`
- `idx_audit_created (created_at DESC)`

## firewall_blocks

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| ip | `INET NOT NULL UNIQUE` | 005 |
| reason | `VARCHAR(200)` | 005 |
| expires_at | `TIMESTAMPTZ` | 005 |
| created_by | `UUID REFERENCES users(id)` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

## follows

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| follower_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 004 |
| followed_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 004 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |

Kısıtlar: `PRIMARY KEY(follower_id, followed_id)`, `CHECK (follower_id <> followed_id)`

İndeksler:
- `idx_follows_followed (followed_id, created_at DESC)`

## frames

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| name | `VARCHAR(100) NOT NULL` | 002 |
| image_url | `TEXT NOT NULL` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |

## friend_requests

Oluşturan: `021_friends.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| requester_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 021 |
| target_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 021 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted'))` | 021 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 021 |
| responded_at | `TIMESTAMPTZ` | 021 |

Kısıtlar: `PRIMARY KEY(requester_id, target_id)`, `CHECK (requester_id <> target_id)`

İndeksler:
- `idx_friend_requests_target (target_id, status)`
- `idx_friend_requests_requester (requester_id, status)`

## gift_transactions

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| room_id | `UUID REFERENCES rooms(id)` | 001 |
| sender_id | `UUID REFERENCES users(id)` | 001 |
| receiver_id | `UUID REFERENCES users(id)` | 001 |
| gift_id | `UUID REFERENCES gifts(id)` | 001 |
| quantity | `BIGINT NOT NULL CHECK(quantity>0)` | 001 |
| coin_amount | `BIGINT NOT NULL CHECK(coin_amount>0)` | 001 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 001 |
| receiver_agency_id | `UUID REFERENCES agencies(id) ON DELETE SET NULL` | 006 |
| diamond_amount | `BIGINT` | 029 |

İndeksler:
- `idx_gift_transactions_room_created (room_id,created_at DESC)`
- `idx_gift_tx_receiver_time (receiver_id, created_at)`
- `idx_gift_tx_agency_time (receiver_agency_id, created_at) WHERE receiver_agency_id IS NOT NULL`
- `idx_gift_tx_created (created_at DESC)`

## gifts

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| name | `VARCHAR(80) NOT NULL` | 001 |
| coin_price | `BIGINT NOT NULL CHECK(coin_price>0)` | 001 |
| icon_url | `TEXT` | 001 |
| animation_url | `TEXT` | 001 |
| animation_format | `VARCHAR(20) DEFAULT 'lottie'` | 001 |
| has_alpha | `BOOLEAN DEFAULT TRUE` | 001 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 001 |
| category | `VARCHAR(20) NOT NULL DEFAULT 'popular' CHECK (category IN ('event', 'popular', 'private', 'vip'))` | 012 |

## global_gift_events

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| gift_transaction_id | `UUID REFERENCES gift_transactions(id)` | 002 |
| room_id | `UUID REFERENCES rooms(id)` | 002 |
| sender_id | `UUID REFERENCES users(id)` | 002 |
| receiver_id | `UUID REFERENCES users(id)` | 002 |
| coin_amount | `BIGINT NOT NULL` | 002 |
| display_level | `INT NOT NULL DEFAULT 1` | 002 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |

İndeksler:
- `idx_global_gift_created (created_at DESC)`

## host_salary_tiers

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| level | `INT PRIMARY KEY CHECK (level BETWEEN 1 AND 10)` | 006 |
| required_hours | `INT NOT NULL CHECK (required_hours >= 0)` | 006 |
| required_diamonds | `BIGINT NOT NULL CHECK (required_diamonds >= 0)` | 006 |
| salary_cents | `BIGINT NOT NULL CHECK (salary_cents >= 0)` | 006 |

## host_statements

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| period_id | `UUID NOT NULL REFERENCES payout_periods(id) ON DELETE CASCADE` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id)` | 006 |
| agency_id | `UUID REFERENCES agencies(id) ON DELETE SET NULL` | 006 |
| seconds | `BIGINT NOT NULL DEFAULT 0` | 006 |
| diamonds | `BIGINT NOT NULL DEFAULT 0` | 006 |
| tier_level | `INT` | 006 |
| base_salary_cents | `BIGINT NOT NULL DEFAULT 0` | 006 |
| penalty_applied | `BOOLEAN NOT NULL DEFAULT FALSE` | 006 |
| salary_cents | `BIGINT NOT NULL DEFAULT 0` | 006 |
| events_ok | `BOOLEAN NOT NULL DEFAULT TRUE` | 006 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','void'))` | 006 |
| paid_at | `TIMESTAMPTZ` | 006 |
| paid_by | `UUID REFERENCES users(id)` | 006 |

Kısıtlar: `UNIQUE (period_id, user_id)`

İndeksler:
- `idx_host_statements_user (user_id)`

## idempotency_keys

Oluşturan: `028_idempotency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 028 |
| key | `VARCHAR(64) NOT NULL` | 028 |
| endpoint | `VARCHAR(60) NOT NULL` | 028 |
| status_code | `INT` | 028 |
| response | `JSONB` | 028 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 028 |

Kısıtlar: `PRIMARY KEY (user_id, key)`

İndeksler:
- `idx_idempotency_created (created_at)`

## inventory_items

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 002 |
| item_type | `VARCHAR(30) NOT NULL` | 002 |
| item_key | `VARCHAR(100) NOT NULL` | 002 |
| item_name | `VARCHAR(120) NOT NULL` | 002 |
| quantity | `INT NOT NULL DEFAULT 1` | 002 |
| starts_at | `TIMESTAMPTZ` | 002 |
| expires_at | `TIMESTAMPTZ` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |
| metadata | `JSONB` | 002 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 002 |

İndeksler:
- `idx_inventory_user (user_id,is_active)`

## lucky_bag_claims

Oluşturan: `016_daily_luckybag.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| bag_id | `UUID NOT NULL REFERENCES lucky_bags(id) ON DELETE CASCADE` | 016 |
| user_id | `UUID NOT NULL REFERENCES users(id)` | 016 |
| amount | `BIGINT NOT NULL` | 016 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 016 |

Kısıtlar: `PRIMARY KEY (bag_id, user_id)`

## lucky_bags

Oluşturan: `016_daily_luckybag.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 016 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 016 |
| sender_id | `UUID NOT NULL REFERENCES users(id)` | 016 |
| kind | `VARCHAR(10) NOT NULL CHECK (kind IN ('normal','super'))` | 016 |
| tier | `VARCHAR(10) NOT NULL` | 016 |
| total_coins | `BIGINT NOT NULL CHECK (total_coins > 0)` | 016 |
| slots | `INT NOT NULL CHECK (slots > 0)` | 016 |
| amounts | `BIGINT[] NOT NULL` | 016 |
| claimed_count | `INT NOT NULL DEFAULT 0` | 016 |
| note | `VARCHAR(100)` | 016 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open','done','expired'))` | 016 |
| expires_at | `TIMESTAMPTZ NOT NULL` | 016 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 016 |
| opens_at | `TIMESTAMPTZ` | 017 |

İndeksler:
- `idx_lucky_open (status, expires_at)`
- `idx_lucky_room (room_id, status)`

## media_files

Oluşturan: `018_media_files.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 018 |
| kind | `VARCHAR(20) NOT NULL` | 018 |
| mime | `VARCHAR(60) NOT NULL` | 018 |
| ext | `VARCHAR(8) NOT NULL` | 018 |
| size_bytes | `INT NOT NULL` | 018 |
| data | `BYTEA NOT NULL` | 018 |
| meta | `JSONB NOT NULL DEFAULT '{}'::jsonb` | 018 |
| created_by | `UUID` | 018 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 018 |

İndeksler:
- `idx_media_created_by (created_by) WHERE created_by IS NOT NULL`

## mic_sessions

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 006 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| started_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |
| ended_at | `TIMESTAMPTZ` | 006 |

İndeksler:
- `UNIQUE idx_mic_sessions_open (user_id, room_id) WHERE ended_at IS NULL`
- `idx_mic_sessions_user_time (user_id, started_at DESC)`

## moderation_strikes

Oluşturan: `027_sessions_presence_moderation.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `BIGSERIAL PRIMARY KEY` | 027 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 027 |
| kind | `VARCHAR(20) NOT NULL` | 027 |
| context | `VARCHAR(20) NOT NULL` | 027 |
| sample | `VARCHAR(300)` | 027 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 027 |

İndeksler:
- `idx_strikes_user (user_id, created_at DESC)`
- `idx_strikes_created (created_at DESC)`

## music_tracks

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| title | `VARCHAR(120) NOT NULL` | 005 |
| artist | `VARCHAR(120)` | 005 |
| url | `TEXT NOT NULL` | 005 |
| cover_url | `TEXT` | 005 |
| duration_ms | `INT NOT NULL CHECK (duration_ms > 0 AND duration_ms <= 7200000)` | 005 |
| license_note | `TEXT NOT NULL` | 005 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 005 |
| created_by | `UUID REFERENCES users(id)` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |
| is_temp | `BOOLEAN NOT NULL DEFAULT FALSE` | 014 |
| owner_room_id | `UUID REFERENCES rooms(id) ON DELETE CASCADE` | 014 |
| expires_at | `TIMESTAMPTZ` | 014 |
| size_bytes | `INT` | 014 |

İndeksler:
- `idx_music_tracks_active (is_active, title)`
- `idx_music_tracks_temp (is_temp, expires_at) WHERE is_temp`

## official_event_attendance

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| event_id | `UUID NOT NULL REFERENCES official_events(id) ON DELETE CASCADE` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 006 |
| marked_by | `UUID REFERENCES users(id)` | 006 |
| marked_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |

Kısıtlar: `PRIMARY KEY (event_id, user_id)`

## official_events

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| title | `VARCHAR(120) NOT NULL` | 006 |
| starts_at | `TIMESTAMPTZ NOT NULL` | 006 |
| created_by | `UUID REFERENCES users(id)` | 006 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |

## payout_periods

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| period_key | `VARCHAR(16) NOT NULL UNIQUE` | 006 |
| cycle | `VARCHAR(10) NOT NULL CHECK (cycle IN ('weekly','monthly'))` | 006 |
| starts_at | `TIMESTAMPTZ NOT NULL` | 006 |
| ends_at | `TIMESTAMPTZ NOT NULL` | 006 |
| closed_by | `UUID REFERENCES users(id)` | 006 |
| closed_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |
| config | `JSONB NOT NULL DEFAULT '{}'::jsonb` | 006 |

## pk_battles

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| room_a | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| room_b | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| host_a | `UUID NOT NULL REFERENCES users(id)` | 006 |
| host_b | `UUID NOT NULL REFERENCES users(id)` | 006 |
| status | `VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','declined','cancelled'))` | 006 |
| duration_seconds | `INT NOT NULL CHECK (duration_seconds BETWEEN 60 AND 1800)` | 006 |
| score_a | `BIGINT NOT NULL DEFAULT 0 CHECK (score_a >= 0)` | 006 |
| score_b | `BIGINT NOT NULL DEFAULT 0 CHECK (score_b >= 0)` | 006 |
| winner_room | `UUID REFERENCES rooms(id)` | 006 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |
| started_at | `TIMESTAMPTZ` | 006 |
| ends_at | `TIMESTAMPTZ` | 006 |
| finished_at | `TIMESTAMPTZ` | 006 |

Kısıtlar: `CHECK (room_a <> room_b)`

İndeksler:
- `idx_pk_open_a (room_a) WHERE status IN ('pending','active')`
- `idx_pk_open_b (room_b) WHERE status IN ('pending','active')`

## pk_supporters

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| battle_id | `UUID NOT NULL REFERENCES pk_battles(id) ON DELETE CASCADE` | 006 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 006 |
| coins | `BIGINT NOT NULL DEFAULT 0 CHECK (coins >= 0)` | 006 |

Kısıtlar: `PRIMARY KEY (battle_id, user_id)`

## post_comments

Oluşturan: `009_feed_banners_announcements.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 009 |
| post_id | `UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE` | 009 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 009 |
| body | `TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 300)` | 009 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |

İndeksler:
- `post_comments_idx (post_id, created_at)`

## post_likes

Oluşturan: `009_feed_banners_announcements.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| post_id | `UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE` | 009 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 009 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |

Kısıtlar: `PRIMARY KEY (post_id, user_id)`

## posts

Oluşturan: `009_feed_banners_announcements.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 009 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 009 |
| body | `TEXT NOT NULL DEFAULT '' CHECK (char_length(body) <= 1000)` | 009 |
| image_url | `TEXT` | 009 |
| like_count | `INT NOT NULL DEFAULT 0 CHECK (like_count >= 0)` | 009 |
| comment_count | `INT NOT NULL DEFAULT 0 CHECK (comment_count >= 0)` | 009 |
| is_removed | `BOOLEAN NOT NULL DEFAULT FALSE` | 009 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |

Kısıtlar: `CHECK (char_length(body) > 0 OR image_url IS NOT NULL)`

İndeksler:
- `posts_created_idx (created_at DESC) WHERE is_removed = FALSE`
- `posts_user_idx (user_id, created_at DESC) WHERE is_removed = FALSE`

## profile_visitors

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| profile_user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 004 |
| visitor_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 004 |
| visit_count | `INT NOT NULL DEFAULT 1` | 004 |
| last_visited_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 004 |

Kısıtlar: `PRIMARY KEY(profile_user_id, visitor_id)`, `CHECK (profile_user_id <> visitor_id)`

İndeksler:
- `idx_profile_visitors_recent (profile_user_id, last_visited_at DESC)`

## recent_rooms

Oluşturan: `008_favorites_recent_mic_queue.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 008 |
| host_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 008 |
| room_name | `VARCHAR(120)` | 008 |
| room_type | `VARCHAR(20)` | 008 |
| visited_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 008 |

Kısıtlar: `PRIMARY KEY(user_id, host_id)`

İndeksler:
- `idx_recent_rooms_user (user_id, visited_at DESC)`

## reports

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| reporter_id | `UUID NOT NULL REFERENCES users(id)` | 005 |
| kind | `VARCHAR(20) NOT NULL CHECK (kind IN ('user','room','room_message','dm'))` | 005 |
| target_user_id | `UUID REFERENCES users(id)` | 005 |
| room_id | `UUID REFERENCES rooms(id)` | 005 |
| message_id | `UUID` | 005 |
| reason | `VARCHAR(30) NOT NULL` | 005 |
| details | `VARCHAR(500)` | 005 |
| status | `VARCHAR(12) NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','dismissed'))` | 005 |
| resolved_by | `UUID REFERENCES users(id)` | 005 |
| resolved_note | `VARCHAR(300)` | 005 |
| resolved_at | `TIMESTAMPTZ` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

İndeksler:
- `idx_reports_status (status, created_at DESC)`

## room_blocks

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID REFERENCES rooms(id) ON DELETE CASCADE` | 001 |
| blocked_user_id | `UUID REFERENCES users(id) ON DELETE CASCADE` | 001 |
| blocked_by_user_id | `UUID REFERENCES users(id)` | 001 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 001 |

Kısıtlar: `PRIMARY KEY(room_id,blocked_user_id)`

## room_game_players

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| game_id | `UUID NOT NULL REFERENCES room_games(id) ON DELETE CASCADE` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 006 |
| seat | `INT NOT NULL CHECK (seat BETWEEN 0 AND 3)` | 006 |
| joined_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |

Kısıtlar: `PRIMARY KEY (game_id, user_id)`, `UNIQUE (game_id, seat)`

## room_games

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 006 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| game_type | `VARCHAR(20) NOT NULL DEFAULT 'ludo' CHECK (game_type IN ('ludo'))` | 006 |
| status | `VARCHAR(12) NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','playing','finished','cancelled'))` | 006 |
| state | `JSONB NOT NULL DEFAULT '{}'::jsonb` | 006 |
| created_by | `UUID NOT NULL REFERENCES users(id)` | 006 |
| winner_id | `UUID REFERENCES users(id)` | 006 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |
| started_at | `TIMESTAMPTZ` | 006 |
| finished_at | `TIMESTAMPTZ` | 006 |

İndeksler:
- `UNIQUE idx_room_games_open (room_id) WHERE status IN ('waiting','playing')`

## room_gift_totals

Oluşturan: `006_room_features_pk_games_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 006 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 006 |
| total_coins | `BIGINT NOT NULL DEFAULT 0 CHECK (total_coins >= 0)` | 006 |
| total_count | `BIGINT NOT NULL DEFAULT 0 CHECK (total_count >= 0)` | 006 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 006 |

Kısıtlar: `PRIMARY KEY (room_id, user_id)`

## room_members

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID REFERENCES rooms(id) ON DELETE CASCADE` | 001 |
| user_id | `UUID REFERENCES users(id) ON DELETE CASCADE` | 001 |
| role | `VARCHAR(20) NOT NULL DEFAULT 'user'` | 001 |
| microphone | `BOOLEAN NOT NULL DEFAULT FALSE` | 001 |
| seat_index | `INT` | 001 |
| joined_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 001 |
| chat_muted_until | `TIMESTAMPTZ` | 005 |
| last_seen_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 013 |

Kısıtlar: `PRIMARY KEY(room_id,user_id)`, `UNIQUE(room_id,seat_index)`

İndeksler:
- `idx_room_members_user (user_id)`

## room_messages

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 005 |
| user_id | `UUID NOT NULL REFERENCES users(id)` | 005 |
| body | `VARCHAR(300) NOT NULL` | 005 |
| deleted | `BOOLEAN NOT NULL DEFAULT FALSE` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

İndeksler:
- `idx_room_messages_room (room_id, created_at DESC)`
- `idx_room_messages_created (created_at)`

## room_mic_queue

Oluşturan: `008_favorites_recent_mic_queue.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 008 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 008 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 008 |

Kısıtlar: `PRIMARY KEY(room_id, user_id)`

İndeksler:
- `idx_room_mic_queue_order (room_id, created_at)`

## room_music

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE` | 005 |
| track_id | `UUID REFERENCES music_tracks(id)` | 005 |
| status | `VARCHAR(10) NOT NULL DEFAULT 'stopped' CHECK (status IN ('playing','paused','stopped'))` | 005 |
| position_ms | `INT NOT NULL DEFAULT 0 CHECK (position_ms >= 0)` | 005 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |
| controlled_by | `UUID REFERENCES users(id)` | 005 |

## room_music_queue

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 005 |
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 005 |
| track_id | `UUID NOT NULL REFERENCES music_tracks(id)` | 005 |
| added_by | `UUID NOT NULL REFERENCES users(id)` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

İndeksler:
- `idx_room_music_queue_room (room_id, created_at)`

## room_mutes

Oluşturan: `026_hardening.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| room_id | `UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE` | 026 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 026 |
| until | `TIMESTAMPTZ NOT NULL` | 026 |

Kısıtlar: `PRIMARY KEY (room_id, user_id)`

## room_profiles

Oluşturan: `011_room_profiles_staff.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| owner_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 011 |
| room_type | `VARCHAR(20) NOT NULL CHECK (room_type IN ('audio', 'video'))` | 011 |
| name | `VARCHAR(120) NOT NULL` | 011 |
| tags | `TEXT[] NOT NULL DEFAULT '{}'` | 011 |
| seat_count | `INT NOT NULL DEFAULT 8 CHECK (seat_count IN (2, 4, 5, 6, 8, 9, 12, 15, 20))` | 011 |
| theme | `VARCHAR(20) NOT NULL DEFAULT 'default'` | 011 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 011 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 011 |
| room_number | `VARCHAR(12)` | 015 |
| announcement | `VARCHAR(200)` | 017 |
| cover_url | `TEXT` | 017 |

Kısıtlar: `PRIMARY KEY (owner_id, room_type)`

İndeksler:
- `UNIQUE idx_room_profiles_number (room_number)`

## room_staff

Oluşturan: `011_room_profiles_staff.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| owner_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 011 |
| room_type | `VARCHAR(20) NOT NULL CHECK (room_type IN ('audio', 'video'))` | 011 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 011 |
| role | `VARCHAR(20) NOT NULL CHECK (role IN ('cohost', 'moderator'))` | 011 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 011 |

Kısıtlar: `PRIMARY KEY (owner_id, room_type, user_id)`

## rooms

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| name | `VARCHAR(120) NOT NULL` | 001 |
| room_type | `VARCHAR(20) NOT NULL DEFAULT 'audio'` | 001 |
| seat_count | `INT NOT NULL DEFAULT 8 CHECK(seat_count IN(2,5,8,9,12,15,20))` | 001 |
| owner_id | `UUID NOT NULL REFERENCES users(id)` | 001 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 001 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 001 |
| closed_at | `TIMESTAMPTZ` | 004 |
| tags | `TEXT[] NOT NULL DEFAULT '{}'` | 005 |
| password_hash | `TEXT` | 005 |
| chat_enabled | `BOOLEAN NOT NULL DEFAULT TRUE` | 005 |
| is_hidden | `BOOLEAN NOT NULL DEFAULT FALSE` | 006 |
| join_code | `VARCHAR(8)` | 006 |
| theme | `VARCHAR(20) NOT NULL DEFAULT 'default'` | 006 |
| theme_image_url | `TEXT` | 006 |
| scoreboard_enabled | `BOOLEAN NOT NULL DEFAULT TRUE` | 006 |
| locked_seats | `INT[] NOT NULL DEFAULT '{}'` | 007 |
| room_number | `VARCHAR(12)` | 015 |
| announcement | `VARCHAR(200)` | 017 |
| cover_url | `TEXT` | 017 |
| mic_request | `BOOLEAN NOT NULL DEFAULT FALSE` | 025 |

İndeksler:
- `UNIQUE idx_rooms_join_code (join_code) WHERE join_code IS NOT NULL AND is_active = TRUE`
- `idx_rooms_number (room_number)`

## security_events

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `BIGSERIAL PRIMARY KEY` | 005 |
| event_type | `VARCHAR(40) NOT NULL` | 005 |
| ip | `INET` | 005 |
| user_id | `UUID` | 005 |
| detail | `JSONB NOT NULL DEFAULT '{}'::jsonb` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

İndeksler:
- `idx_security_events_time (created_at DESC)`
- `idx_security_events_type (event_type, created_at DESC)`

## store_items

Oluşturan: `022_store.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 022 |
| category | `VARCHAR(30) NOT NULL CHECK (category IN ('frame','chat_bubble','entrance_effect','mini_card','mic_wave','vehicle'))` | 022 |
| name | `VARCHAR(100) NOT NULL` | 022 |
| image_url | `TEXT NOT NULL` | 022 |
| ref_id | `UUID` | 022 |
| price_coins | `BIGINT NOT NULL CHECK (price_coins >= 0)` | 022 |
| duration_days | `INT NOT NULL DEFAULT 14 CHECK (duration_days BETWEEN 1 AND 3650)` | 022 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 022 |
| sort_order | `INT NOT NULL DEFAULT 0` | 022 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 022 |
| for_sale | `BOOLEAN NOT NULL DEFAULT TRUE` | 023 |

İndeksler:
- `idx_store_items_cat (category, is_active, sort_order, created_at DESC)`

## support_messages

Oluşturan: `024_levels_packages_support.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 024 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 024 |
| from_staff | `BOOLEAN NOT NULL DEFAULT FALSE` | 024 |
| staff_id | `UUID REFERENCES users(id) ON DELETE SET NULL` | 024 |
| category | `VARCHAR(40)` | 024 |
| body | `TEXT NOT NULL` | 024 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 024 |
| read_at | `TIMESTAMPTZ` | 024 |

İndeksler:
- `idx_support_user (user_id, created_at DESC)`

## upload_owners

Oluşturan: `026_hardening.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| url | `TEXT PRIMARY KEY` | 026 |
| owner_id | `UUID REFERENCES users(id) ON DELETE SET NULL` | 026 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 026 |

## user_blocks

Oluşturan: `005_music_chat_social_security.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| blocker_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 005 |
| blocked_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 005 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 005 |

Kısıtlar: `PRIMARY KEY (blocker_id, blocked_id)`, `CHECK (blocker_id <> blocked_id)`

İndeksler:
- `idx_user_blocks_blocked (blocked_id)`

## user_sessions

Oluşturan: `027_sessions_presence_moderation.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 027 |
| user_id | `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 027 |
| refresh_hash | `CHAR(64) NOT NULL` | 027 |
| prev_hash | `CHAR(64)` | 027 |
| rotated_at | `TIMESTAMPTZ` | 027 |
| device_id | `VARCHAR(64)` | 027 |
| device_name | `VARCHAR(80)` | 027 |
| platform | `VARCHAR(20)` | 027 |
| app_version | `VARCHAR(20)` | 027 |
| emulator | `BOOLEAN NOT NULL DEFAULT FALSE` | 027 |
| ip | `VARCHAR(64)` | 027 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 027 |
| last_used_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 027 |
| expires_at | `TIMESTAMPTZ NOT NULL` | 027 |
| revoked_at | `TIMESTAMPTZ` | 027 |
| revoke_reason | `VARCHAR(30)` | 027 |
| legacy_hash | `CHAR(64)` | 027 |

İndeksler:
- `UNIQUE idx_sessions_refresh (refresh_hash)`
- `idx_sessions_prev (prev_hash) WHERE prev_hash IS NOT NULL`
- `idx_sessions_user (user_id, last_used_at DESC)`
- `idx_sessions_device (device_id) WHERE device_id IS NOT NULL`
- `UNIQUE idx_sessions_legacy (legacy_hash) WHERE legacy_hash IS NOT NULL`

## user_wip

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| user_id | `UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE` | 002 |
| level | `INT NOT NULL DEFAULT 1` | 002 |
| starts_at | `TIMESTAMPTZ NOT NULL` | 002 |
| expires_at | `TIMESTAMPTZ NOT NULL` | 002 |
| is_active | `BOOLEAN NOT NULL DEFAULT TRUE` | 002 |

İndeksler:
- `idx_user_wip_active (user_id,is_active,expires_at)`

## users

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| username | `VARCHAR(40) UNIQUE NOT NULL` | 001 |
| display_name | `VARCHAR(80) NOT NULL` | 001 |
| password_hash | `TEXT` | 001 |
| avatar_url | `TEXT` | 001 |
| bio | `TEXT` | 001 |
| language | `VARCHAR(10) NOT NULL DEFAULT 'tr'` | 001 |
| coins | `BIGINT NOT NULL DEFAULT 0` | 001 |
| diamonds | `BIGINT NOT NULL DEFAULT 0` | 001 |
| total_sent_coins | `BIGINT NOT NULL DEFAULT 0` | 001 |
| total_received_diamonds | `BIGINT NOT NULL DEFAULT 0` | 001 |
| coin_level | `INT NOT NULL DEFAULT 1` | 001 |
| gift_level | `INT NOT NULL DEFAULT 1` | 001 |
| is_hidden | `BOOLEAN NOT NULL DEFAULT FALSE` | 001 |
| account_status | `VARCHAR(20) NOT NULL DEFAULT 'active'` | 001 |
| system_role | `VARCHAR(20) NOT NULL DEFAULT 'user'` | 001 |
| created_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 001 |
| updated_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 001 |
| cover_url | `TEXT` | 004 |
| gender | `VARCHAR(10)` | 004 |
| birth_date | `DATE` | 004 |
| country | `VARCHAR(60)` | 004 |
| city | `VARCHAR(60)` | 004 |
| token_version | `INT NOT NULL DEFAULT 0` | 004 |
| last_seen_at | `TIMESTAMPTZ` | 004 |
| who_can_dm | `VARCHAR(10) NOT NULL DEFAULT 'everyone'` | 005 |
| kyc_status | `VARCHAR(12) NOT NULL DEFAULT 'none' CHECK (kyc_status IN ('none','pending','approved','rejected'))` | 006 |
| banned_until | `TIMESTAMPTZ` | 007 |
| ban_reason | `TEXT` | 007 |
| banned_by | `UUID REFERENCES users(id)` | 007 |
| announcements_seen_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 009 |
| public_id | `VARCHAR(20)` | 015 |
| xp | `BIGINT NOT NULL DEFAULT 0` | 016 |
| avatar_animated | `BOOLEAN NOT NULL DEFAULT FALSE` | 020 |
| static_avatar_url | `TEXT` | 020 |
| visitors_seen_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 021 |
| followers_seen_at | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` | 021 |
| show_presence | `BOOLEAN NOT NULL DEFAULT TRUE` | 027 |
| chat_restricted_until | `TIMESTAMPTZ` | 027 |
| ghost_mode | `BOOLEAN NOT NULL DEFAULT FALSE` | 029 |

İndeksler:
- `UNIQUE idx_users_username_lower (lower(username))`
- `idx_users_banned_until (banned_until) WHERE account_status = 'banned' AND banned_until IS NOT NULL`
- `UNIQUE idx_users_public_id (public_id)`
- `idx_users_created (created_at DESC)`
- `idx_users_last_seen (last_seen_at DESC) WHERE last_seen_at IS NOT NULL`
- `idx_users_ghost (id) WHERE ghost_mode`

## wallet_transactions

Oluşturan: `001_core.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 001 |
| user_id | `UUID REFERENCES users(id)` | 001 |
| transaction_type | `VARCHAR(50) NOT NULL` | 001 |
| coin_amount | `BIGINT DEFAULT 0` | 001 |
| diamond_amount | `BIGINT DEFAULT 0` | 001 |
| reference_id | `TEXT` | 001 |
| description | `TEXT` | 001 |
| created_at | `TIMESTAMPTZ DEFAULT NOW()` | 001 |

İndeksler:
- `idx_wallet_user_created (user_id, created_at DESC)`

## wip_plans

Oluşturan: `002_social_inventory.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| id | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | 002 |
| name | `VARCHAR(100) NOT NULL` | 002 |
| level | `INT NOT NULL DEFAULT 1` | 002 |
| duration_days | `INT NOT NULL` | 002 |
| price_coins | `BIGINT NOT NULL DEFAULT 0` | 002 |
| is_active | `BOOLEAN DEFAULT TRUE` | 002 |

## wip_tiers

Oluşturan: `004_profile_wip_agency.sql`

| Sütun | Tür / kural | Ekleyen |
|---|---|---|
| level | `INT PRIMARY KEY CHECK (level BETWEEN 1 AND 5)` | 004 |
| name | `VARCHAR(60) NOT NULL` | 004 |
| features | `JSONB NOT NULL DEFAULT '{}'::jsonb` | 004 |

