-- ==============================================================================
-- BAATKRY PLATFORM - CREATOR PAYOUT & WITHDRAWAL SYSTEM MIGRATION
-- Migration: 20261101020000_creator_payout_and_cancellation.sql
-- ==============================================================================

-- 1. Update payout_method check constraint to support modern digital methods (PayPal, Crypto, etc.)
DO $$
BEGIN
    ALTER TABLE public.payout_accounts 
    DROP CONSTRAINT IF EXISTS payout_accounts_payout_method_check;

    ALTER TABLE public.payout_accounts 
    ADD CONSTRAINT payout_accounts_payout_method_check 
    CHECK (payout_method IN (
        'paypal', 'bank_transfer', 'iban', 'jazzcash', 
        'easypaisa', 'wise', 'payoneer', 'crypto', 'usdt'
    ));
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- 2. Stored Procedure for Creators to Self-Cancel a Pending Payout Request
CREATE OR REPLACE FUNCTION public.cancel_creator_withdrawal(
    p_withdrawal_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_creator_id UUID;
    v_withdrawal RECORD;
    v_new_available NUMERIC(12, 4);
BEGIN
    v_creator_id := auth.uid();
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Lock withdrawal record FOR UPDATE
    SELECT * INTO v_withdrawal 
    FROM public.creator_withdrawals 
    WHERE id = p_withdrawal_id AND creator_id = v_creator_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Withdrawal request not found or not owned by creator';
    END IF;

    -- Only allow cancellation of requests that have not yet been approved/processed
    IF v_withdrawal.status NOT IN ('pending', 'under_review') THEN
        RAISE EXCEPTION 'Cannot cancel withdrawal in state: %', v_withdrawal.status;
    END IF;

    -- 1. Restore the reserved amount back to creator wallet
    UPDATE public.creator_wallets
    SET available_earnings_usd = available_earnings_usd + v_withdrawal.amount_usd,
        withdrawn_earnings_usd = GREATEST(0, withdrawn_earnings_usd - v_withdrawal.amount_usd),
        updated_at = NOW()
    WHERE creator_id = v_creator_id
    RETURNING available_earnings_usd INTO v_new_available;

    -- 2. Mark withdrawal record as cancelled
    UPDATE public.creator_withdrawals
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_withdrawal_id;

    -- 3. Insert audit log
    INSERT INTO public.admin_audit_logs (
        admin_id, action, target_type, target_id, details
    ) VALUES (
        v_creator_id, 'creator_cancel_withdrawal', 'creator_withdrawals', p_withdrawal_id::TEXT,
        jsonb_build_object(
            'amount_usd', v_withdrawal.amount_usd,
            'restored_balance_usd', v_new_available
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'withdrawal_id', p_withdrawal_id,
        'status', 'cancelled',
        'restored_amount_usd', v_withdrawal.amount_usd,
        'available_earnings_usd', v_new_available
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
