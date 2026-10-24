-- ================================================================
-- Supabase Schema for Monkey & Omegle Video Chat Platform
-- ================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. User Profiles Table (Handles both Anonymous Guests and Registered Users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_anonymous BOOLEAN DEFAULT true,
    nickname TEXT NOT NULL DEFAULT 'Anonymous Monkey',
    avatar_url TEXT,
    gender TEXT DEFAULT 'unspecified', -- 'male', 'female', 'other', 'unspecified'
    interests TEXT[] DEFAULT ARRAY[]::TEXT[],
    coins INTEGER DEFAULT 50, -- Free starter coins
    is_vip BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'offline', -- 'online', 'in_queue', 'in_call', 'offline'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles are viewable by authenticated/anonymous users"
    ON public.profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- 3. Blocked Users Table (Ensures two users never match again)
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, blocked_user_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their blocked list"
    ON public.blocked_users FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can block another user"
    ON public.blocked_users FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 4. User Reports & Moderation Table
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reported_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL, -- 'inappropriate', 'nudity', 'harassment', 'underage', 'spam'
    details TEXT,
    room_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can submit reports"
    ON public.reports FOR INSERT
    WITH CHECK (auth.uid() = reporter_id);

-- 5. Matchmaking Queue Table (Coordinated queue fallback)
CREATE TABLE IF NOT EXISTS public.match_queue (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    mode TEXT NOT NULL DEFAULT 'omegle', -- 'omegle' (instant raw) or 'monkey' (timed/tags)
    interests TEXT[] DEFAULT ARRAY[]::TEXT[],
    gender_filter TEXT DEFAULT 'any',
    status TEXT DEFAULT 'waiting', -- 'waiting', 'matched', 'connected'
    matched_room_id TEXT,
    matched_peer_id UUID REFERENCES auth.users(id),
    joined_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.match_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their queue entry"
    ON public.match_queue FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users can view matching candidates"
    ON public.match_queue FOR SELECT
    USING (true);

-- 6. Purchases & Coin Transactions (Requires Registered Non-Anonymous User)
CREATE TABLE IF NOT EXISTS public.coin_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    package_id TEXT NOT NULL, -- 'pack_100_coins', 'pack_500_coins', 'vip_pass'
    amount_usd NUMERIC(10, 2) NOT NULL,
    coins_added INTEGER NOT NULL,
    payment_status TEXT DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.coin_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own purchase history"
    ON public.coin_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- 7. Trigger to auto-create profile on Auth signup (handles both anonymous & email)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, is_anonymous, nickname, coins)
    VALUES (
        NEW.id,
        COALESCE(NEW.is_anonymous, true),
        CASE
            WHEN NEW.is_anonymous THEN 'Monkey #' || SUBSTRING(NEW.id::TEXT, 1, 6)
            ELSE COALESCE(NEW.raw_user_meta_data->>'full_name', 'User #' || SUBSTRING(NEW.id::TEXT, 1, 6))
        END,
        CASE WHEN NEW.is_anonymous THEN 30 ELSE 100 END
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable Realtime on tables for low latency matching updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.match_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
