-- ============================================================================
-- Migration: Credit Receiver Coins on Gift Transmission & Live Balance Sync
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_virtual_gift(
    p_gift_id TEXT,
    p_receiver_id UUID,
    p_room_id TEXT DEFAULT NULL,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_sender_id UUID;
    v_gift RECORD;
    v_sender_wallet RECORD;
    v_receiver_wallet RECORD;
    v_commission RECORD;
    v_is_receiver_creator BOOLEAN := false;
    v_gross_usd NUMERIC(12, 4) := 0;
    v_platform_commission_usd NUMERIC(12, 4) := 0;
    v_creator_net_usd NUMERIC(12, 4) := 0;
    v_gift_tx_id UUID;
    v_sender_new_balance BIGINT;
    v_receiver_new_balance BIGINT;
    v_sender_nickname TEXT;
    v_effective_idempotency TEXT;
BEGIN
    -- 1. Identify Sender
    v_sender_id := auth.uid();
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to send gifts';
    END IF;

    -- 2. Validate Receiver
    IF p_receiver_id IS NULL OR v_sender_id = p_receiver_id THEN
        RAISE EXCEPTION 'Invalid gift recipient';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_receiver_id) THEN
        RAISE EXCEPTION 'Recipient user does not exist';
    END IF;

    SELECT COALESCE(nickname, 'Friend') INTO v_sender_nickname FROM public.profiles WHERE id = v_sender_id;

    -- 3. Check Idempotency Key
    v_effective_idempotency := COALESCE(p_idempotency_key, gen_random_uuid()::TEXT);
    SELECT id INTO v_gift_tx_id FROM public.gift_transactions WHERE idempotency_key = v_effective_idempotency;
    IF v_gift_tx_id IS NOT NULL THEN
        SELECT balance INTO v_sender_new_balance FROM public.wallets WHERE user_id = v_sender_id;
        RETURN jsonb_build_object(
            'success', true,
            'duplicate_prevented', true,
            'gift_transaction_id', v_gift_tx_id,
            'coins_balance', v_sender_new_balance
        );
    END IF;

    -- 4. Validate Gift
    SELECT * INTO v_gift FROM public.gifts WHERE id = p_gift_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gift not found or currently unavailable';
    END IF;

    -- 5. Lock Sender Wallet Row FOR UPDATE (Concurrency Protection)
    PERFORM public.ensure_user_wallet(v_sender_id);
    SELECT * INTO v_sender_wallet FROM public.wallets WHERE user_id = v_sender_id FOR UPDATE;

    -- 6. Check Balance
    IF v_sender_wallet.balance < v_gift.coin_price THEN
        RAISE EXCEPTION 'Insufficient coin balance (Required: %, Available: %)', v_gift.coin_price, v_sender_wallet.balance;
    END IF;

    -- 7. Deduct Coins from Sender (Gifter Account)
    v_sender_new_balance := v_sender_wallet.balance - v_gift.coin_price;
    UPDATE public.wallets
    SET balance = v_sender_new_balance,
        total_spent = total_spent + v_gift.coin_price,
        updated_at = NOW()
    WHERE id = v_sender_wallet.id;

    -- Update sender profiles.coins
    UPDATE public.profiles
    SET coins = v_sender_new_balance, updated_at = NOW()
    WHERE id = v_sender_id;

    -- 8. Record in Sender Wallet Ledger
    INSERT INTO public.wallet_ledger (
        wallet_id, user_id, type, amount, balance_after, reference_id, description, idempotency_key
    ) VALUES (
        v_sender_wallet.id,
        v_sender_id,
        'gift_sent',
        -v_gift.coin_price,
        v_sender_new_balance,
        p_gift_id,
        'Sent ' || v_gift.name || ' in call',
        'ledger_' || v_effective_idempotency
    );

    -- 9. Add Coins to Receiver Account
    PERFORM public.ensure_user_wallet(p_receiver_id);
    SELECT * INTO v_receiver_wallet FROM public.wallets WHERE user_id = p_receiver_id FOR UPDATE;

    v_receiver_new_balance := v_receiver_wallet.balance + v_gift.coin_price;
    UPDATE public.wallets
    SET balance = v_receiver_new_balance,
        total_purchased = total_purchased + v_gift.coin_price,
        updated_at = NOW()
    WHERE id = v_receiver_wallet.id;

    -- Update receiver profiles.coins
    UPDATE public.profiles
    SET coins = v_receiver_new_balance, updated_at = NOW()
    WHERE id = p_receiver_id;

    -- Record in Receiver Wallet Ledger
    INSERT INTO public.wallet_ledger (
        wallet_id, user_id, type, amount, balance_after, reference_id, description, idempotency_key
    ) VALUES (
        v_receiver_wallet.id,
        p_receiver_id,
        'gift_received',
        v_gift.coin_price,
        v_receiver_new_balance,
        p_gift_id,
        'Received ' || v_gift.name || ' in call from ' || v_sender_nickname,
        'ledger_recv_' || v_effective_idempotency
    );

    -- 10. Check if Receiver is an Approved Creator
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = p_receiver_id AND role = 'creator'
    ) INTO v_is_receiver_creator;

    -- 11. Fetch Active Commission Rules & Calculate Split (if creator)
    SELECT * INTO v_commission FROM public.commission_rules WHERE is_active = true ORDER BY created_at DESC LIMIT 1;
    IF v_commission IS NULL THEN
        v_gross_usd := v_gift.coin_price * 0.002000;
        v_platform_commission_usd := v_gross_usd * 0.3000;
        v_creator_net_usd := v_gross_usd * 0.7000;
    ELSE
        v_gross_usd := v_gift.coin_price * v_commission.coin_to_usd_rate;
        v_platform_commission_usd := v_gross_usd * v_commission.platform_percentage;
        v_creator_net_usd := v_gross_usd * v_commission.creator_percentage;
    END IF;

    -- 12. Record Gift Transaction Record
    INSERT INTO public.gift_transactions (
        gift_id, sender_id, receiver_id, room_id, coins_spent,
        creator_earnings_usd, platform_commission_usd,
        commission_rate, receiver_was_creator, idempotency_key
    ) VALUES (
        p_gift_id, v_sender_id, p_receiver_id, p_room_id, v_gift.coin_price,
        CASE WHEN v_is_receiver_creator THEN v_creator_net_usd ELSE 0 END,
        v_platform_commission_usd,
        COALESCE(v_commission.platform_percentage, 0.3000),
        v_is_receiver_creator,
        v_effective_idempotency
    ) RETURNING id INTO v_gift_tx_id;

    -- 13. If Receiver is Creator: Credit Creator Wallet & Ledger
    IF v_is_receiver_creator THEN
        INSERT INTO public.creator_wallets (creator_id, available_earnings_usd, lifetime_earnings_usd)
        VALUES (p_receiver_id, v_creator_net_usd, v_creator_net_usd)
        ON CONFLICT (creator_id) DO UPDATE SET
            available_earnings_usd = public.creator_wallets.available_earnings_usd + v_creator_net_usd,
            lifetime_earnings_usd = public.creator_wallets.lifetime_earnings_usd + v_creator_net_usd,
            updated_at = NOW();

        INSERT INTO public.creator_earnings (
            creator_id, gift_transaction_id, gross_amount_usd,
            platform_commission_usd, net_earning_usd, status
        ) VALUES (
            p_receiver_id, v_gift_tx_id, v_gross_usd,
            v_platform_commission_usd, v_creator_net_usd, 'available'
        );

        UPDATE public.creator_profiles
        SET total_gifts_received = total_gifts_received + 1,
            updated_at = NOW()
        WHERE id = p_receiver_id;
    END IF;

    -- 14. Record Platform Revenue Transaction
    INSERT INTO public.platform_transactions (
        type, gross_amount, fee_deducted, net_amount, reference_id
    ) VALUES (
        'gift_commission', v_gross_usd, 0, v_platform_commission_usd, v_gift_tx_id::TEXT
    );

    RETURN jsonb_build_object(
        'success', true,
        'gift_transaction_id', v_gift_tx_id,
        'gift_id', p_gift_id,
        'gift_name', v_gift.name,
        'coins_spent', v_gift.coin_price,
        'coins_balance', v_sender_new_balance,
        'receiver_coins_balance', v_receiver_new_balance,
        'icon_url', v_gift.icon_url,
        'animation_url', v_gift.animation_url,
        'receiver_earned_usd', CASE WHEN v_is_receiver_creator THEN v_creator_net_usd ELSE 0 END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
