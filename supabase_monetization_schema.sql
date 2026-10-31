-- ==============================================================================
-- BAATKRY PLATFORM - COMPLETE MONETIZATION & CREATOR EARNING SYSTEM MIGRATION
-- Migration: 20261101000000_monetization_system.sql
-- Compatible with Supabase PostgreSQL (Standard & Enterprise)
-- ==============================================================================

-- 0. Ensure Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- MODULE 1: USER & CREATOR ROLE MANAGEMENT
-- ==============================================================================

-- 1.1 User Roles Table
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'creator', 'admin', 'moderator')),
    granted_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles(role);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Helper security functions for RLS checks
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = p_user_id AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_creator(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = p_user_id AND role = 'creator'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RLS for user_roles
CREATE POLICY "Users can view their own roles"
    ON public.user_roles FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

CREATE POLICY "Only admins can manage roles"
    ON public.user_roles FOR ALL
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 1.2 Creator Public Profiles Table
CREATE TABLE IF NOT EXISTS public.creator_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    banner_url TEXT,
    category TEXT DEFAULT 'General',
    is_verified BOOLEAN NOT NULL DEFAULT false,
    total_gifts_received BIGINT NOT NULL DEFAULT 0,
    total_call_minutes BIGINT NOT NULL DEFAULT 0,
    follower_count BIGINT NOT NULL DEFAULT 0,
    social_links JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.creator_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can view verified or active creator profiles"
    ON public.creator_profiles FOR SELECT
    USING (true);

CREATE POLICY "Creators can update their own profile bio and links"
    ON public.creator_profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- 1.3 Creator KYC Applications Table
CREATE TABLE IF NOT EXISTS public.creator_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    date_of_birth DATE NOT NULL,
    country TEXT NOT NULL,
    id_document_type TEXT NOT NULL CHECK (id_document_type IN ('passport', 'national_id', 'driving_license')),
    id_document_front_url TEXT NOT NULL,
    id_document_back_url TEXT,
    selfie_url TEXT NOT NULL,
    social_media_links JSONB DEFAULT '{}'::jsonb,
    bio TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected')),
    rejection_reason TEXT,
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_applications_user ON public.creator_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_creator_applications_status ON public.creator_applications(status);

ALTER TABLE public.creator_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own creator applications"
    ON public.creator_applications FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

CREATE POLICY "Users can submit creator applications"
    ON public.creator_applications FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can update creator applications"
    ON public.creator_applications FOR UPDATE
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 1.4 Creator Verifications Table
CREATE TABLE IF NOT EXISTS public.creator_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    verification_level TEXT NOT NULL DEFAULT 'tier_1' CHECK (verification_level IN ('tier_1', 'tier_2', 'tier_3')),
    verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.creator_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators and admins can view verifications"
    ON public.creator_verifications FOR SELECT
    USING (auth.uid() = creator_id OR public.is_admin(auth.uid()));

-- ==============================================================================
-- MODULE 2: COIN WALLET & VIRTUAL GOODS MANAGEMENT
-- ==============================================================================

-- 2.1 User Coin Wallets Table (Strict Double-Entry Balance)
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    balance BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0),
    locked_balance BIGINT NOT NULL DEFAULT 0 CHECK (locked_balance >= 0),
    total_purchased BIGINT NOT NULL DEFAULT 0 CHECK (total_purchased >= 0),
    total_spent BIGINT NOT NULL DEFAULT 0 CHECK (total_spent >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own wallet"
    ON public.wallets FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- Direct INSERT/UPDATE/DELETE on wallets disallowed by clients: strictly executed via stored functions

-- 2.2 Dynamic Coin Packages Table
CREATE TABLE IF NOT EXISTS public.coin_packages (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    coins BIGINT NOT NULL CHECK (coins > 0),
    price_usd NUMERIC(10, 2) NOT NULL CHECK (price_usd > 0),
    price_rs NUMERIC(10, 2) NOT NULL DEFAULT 0,
    badge TEXT,
    is_popular BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.coin_packages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active coin packages"
    ON public.coin_packages FOR SELECT
    USING (is_active = true OR public.is_admin(auth.uid()));

CREATE POLICY "Only admins can manage coin packages"
    ON public.coin_packages FOR ALL
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 2.3 Verified Coin Purchases Table
CREATE TABLE IF NOT EXISTS public.coin_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    package_id TEXT NOT NULL REFERENCES public.coin_packages(id),
    coins_credited BIGINT NOT NULL CHECK (coins_credited > 0),
    amount_paid NUMERIC(10, 2) NOT NULL CHECK (amount_paid >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    gateway TEXT NOT NULL CHECK (gateway IN ('stripe', 'google_play', 'apple_iap', 'safepay', 'jazzcash', 'easypaisa', 'manual_admin')),
    gateway_order_id TEXT,
    gateway_payment_id TEXT,
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'refunded', 'charged_back')),
    idempotency_key TEXT UNIQUE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coin_purchases_user ON public.coin_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_coin_purchases_idempotency ON public.coin_purchases(idempotency_key);

ALTER TABLE public.coin_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own purchases"
    ON public.coin_purchases FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- 2.4 Immutable Coin Transaction Ledger
-- Extends the existing coin_transactions concept with explicit financial accounting
CREATE TABLE IF NOT EXISTS public.wallet_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'gift_sent', 'feature_unlock', 'bonus', 'refund_deduct', 'admin_adjustment')),
    amount BIGINT NOT NULL, -- positive for credits, negative for debits
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    reference_id TEXT,
    description TEXT,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user ON public.wallet_ledger(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_wallet ON public.wallet_ledger(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_idempotency ON public.wallet_ledger(idempotency_key);

ALTER TABLE public.wallet_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own wallet ledger"
    ON public.wallet_ledger FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- 2.5 Virtual Gifts Catalogue Table
CREATE TABLE IF NOT EXISTS public.gifts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    coin_price BIGINT NOT NULL CHECK (coin_price > 0),
    icon_url TEXT NOT NULL,
    animation_url TEXT,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.gifts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active gifts"
    ON public.gifts FOR SELECT
    USING (is_active = true OR public.is_admin(auth.uid()));

CREATE POLICY "Only admins can manage gifts"
    ON public.gifts FOR ALL
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 2.6 Atomic Gift Transactions Table
CREATE TABLE IF NOT EXISTS public.gift_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gift_id TEXT NOT NULL REFERENCES public.gifts(id),
    sender_id UUID NOT NULL REFERENCES auth.users(id),
    receiver_id UUID NOT NULL REFERENCES auth.users(id),
    room_id TEXT,
    coins_spent BIGINT NOT NULL CHECK (coins_spent > 0),
    creator_earnings_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (creator_earnings_usd >= 0),
    platform_commission_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (platform_commission_usd >= 0),
    commission_rate NUMERIC(5, 4) NOT NULL DEFAULT 0.3000,
    receiver_was_creator BOOLEAN NOT NULL DEFAULT false,
    idempotency_key TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gift_transactions_sender ON public.gift_transactions(sender_id);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_receiver ON public.gift_transactions(receiver_id);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_room ON public.gift_transactions(room_id);
CREATE INDEX IF NOT EXISTS idx_gift_transactions_idempotency ON public.gift_transactions(idempotency_key);

ALTER TABLE public.gift_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can view their sent and received gifts"
    ON public.gift_transactions FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR public.is_admin(auth.uid()));

-- ==============================================================================
-- MODULE 3: CREATOR FINANCIAL & WITHDRAWAL MANAGEMENT
-- ==============================================================================

-- 3.1 Dynamic Commission Rules Table
CREATE TABLE IF NOT EXISTS public.commission_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT 'Standard Commission Tier',
    creator_percentage NUMERIC(5, 4) NOT NULL DEFAULT 0.7000 CHECK (creator_percentage >= 0 AND creator_percentage <= 1),
    platform_percentage NUMERIC(5, 4) NOT NULL DEFAULT 0.3000 CHECK (platform_percentage >= 0 AND platform_percentage <= 1),
    coin_to_usd_rate NUMERIC(10, 6) NOT NULL DEFAULT 0.002000, -- e.g. 500 coins = $1.00 => $0.002/coin
    min_withdrawal_usd NUMERIC(10, 2) NOT NULL DEFAULT 20.00 CHECK (min_withdrawal_usd > 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_commission_sum CHECK (creator_percentage + platform_percentage = 1.0000)
);

ALTER TABLE public.commission_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active commission rules"
    ON public.commission_rules FOR SELECT
    USING (is_active = true OR public.is_admin(auth.uid()));

CREATE POLICY "Only admins can edit commission rules"
    ON public.commission_rules FOR ALL
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 3.2 Creator Real-Money Earnings Wallets Table
CREATE TABLE IF NOT EXISTS public.creator_wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    available_earnings_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (available_earnings_usd >= 0),
    pending_earnings_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (pending_earnings_usd >= 0),
    lifetime_earnings_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (lifetime_earnings_usd >= 0),
    withdrawn_earnings_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (withdrawn_earnings_usd >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_wallets_creator ON public.creator_wallets(creator_id);

ALTER TABLE public.creator_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can view their own financial earnings wallet"
    ON public.creator_wallets FOR SELECT
    USING (auth.uid() = creator_id OR public.is_admin(auth.uid()));

-- 3.3 Creator Itemized Earnings Ledger Table
CREATE TABLE IF NOT EXISTS public.creator_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    gift_transaction_id UUID NOT NULL REFERENCES public.gift_transactions(id),
    gross_amount_usd NUMERIC(12, 4) NOT NULL CHECK (gross_amount_usd > 0),
    platform_commission_usd NUMERIC(12, 4) NOT NULL CHECK (platform_commission_usd >= 0),
    net_earning_usd NUMERIC(12, 4) NOT NULL CHECK (net_earning_usd >= 0),
    status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('pending', 'available', 'withdrawn', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_earnings_creator ON public.creator_earnings(creator_id);
CREATE INDEX IF NOT EXISTS idx_creator_earnings_gift_tx ON public.creator_earnings(gift_transaction_id);

ALTER TABLE public.creator_earnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can view their earnings records"
    ON public.creator_earnings FOR SELECT
    USING (auth.uid() = creator_id OR public.is_admin(auth.uid()));

-- 3.4 Creator Payout Beneficiary Accounts Table
CREATE TABLE IF NOT EXISTS public.payout_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    payout_method TEXT NOT NULL CHECK (payout_method IN ('bank_transfer', 'iban', 'jazzcash', 'easypaisa', 'wise', 'payoneer')),
    account_title TEXT NOT NULL,
    account_number TEXT NOT NULL,
    bank_name TEXT,
    routing_code TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    is_primary BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_accounts_creator ON public.payout_accounts(creator_id);

ALTER TABLE public.payout_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can manage their own payout accounts"
    ON public.payout_accounts FOR ALL
    USING (auth.uid() = creator_id OR public.is_admin(auth.uid()))
    WITH CHECK (auth.uid() = creator_id OR public.is_admin(auth.uid()));

-- 3.5 Creator Withdrawals Lifecycle Table
CREATE TABLE IF NOT EXISTS public.creator_withdrawals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    payout_account_id UUID NOT NULL REFERENCES public.payout_accounts(id),
    amount_usd NUMERIC(12, 4) NOT NULL CHECK (amount_usd > 0),
    fee_usd NUMERIC(12, 4) NOT NULL DEFAULT 0 CHECK (fee_usd >= 0),
    net_payout_amount NUMERIC(12, 4) NOT NULL CHECK (net_payout_amount > 0),
    payout_currency TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'processing', 'completed', 'rejected', 'failed', 'cancelled')),
    admin_notes TEXT,
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    payout_transaction_reference TEXT,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_withdrawals_creator ON public.creator_withdrawals(creator_id);
CREATE INDEX IF NOT EXISTS idx_creator_withdrawals_status ON public.creator_withdrawals(status);

ALTER TABLE public.creator_withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Creators can view their withdrawal history"
    ON public.creator_withdrawals FOR SELECT
    USING (auth.uid() = creator_id OR public.is_admin(auth.uid()));

CREATE POLICY "Only admins can update withdrawal status"
    ON public.creator_withdrawals FOR UPDATE
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- ==============================================================================
-- MODULE 4: PAYMENT MANAGEMENT & AUDIT
-- ==============================================================================

-- 4.1 Payment Transactions Ledger Table
CREATE TABLE IF NOT EXISTS public.payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('stripe', 'google_play', 'apple_iap', 'safepay', 'jazzcash', 'easypaisa', 'manual_admin')),
    provider_tx_id TEXT NOT NULL UNIQUE,
    amount NUMERIC(12, 4) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL CHECK (status IN ('initiated', 'success', 'failed', 'refunded', 'disputed')),
    raw_payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON public.payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_provider_tx ON public.payment_transactions(provider_tx_id);

ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own payment transactions"
    ON public.payment_transactions FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- 4.2 Webhook Idempotency & Log Table
CREATE TABLE IF NOT EXISTS public.payment_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_id TEXT UNIQUE NOT NULL,
    payload JSONB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT false,
    processed_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.payment_webhooks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view webhooks"
    ON public.payment_webhooks FOR SELECT
    USING (public.is_admin(auth.uid()));

-- 4.3 Refunds & Chargebacks Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID REFERENCES public.coin_purchases(id),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    amount NUMERIC(12, 4) NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    coins_deducted BIGINT NOT NULL DEFAULT 0,
    reason TEXT NOT NULL,
    processed_by UUID REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users and admins can view refunds"
    ON public.refunds FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- ==============================================================================
-- MODULE 5: PLATFORM ADMINISTRATION & GOVERNANCE
-- ==============================================================================

-- 5.1 Admin Audit Logs Table
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id TEXT NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_action ON public.admin_audit_logs(action);

ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view audit logs"
    ON public.admin_audit_logs FOR SELECT
    USING (public.is_admin(auth.uid()));

-- 5.2 Dynamic Platform Settings Table
CREATE TABLE IF NOT EXISTS public.app_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES auth.users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view app settings"
    ON public.app_settings FOR SELECT
    USING (true);

CREATE POLICY "Only admins can modify app settings"
    ON public.app_settings FOR ALL
    USING (public.is_admin(auth.uid()))
    WITH CHECK (public.is_admin(auth.uid()));

-- 5.3 Platform Financial Ledger Table (Revenue & Commission Tracking)
CREATE TABLE IF NOT EXISTS public.platform_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL CHECK (type IN ('gift_commission', 'withdrawal_fee', 'iap_fee', 'gateway_fee', 'refund_loss')),
    gross_amount NUMERIC(12, 4) NOT NULL,
    fee_deducted NUMERIC(12, 4) NOT NULL DEFAULT 0,
    net_amount NUMERIC(12, 4) NOT NULL,
    reference_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.platform_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only admins can view platform transactions"
    ON public.platform_transactions FOR SELECT
    USING (public.is_admin(auth.uid()));

-- 5.4 Support & Appeal Tickets Table
CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('payment', 'withdrawal', 'gift', 'account', 'moderation', 'other')),
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    assigned_to UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view and create their own tickets"
    ON public.support_tickets FOR ALL
    USING (auth.uid() = user_id OR public.is_admin(auth.uid()))
    WITH CHECK (auth.uid() = user_id OR public.is_admin(auth.uid()));

-- ==============================================================================
-- MODULE 6: ATOMIC FINANCIAL STORED PROCEDURES (ACID GUARANTEE)
-- ==============================================================================

-- 6.1 Helper to ensure a wallet exists and sync with profiles
CREATE OR REPLACE FUNCTION public.ensure_user_wallet(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    v_wallet_id UUID;
    v_existing_coins INT := 0;
BEGIN
    SELECT id INTO v_wallet_id FROM public.wallets WHERE user_id = p_user_id;
    
    IF v_wallet_id IS NULL THEN
        -- Check coins from profiles if existing
        SELECT COALESCE(coins, 0) INTO v_existing_coins FROM public.profiles WHERE id = p_user_id;
        
        INSERT INTO public.wallets (user_id, balance, total_purchased)
        VALUES (p_user_id, v_existing_coins, v_existing_coins)
        ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
        RETURNING id INTO v_wallet_id;
    END IF;
    
    RETURN v_wallet_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.2 Atomic Gift Sending Procedure
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
    v_commission RECORD;
    v_is_receiver_creator BOOLEAN := false;
    v_gross_usd NUMERIC(12, 4) := 0;
    v_platform_commission_usd NUMERIC(12, 4) := 0;
    v_creator_net_usd NUMERIC(12, 4) := 0;
    v_gift_tx_id UUID;
    v_new_balance BIGINT;
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

    -- 3. Check Idempotency Key
    v_effective_idempotency := COALESCE(p_idempotency_key, gen_random_uuid()::TEXT);
    SELECT id INTO v_gift_tx_id FROM public.gift_transactions WHERE idempotency_key = v_effective_idempotency;
    IF v_gift_tx_id IS NOT NULL THEN
        SELECT balance INTO v_new_balance FROM public.wallets WHERE user_id = v_sender_id;
        RETURN jsonb_build_object(
            'success', true,
            'duplicate_prevented', true,
            'gift_transaction_id', v_gift_tx_id,
            'coins_balance', v_new_balance
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

    -- 7. Deduct Coins from Sender
    v_new_balance := v_sender_wallet.balance - v_gift.coin_price;
    UPDATE public.wallets
    SET balance = v_new_balance,
        total_spent = total_spent + v_gift.coin_price,
        updated_at = NOW()
    WHERE id = v_sender_wallet.id;

    -- Backward compatibility: update profiles.coins
    UPDATE public.profiles
    SET coins = v_new_balance, updated_at = NOW()
    WHERE id = v_sender_id;

    -- 8. Record in Wallet Ledger
    INSERT INTO public.wallet_ledger (
        wallet_id, user_id, type, amount, balance_after, reference_id, description, idempotency_key
    ) VALUES (
        v_sender_wallet.id,
        v_sender_id,
        'gift_sent',
        -v_gift.coin_price,
        v_new_balance,
        p_gift_id,
        'Sent ' || v_gift.name || ' in call',
        'ledger_' || v_effective_idempotency
    );

    -- 9. Check if Receiver is an Approved Creator
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = p_receiver_id AND role = 'creator'
    ) INTO v_is_receiver_creator;

    -- 10. Fetch Active Commission Rules & Calculate Split
    SELECT * INTO v_commission FROM public.commission_rules WHERE is_active = true ORDER BY created_at DESC LIMIT 1;
    IF v_commission IS NULL THEN
        -- Default Fallback: 70% Creator / 30% Platform, $0.002 per coin
        v_gross_usd := v_gift.coin_price * 0.002000;
        v_platform_commission_usd := v_gross_usd * 0.3000;
        v_creator_net_usd := v_gross_usd * 0.7000;
    ELSE
        v_gross_usd := v_gift.coin_price * v_commission.coin_to_usd_rate;
        v_platform_commission_usd := v_gross_usd * v_commission.platform_percentage;
        v_creator_net_usd := v_gross_usd * v_commission.creator_percentage;
    END IF;

    -- 11. Record Gift Transaction Record
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

    -- 12. If Receiver is Creator: Credit Creator Wallet & Ledger
    IF v_is_receiver_creator THEN
        -- Ensure creator wallet exists
        INSERT INTO public.creator_wallets (creator_id, available_earnings_usd, lifetime_earnings_usd)
        VALUES (p_receiver_id, v_creator_net_usd, v_creator_net_usd)
        ON CONFLICT (creator_id) DO UPDATE SET
            available_earnings_usd = public.creator_wallets.available_earnings_usd + v_creator_net_usd,
            lifetime_earnings_usd = public.creator_wallets.lifetime_earnings_usd + v_creator_net_usd,
            updated_at = NOW();

        -- Insert Creator Itemized Earning
        INSERT INTO public.creator_earnings (
            creator_id, gift_transaction_id, gross_amount_usd,
            platform_commission_usd, net_earning_usd, status
        ) VALUES (
            p_receiver_id, v_gift_tx_id, v_gross_usd,
            v_platform_commission_usd, v_creator_net_usd, 'available'
        );

        -- Update Creator Profile Stats
        UPDATE public.creator_profiles
        SET total_gifts_received = total_gifts_received + 1,
            updated_at = NOW()
        WHERE id = p_receiver_id;
    END IF;

    -- 13. Record Platform Revenue Transaction
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
        'coins_balance', v_new_balance,
        'icon_url', v_gift.icon_url,
        'animation_url', v_gift.animation_url,
        'receiver_earned_usd', CASE WHEN v_is_receiver_creator THEN v_creator_net_usd ELSE 0 END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.3 Atomic Coin Purchase Fulfillment Procedure (Called by Verified Webhook / IAP)
CREATE OR REPLACE FUNCTION public.process_verified_coin_purchase(
    p_user_id UUID,
    p_package_id TEXT,
    p_gateway TEXT,
    p_gateway_order_id TEXT,
    p_gateway_payment_id TEXT,
    p_amount_paid NUMERIC(10, 2),
    p_currency TEXT DEFAULT 'USD',
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_package RECORD;
    v_wallet RECORD;
    v_effective_idempotency TEXT;
    v_purchase_id UUID;
    v_new_balance BIGINT;
BEGIN
    -- Validate user
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'Target user not found';
    END IF;

    -- Validate package
    SELECT * INTO v_package FROM public.coin_packages WHERE id = p_package_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Coin package not found';
    END IF;

    v_effective_idempotency := COALESCE(p_idempotency_key, p_gateway_payment_id, gen_random_uuid()::TEXT);

    -- Check Idempotency
    SELECT id INTO v_purchase_id FROM public.coin_purchases WHERE idempotency_key = v_effective_idempotency;
    IF v_purchase_id IS NOT NULL THEN
        SELECT balance INTO v_new_balance FROM public.wallets WHERE user_id = p_user_id;
        RETURN jsonb_build_object(
            'success', true,
            'duplicate_prevented', true,
            'purchase_id', v_purchase_id,
            'coins_balance', v_new_balance
        );
    END IF;

    -- Lock Wallet FOR UPDATE
    PERFORM public.ensure_user_wallet(p_user_id);
    SELECT * INTO v_wallet FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;

    v_new_balance := v_wallet.balance + v_package.coins;

    -- Credit Coins
    UPDATE public.wallets
    SET balance = v_new_balance,
        total_purchased = total_purchased + v_package.coins,
        updated_at = NOW()
    WHERE id = v_wallet.id;

    -- Backward compatibility: update profiles.coins and is_vip if package qualifies
    UPDATE public.profiles
    SET coins = v_new_balance,
        is_vip = CASE WHEN p_package_id LIKE '%vip%' OR p_package_id LIKE '%2500%' OR p_package_id LIKE '%5000%' THEN true ELSE is_vip END,
        updated_at = NOW()
    WHERE id = p_user_id;

    -- Record Purchase
    INSERT INTO public.coin_purchases (
        user_id, package_id, coins_credited, amount_paid, currency,
        gateway, gateway_order_id, gateway_payment_id, status, idempotency_key
    ) VALUES (
        p_user_id, p_package_id, v_package.coins, p_amount_paid, p_currency,
        p_gateway, p_gateway_order_id, p_gateway_payment_id, 'completed', v_effective_idempotency
    ) RETURNING id INTO v_purchase_id;

    -- Record in Wallet Ledger
    INSERT INTO public.wallet_ledger (
        wallet_id, user_id, type, amount, balance_after, reference_id, description, idempotency_key
    ) VALUES (
        v_wallet.id, p_user_id, 'purchase', v_package.coins, v_new_balance,
        v_purchase_id::TEXT, 'Purchased ' || v_package.name, 'ledger_' || v_effective_idempotency
    );

    RETURN jsonb_build_object(
        'success', true,
        'purchase_id', v_purchase_id,
        'coins_credited', v_package.coins,
        'coins_balance', v_new_balance
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.4 Atomic Creator Withdrawal Request Procedure
CREATE OR REPLACE FUNCTION public.request_creator_withdrawal(
    p_payout_account_id UUID,
    p_amount_usd NUMERIC(12, 4),
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_creator_id UUID;
    v_wallet RECORD;
    v_commission RECORD;
    v_min_withdrawal NUMERIC(10, 2);
    v_withdrawal_id UUID;
    v_effective_idempotency TEXT;
BEGIN
    v_creator_id := auth.uid();
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Check if approved creator
    IF NOT public.is_creator(v_creator_id) THEN
        RAISE EXCEPTION 'Only approved creators can request withdrawals';
    END IF;

    -- Validate Payout Account
    IF NOT EXISTS (
        SELECT 1 FROM public.payout_accounts 
        WHERE id = p_payout_account_id AND creator_id = v_creator_id
    ) THEN
        RAISE EXCEPTION 'Payout account not found or does not belong to creator';
    END IF;

    -- Minimum Withdrawal Check
    SELECT min_withdrawal_usd INTO v_min_withdrawal FROM public.commission_rules WHERE is_active = true ORDER BY created_at DESC LIMIT 1;
    v_min_withdrawal := COALESCE(v_min_withdrawal, 20.00);

    IF p_amount_usd < v_min_withdrawal THEN
        RAISE EXCEPTION 'Withdrawal amount must be at least $% USD', v_min_withdrawal;
    END IF;

    v_effective_idempotency := COALESCE(p_idempotency_key, gen_random_uuid()::TEXT);

    -- Check Idempotency
    SELECT id INTO v_withdrawal_id FROM public.creator_withdrawals WHERE idempotency_key = v_effective_idempotency;
    IF v_withdrawal_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true,
            'duplicate_prevented', true,
            'withdrawal_id', v_withdrawal_id
        );
    END IF;

    -- Lock Creator Wallet FOR UPDATE
    SELECT * INTO v_wallet FROM public.creator_wallets WHERE creator_id = v_creator_id FOR UPDATE;
    IF NOT FOUND OR v_wallet.available_earnings_usd < p_amount_usd THEN
        RAISE EXCEPTION 'Insufficient available earnings (Required: $%, Available: $%)', p_amount_usd, COALESCE(v_wallet.available_earnings_usd, 0);
    END IF;

    -- Deduct from Available Earnings, add to Withdrawn
    UPDATE public.creator_wallets
    SET available_earnings_usd = available_earnings_usd - p_amount_usd,
        withdrawn_earnings_usd = withdrawn_earnings_usd + p_amount_usd,
        updated_at = NOW()
    WHERE id = v_wallet.id;

    -- Insert Withdrawal Request
    INSERT INTO public.creator_withdrawals (
        creator_id, payout_account_id, amount_usd, fee_usd, net_payout_amount,
        status, idempotency_key
    ) VALUES (
        v_creator_id, p_payout_account_id, p_amount_usd, 0.00, p_amount_usd,
        'pending', v_effective_idempotency
    ) RETURNING id INTO v_withdrawal_id;

    RETURN jsonb_build_object(
        'success', true,
        'withdrawal_id', v_withdrawal_id,
        'amount_usd', p_amount_usd,
        'status', 'pending',
        'remaining_available_usd', v_wallet.available_earnings_usd - p_amount_usd
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.5 Admin Review Withdrawal Procedure (Approve / Reject with Rollback)
CREATE OR REPLACE FUNCTION public.admin_review_withdrawal(
    p_withdrawal_id UUID,
    p_action TEXT, -- 'approve', 'complete', 'reject', 'fail'
    p_admin_notes TEXT DEFAULT NULL,
    p_tx_ref TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_admin_id UUID;
    v_withdrawal RECORD;
    v_new_status TEXT;
BEGIN
    v_admin_id := auth.uid();
    IF NOT public.is_admin(v_admin_id) THEN
        RAISE EXCEPTION 'Administrator privileges required';
    END IF;

    SELECT * INTO v_withdrawal FROM public.creator_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Withdrawal request not found';
    END IF;

    IF v_withdrawal.status IN ('completed', 'rejected', 'cancelled') THEN
        RAISE EXCEPTION 'Withdrawal is already in terminal state (%)', v_withdrawal.status;
    END IF;

    IF p_action = 'approve' THEN
        v_new_status := 'approved';
    ELSIF p_action = 'complete' THEN
        v_new_status := 'completed';
    ELSIF p_action IN ('reject', 'fail') THEN
        v_new_status := CASE WHEN p_action = 'reject' THEN 'rejected' ELSE 'failed' END;
        
        -- Automatic Financial Rollback: restore funds to creator's available earnings
        UPDATE public.creator_wallets
        SET available_earnings_usd = available_earnings_usd + v_withdrawal.amount_usd,
            withdrawn_earnings_usd = withdrawn_earnings_usd - v_withdrawal.amount_usd,
            updated_at = NOW()
        WHERE creator_id = v_withdrawal.creator_id;
    ELSE
        RAISE EXCEPTION 'Invalid review action: %', p_action;
    END IF;

    UPDATE public.creator_withdrawals
    SET status = v_new_status,
        admin_notes = COALESCE(p_admin_notes, admin_notes),
        reviewed_by = v_admin_id,
        reviewed_at = NOW(),
        payout_transaction_reference = COALESCE(p_tx_ref, payout_transaction_reference),
        updated_at = NOW()
    WHERE id = p_withdrawal_id;

    -- Audit log
    INSERT INTO public.admin_audit_logs (
        admin_id, action, target_type, target_id, details
    ) VALUES (
        v_admin_id, 'review_withdrawal_' || p_action, 'creator_withdrawals', p_withdrawal_id::TEXT,
        jsonb_build_object('status', v_new_status, 'notes', p_admin_notes, 'tx_ref', p_tx_ref)
    );

    RETURN jsonb_build_object(
        'success', true,
        'withdrawal_id', p_withdrawal_id,
        'status', v_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- MODULE 7: SEED DATA & MIGRATION BACKFILL
-- ==============================================================================

-- 7.1 Seed Standard Coin Packages
INSERT INTO public.coin_packages (id, name, description, coins, price_usd, price_rs, badge, is_popular, sort_order)
VALUES
    ('pack_starter_500', 'Starter Pack', '500 Virtual Coins for video chats & gifts', 500, 0.99, 280, NULL, false, 1),
    ('pack_basic_1200', 'Basic Pack', '1,200 Virtual Coins + Bonus', 1200, 1.99, 560, NULL, false, 2),
    ('pack_popular_3500', 'Popular Pack', '3,500 Virtual Coins (Most Selected)', 3500, 4.99, 1400, 'POPULAR', true, 3),
    ('pack_premium_8000', 'Premium VIP', '8,000 Coins + Gold VIP status badge', 8000, 9.99, 2800, 'VIP DEAL', false, 4),
    ('pack_ultimate_18000', 'Ultimate King', '18,000 Coins + Crown badge & priority match', 18000, 19.99, 5600, 'BEST VALUE', false, 5)
ON CONFLICT (id) DO UPDATE SET
    coins = EXCLUDED.coins,
    price_usd = EXCLUDED.price_usd,
    price_rs = EXCLUDED.price_rs,
    updated_at = NOW();

-- Also keep backward compatibility for existing Pakistani Rupee packages
INSERT INTO public.coin_packages (id, name, description, coins, price_usd, price_rs, badge, is_popular, sort_order)
VALUES
    ('pack_500_rs', 'Starter Pack (PKR)', '60 Mins Gender-Filtered Video Chat (1 coin/sec)', 3600, 1.79, 500, 'MIN DEPOSIT', false, 6),
    ('pack_1000_rs', 'Popular VIP (PKR)', '130 Mins Gender-Filtered Video Chat', 7800, 3.57, 1000, 'POPULAR', false, 7),
    ('pack_2500_rs', 'Pro VIP Pass (PKR)', '350 Mins + Gold VIP Badge', 21000, 8.92, 2500, 'VIP DEAL', false, 8),
    ('pack_5000_rs', 'King VIP Access (PKR)', '800 Mins + Crown Badge', 48000, 17.85, 5000, 'BEST VALUE', false, 9)
ON CONFLICT (id) DO NOTHING;

-- 7.2 Seed Virtual Gifts Catalogue
INSERT INTO public.gifts (id, name, coin_price, icon_url, animation_url, description, sort_order)
VALUES
    ('gift_heart', 'Heart', 10, 'assets/gifts/heart.png', 'assets/animations/heart.json', 'Send a sweet loving heart', 1),
    ('gift_rose', 'Rose', 25, 'assets/gifts/rose.png', 'assets/animations/rose.json', 'A fresh blooming red rose', 2),
    ('gift_coffee', 'Coffee', 50, 'assets/gifts/coffee.png', 'assets/animations/coffee.json', 'Treat someone to warm coffee', 3),
    ('gift_star', 'Star', 100, 'assets/gifts/star.png', 'assets/animations/star.json', 'Make them shine like a star', 4),
    ('gift_diamond', 'Diamond', 500, 'assets/gifts/diamond.png', 'assets/animations/diamond.json', 'Sparkling luxury diamond', 5),
    ('gift_crown', 'Crown', 1000, 'assets/gifts/crown.png', 'assets/animations/crown.json', 'Crown them king or queen', 6),
    ('gift_super', 'Super Gift', 5000, 'assets/gifts/super_gift.png', 'assets/animations/super_gift.json', 'Ultimate fireworks explosion', 7)
ON CONFLICT (id) DO UPDATE SET
    coin_price = EXCLUDED.coin_price,
    updated_at = NOW();

-- 7.3 Seed Default Commission Rule (70% Creator / 30% Platform, Min $20.00 withdrawal)
INSERT INTO public.commission_rules (id, name, creator_percentage, platform_percentage, coin_to_usd_rate, min_withdrawal_usd, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Global Default 70/30 Tier',
    0.7000,
    0.3000,
    0.002000, -- 500 coins = $1.00 USD
    20.00,
    true
)
ON CONFLICT (id) DO NOTHING;

-- 7.4 Seed Global Platform App Settings
INSERT INTO public.app_settings (key, value, description)
VALUES
    ('monetization_enabled', 'true'::jsonb, 'Master toggle for virtual gifts and coin store'),
    ('creator_applications_enabled', 'true'::jsonb, 'Whether users can submit creator KYC applications'),
    ('min_creator_age', '18'::jsonb, 'Minimum verified age required to apply as creator'),
    ('default_currency', '"USD"'::jsonb, 'Default financial reporting currency'),
    ('allowed_withdrawal_methods', '["bank_transfer", "iban", "jazzcash", "easypaisa", "wise", "payoneer"]'::jsonb, 'Supported payout gateways')
ON CONFLICT (key) DO NOTHING;

-- 7.5 Backfill Migration: Create wallets for all existing profiles
INSERT INTO public.wallets (user_id, balance, total_purchased)
SELECT 
    p.id, 
    COALESCE(p.coins, 0),
    COALESCE(p.coins, 0)
FROM public.profiles p
LEFT JOIN public.wallets w ON w.user_id = p.id
WHERE w.id IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- 7.6 Realtime Publication: Add gifts, wallets, and creator earnings to Supabase Realtime
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'wallets'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'gift_transactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_transactions;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'creator_wallets'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.creator_wallets;
    END IF;
END $$;
