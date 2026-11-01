-- ============================================================================
-- Phase 10: Platform Moderation, Security, and Anti-Fraud Migration
-- Baatkry Stranger Video/Text Chat Monetization Platform
-- ============================================================================

-- 1. Extend profiles with moderation ban and suspension flags
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_banned BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;

-- 2. Extend creator_wallets with freeze flag
ALTER TABLE public.creator_wallets
ADD COLUMN IF NOT EXISTS is_frozen BOOLEAN NOT NULL DEFAULT false;

-- 3. Create user_reports table
CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reported_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    details TEXT,
    room_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'investigating', 'resolved', 'dismissed')),
    action_taken TEXT NOT NULL DEFAULT 'none' CHECK (action_taken IN (
        'none', 'warned', 'suspended_24h', 'suspended_7d', 'banned', 'creator_revoked', 'wallet_frozen', 'dismissed'
    )),
    admin_notes TEXT,
    resolved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON public.user_reports(reported_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON public.user_reports(status);
CREATE INDEX IF NOT EXISTS idx_user_reports_created ON public.user_reports(created_at DESC);

-- 4. Create blocked_users table
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_user_block_pair UNIQUE(user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_pair ON public.blocked_users(user_id, blocked_user_id);

-- 5. Create moderation_actions table (itemized moderation audit trail)
CREATE TABLE IF NOT EXISTS public.moderation_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    admin_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action_type TEXT NOT NULL CHECK (action_type IN (
        'ban', 'unban', 'suspend', 'unsuspend', 'revoke_creator', 'freeze_wallet', 'unfreeze_wallet', 'warn', 'dismiss'
    )),
    reason TEXT NOT NULL,
    admin_notes TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mod_actions_target ON public.moderation_actions(target_user_id);
CREATE INDEX IF NOT EXISTS idx_mod_actions_created ON public.moderation_actions(created_at DESC);

-- 6. Create device_fraud_tracking table
CREATE TABLE IF NOT EXISTS public.device_fraud_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_fingerprint TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ip_hash TEXT,
    starter_bonus_claimed BOOLEAN NOT NULL DEFAULT false,
    is_blacklisted BOOLEAN NOT NULL DEFAULT false,
    risk_score INT NOT NULL DEFAULT 0,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_device_user UNIQUE(device_fingerprint, user_id)
);

CREATE INDEX IF NOT EXISTS idx_device_fraud_fingerprint ON public.device_fraud_tracking(device_fingerprint);

-- ============================================================================
-- 7. Moderation Stored Procedures (SECURITY DEFINER)
-- ============================================================================

-- Procedure: Resolve User Report and Apply Moderation Action
CREATE OR REPLACE FUNCTION public.resolve_user_report(
    p_report_id UUID,
    p_action TEXT,
    p_admin_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_admin_id UUID;
    v_report RECORD;
    v_target_user_id UUID;
    v_expires_at TIMESTAMPTZ := NULL;
BEGIN
    v_admin_id := auth.uid();

    -- Verify administrator authorization
    IF NOT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = v_admin_id AND role IN ('admin', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    -- Fetch and lock report
    SELECT * INTO v_report
    FROM public.user_reports
    WHERE id = p_report_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User report with id % not found.', p_report_id;
    END IF;

    v_target_user_id := v_report.reported_id;

    -- Execute specific moderation action
    IF p_action = 'banned' THEN
        UPDATE public.profiles 
        SET is_banned = true, updated_at = now() 
        WHERE id = v_target_user_id;

        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes)
        VALUES (v_target_user_id, v_admin_id, 'ban', v_report.reason, p_admin_notes);

    ELSIF p_action = 'suspended_24h' THEN
        v_expires_at := now() + INTERVAL '24 hours';
        UPDATE public.profiles 
        SET is_suspended = true, suspended_until = v_expires_at, updated_at = now() 
        WHERE id = v_target_user_id;

        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes, expires_at)
        VALUES (v_target_user_id, v_admin_id, 'suspend', v_report.reason, p_admin_notes, v_expires_at);

    ELSIF p_action = 'suspended_7d' THEN
        v_expires_at := now() + INTERVAL '7 days';
        UPDATE public.profiles 
        SET is_suspended = true, suspended_until = v_expires_at, updated_at = now() 
        WHERE id = v_target_user_id;

        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes, expires_at)
        VALUES (v_target_user_id, v_admin_id, 'suspend', v_report.reason, p_admin_notes, v_expires_at);

    ELSIF p_action = 'creator_revoked' THEN
        UPDATE public.creator_profiles 
        SET is_active = false, updated_at = now() 
        WHERE user_id = v_target_user_id;

        UPDATE public.creator_applications 
        SET status = 'rejected', admin_notes = COALESCE(p_admin_notes, 'Revoked due to safety report'), updated_at = now() 
        WHERE user_id = v_target_user_id;

        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes)
        VALUES (v_target_user_id, v_admin_id, 'revoke_creator', v_report.reason, p_admin_notes);

    ELSIF p_action = 'wallet_frozen' THEN
        UPDATE public.creator_wallets 
        SET is_frozen = true, updated_at = now() 
        WHERE creator_id = v_target_user_id;

        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes)
        VALUES (v_target_user_id, v_admin_id, 'freeze_wallet', v_report.reason, p_admin_notes);

    ELSIF p_action = 'dismissed' THEN
        INSERT INTO public.moderation_actions (target_user_id, admin_id, action_type, reason, admin_notes)
        VALUES (v_target_user_id, v_admin_id, 'dismiss', 'Report dismissed by admin', p_admin_notes);
    END IF;

    -- Update report state
    UPDATE public.user_reports
    SET status = CASE WHEN p_action = 'dismissed' THEN 'dismissed' ELSE 'resolved' END,
        action_taken = p_action,
        admin_notes = p_admin_notes,
        resolved_by = v_admin_id,
        resolved_at = now()
    WHERE id = p_report_id;

    -- Log to admin audit trail
    INSERT INTO public.admin_audit_logs (
        admin_id, action, target_type, target_id, details
    ) VALUES (
        v_admin_id,
        'resolve_user_report',
        'user_reports',
        p_report_id::TEXT,
        jsonb_build_object(
            'target_user_id', v_target_user_id,
            'action_taken', p_action,
            'admin_notes', p_admin_notes
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'report_id', p_report_id,
        'action_taken', p_action,
        'status', CASE WHEN p_action = 'dismissed' THEN 'dismissed' ELSE 'resolved' END
    );
END;
$$;

-- Procedure: Block Peer User (Client Callable)
CREATE OR REPLACE FUNCTION public.block_peer_user(
    p_blocked_user_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to block user.';
    END IF;

    IF v_user_id = p_blocked_user_id THEN
        RAISE EXCEPTION 'Users cannot block themselves.';
    END IF;

    INSERT INTO public.blocked_users (user_id, blocked_user_id, reason)
    VALUES (v_user_id, p_blocked_user_id, p_reason)
    ON CONFLICT (user_id, blocked_user_id) DO NOTHING;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'blocked_user_id', p_blocked_user_id
    );
END;
$$;

-- ============================================================================
-- 8. Row Level Security Policies
-- ============================================================================

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moderation_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_fraud_tracking ENABLE ROW LEVEL SECURITY;

-- user_reports RLS
CREATE POLICY "Users can create reports"
ON public.user_reports FOR INSERT
WITH CHECK (auth.uid() = reporter_id OR reporter_id IS NULL);

CREATE POLICY "Users can view their submitted reports"
ON public.user_reports FOR SELECT
USING (auth.uid() = reporter_id);

CREATE POLICY "Admins have full access to user reports"
ON public.user_reports FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'super_admin')
    )
);

-- blocked_users RLS
CREATE POLICY "Users can manage their own blocked list"
ON public.blocked_users FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- moderation_actions RLS
CREATE POLICY "Admins have full access to moderation actions"
ON public.moderation_actions FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'super_admin')
    )
);

-- device_fraud_tracking RLS
CREATE POLICY "Admins can inspect fraud records"
ON public.device_fraud_tracking FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'super_admin')
    )
);

-- 9. Realtime publication
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_reports;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
