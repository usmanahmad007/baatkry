-- ==============================================================================
-- BAATKRY PLATFORM - CREATOR APPLICATION APPROVAL PROCEDURE MIGRATION
-- Migration: 20261101010000_creator_approval_procedure.sql
-- Compatible with Supabase PostgreSQL (Standard & Enterprise)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.admin_review_creator_application(
    p_application_id UUID,
    p_action TEXT, -- 'approve', 'reject'
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_admin_id UUID;
    v_app RECORD;
    v_new_status TEXT;
BEGIN
    v_admin_id := auth.uid();
    IF NOT public.is_admin(v_admin_id) THEN
        RAISE EXCEPTION 'Administrator privileges required';
    END IF;

    SELECT * INTO v_app FROM public.creator_applications WHERE id = p_application_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Creator application not found';
    END IF;

    IF v_app.status IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Application is already in terminal state (%)', v_app.status;
    END IF;

    IF p_action = 'approve' THEN
        v_new_status := 'approved';

        -- 1. Grant creator role
        INSERT INTO public.user_roles (user_id, role, granted_by)
        VALUES (v_app.user_id, 'creator', v_admin_id)
        ON CONFLICT (user_id, role) DO NOTHING;

        -- 2. Create or verify creator profile
        INSERT INTO public.creator_profiles (id, display_name, bio, is_verified)
        VALUES (v_app.user_id, v_app.full_name, v_app.bio, true)
        ON CONFLICT (id) DO UPDATE 
        SET display_name = EXCLUDED.display_name,
            bio = COALESCE(EXCLUDED.bio, creator_profiles.bio),
            is_verified = true,
            updated_at = NOW();

        -- 3. Ensure creator wallet exists for real-money earnings
        INSERT INTO public.creator_wallets (creator_id)
        VALUES (v_app.user_id)
        ON CONFLICT (creator_id) DO NOTHING;

        -- 4. Record formal verification entry
        INSERT INTO public.creator_verifications (creator_id, verification_level, verified_by, notes)
        VALUES (v_app.user_id, 'tier_1', v_admin_id, 'Approved via KYC application');

    ELSIF p_action = 'reject' THEN
        v_new_status := 'rejected';
    ELSE
        RAISE EXCEPTION 'Invalid review action: %', p_action;
    END IF;

    -- Update application status
    UPDATE public.creator_applications
    SET status = v_new_status,
        rejection_reason = CASE WHEN p_action = 'reject' THEN p_rejection_reason ELSE NULL END,
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_application_id;

    -- Admin audit log
    INSERT INTO public.admin_audit_logs (
        admin_id, action, target_type, target_id, details
    ) VALUES (
        v_admin_id, 'review_creator_' || p_action, 'creator_applications', p_application_id::TEXT,
        jsonb_build_object('user_id', v_app.user_id, 'status', v_new_status, 'reason', p_rejection_reason)
    );

    RETURN jsonb_build_object(
        'success', true,
        'application_id', p_application_id,
        'user_id', v_app.user_id,
        'status', v_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
