-- =====================================================================
-- Migration: Complete Instagram-Style Social Follow, Friend Requests,
-- Direct Messaging & User Blocking System for Baatkry
-- =====================================================================

-- 1. Ensure public.profiles has unique username and social fields
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS username TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS username_updated_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS daily_claim_streak INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_daily_claim_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS vip_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_username_lower ON public.profiles (LOWER(username));

-- 2. User Follows Table (Instagram unidirectional following)
CREATE TABLE IF NOT EXISTS public.user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON public.user_follows (follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_following ON public.user_follows (following_id);

-- 3. Friend Requests Table (incoming requests with accept & follow back)
CREATE TABLE IF NOT EXISTS public.friend_requests (
    id TEXT PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_name TEXT NOT NULL,
    sender_avatar TEXT,
    sender_is_vip BOOLEAN DEFAULT false,
    receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    receiver_name TEXT NOT NULL,
    receiver_avatar TEXT,
    status TEXT DEFAULT 'pending', -- 'pending', 'accepted', 'declined'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver ON public.friend_requests (receiver_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_requests_sender ON public.friend_requests (sender_id, status);

-- 4. Mutual Friends Table (mutual follow / accepted connection)
CREATE TABLE IF NOT EXISTS public.friends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_1 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id_1, user_id_2)
);

CREATE INDEX IF NOT EXISTS idx_friends_user1 ON public.friends (user_id_1);
CREATE INDEX IF NOT EXISTS idx_friends_user2 ON public.friends (user_id_2);

-- 5. 1-on-1 Friend Messages Table (chat & gift messages)
CREATE TABLE IF NOT EXISTS public.friend_messages (
    id TEXT PRIMARY KEY,
    chat_id TEXT NOT NULL,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_name TEXT NOT NULL,
    receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    is_gift BOOLEAN DEFAULT false,
    gift_name TEXT,
    gift_emoji TEXT,
    gift_coins INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_friend_messages_chat ON public.friend_messages (chat_id, created_at);

-- 6. Blocked Users Table (bidirectional safety exclusion)
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_lookup ON public.blocked_users (user_id, blocked_user_id);

-- 7. Enable Row Level Security (RLS) on all social tables
ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- 8. Permissive RLS Policies
-- user_follows policies
DROP POLICY IF EXISTS "Public can view follows" ON public.user_follows;
CREATE POLICY "Public can view follows" ON public.user_follows FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert their own follows" ON public.user_follows;
CREATE POLICY "Users can insert their own follows" ON public.user_follows 
FOR INSERT WITH CHECK (auth.uid() = follower_id OR auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can delete their own follows" ON public.user_follows;
CREATE POLICY "Users can delete their own follows" ON public.user_follows 
FOR DELETE USING (auth.uid() = follower_id);

-- friend_requests policies
DROP POLICY IF EXISTS "Users can view requests related to them" ON public.friend_requests;
CREATE POLICY "Users can view requests related to them" ON public.friend_requests 
FOR SELECT USING (auth.uid() = receiver_id OR auth.uid() = sender_id OR true);

DROP POLICY IF EXISTS "Users can insert requests" ON public.friend_requests;
CREATE POLICY "Users can insert requests" ON public.friend_requests 
FOR INSERT WITH CHECK (auth.uid() = sender_id OR auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can update their requests" ON public.friend_requests;
CREATE POLICY "Users can update their requests" ON public.friend_requests 
FOR UPDATE USING (auth.uid() = receiver_id OR auth.uid() = sender_id);

-- friends policies
DROP POLICY IF EXISTS "Users can view their friendships" ON public.friends;
CREATE POLICY "Users can view their friendships" ON public.friends 
FOR SELECT USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2 OR true);

DROP POLICY IF EXISTS "Users can insert friendships" ON public.friends;
CREATE POLICY "Users can insert friendships" ON public.friends 
FOR INSERT WITH CHECK (auth.uid() = user_id_1 OR auth.uid() = user_id_2 OR auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can delete friendships" ON public.friends;
CREATE POLICY "Users can delete friendships" ON public.friends 
FOR DELETE USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

-- friend_messages policies
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.friend_messages;
CREATE POLICY "Users can view messages in their chats" ON public.friend_messages 
FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR true);

DROP POLICY IF EXISTS "Users can insert messages" ON public.friend_messages;
CREATE POLICY "Users can insert messages" ON public.friend_messages 
FOR INSERT WITH CHECK (auth.uid() = sender_id OR auth.uid() IS NOT NULL);

-- blocked_users policies
DROP POLICY IF EXISTS "Users can manage their blocked list" ON public.blocked_users;
CREATE POLICY "Users can manage their blocked list" ON public.blocked_users 
FOR ALL USING (auth.uid() = user_id OR auth.uid() IS NOT NULL);
