-- =====================================================================
-- Migration: Add DOB (Date of Birth) & Age Verification to public.profiles
-- Ensures user DOB is permanently stored so users are never asked twice
-- =====================================================================

-- 1. Add columns to public.profiles if they do not exist
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS birth_date DATE,
ADD COLUMN IF NOT EXISTS date_of_birth DATE,
ADD COLUMN IF NOT EXISTS age INTEGER,
ADD COLUMN IF NOT EXISTS is_age_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'Global (Worldwide)',
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'ALL';

-- 2. Trigger function to synchronize birth_date, date_of_birth, age, and is_age_verified
CREATE OR REPLACE FUNCTION public.sync_profile_dob()
RETURNS TRIGGER AS $$
BEGIN
    -- Synchronize birth_date and date_of_birth if one is provided
    IF NEW.birth_date IS NOT NULL AND NEW.date_of_birth IS NULL THEN
        NEW.date_of_birth := NEW.birth_date;
    ELSIF NEW.date_of_birth IS NOT NULL AND NEW.birth_date IS NULL THEN
        NEW.birth_date := NEW.date_of_birth;
    END IF;

    -- Calculate age from birth_date if age is not explicitly set or is <= 0
    IF NEW.birth_date IS NOT NULL AND (NEW.age IS NULL OR NEW.age <= 0) THEN
        NEW.age := DATE_PART('year', AGE(NEW.birth_date))::INTEGER;
    END IF;

    -- If age is 18 or above, mark as verified adult
    IF NEW.age IS NOT NULL AND NEW.age >= 18 THEN
        NEW.is_age_verified := true;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_profile_dob ON public.profiles;
CREATE TRIGGER trg_sync_profile_dob
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_profile_dob();

-- 3. Create index for fast age verification lookup
CREATE INDEX IF NOT EXISTS idx_profiles_age_verified ON public.profiles (id, is_age_verified);
