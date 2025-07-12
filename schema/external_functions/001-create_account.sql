CREATE OR REPLACE FUNCTION ledgerr_api.create_account(
    p_account_code VARCHAR(64),
    p_account_name VARCHAR(100),
    p_account_type VARCHAR(64),
    p_parent_account_id UUID DEFAULT NULL,
    p_account_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_account_id UUID;
BEGIN
    -- Use provided UUID or generate new one
    v_account_id := COALESCE(p_account_id, gen_random_uuid());

    -- Validate account type
    IF p_account_type NOT IN ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE') THEN
        RAISE EXCEPTION 'Invalid account type: %. Must be one of: ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE', p_account_type;
    END IF;
    
    -- Validate account code format (you can customize this)
    IF p_account_code IS NULL OR trim(p_account_code) = '' THEN
        RAISE EXCEPTION 'Account code cannot be empty';
    END IF;
    
    -- Validate account name
    IF p_account_name IS NULL OR trim(p_account_name) = '' THEN
        RAISE EXCEPTION 'Account name cannot be empty';
    END IF;
    
    -- Validate parent account exists if provided
    IF p_parent_account_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM ledgerr.accounts WHERE account_id = p_parent_account_id AND is_active = TRUE) THEN
            RAISE EXCEPTION 'Parent account not found or inactive: %', p_parent_account_id;
        END IF;
    END IF;
    
    -- Check for duplicate account code
    IF EXISTS (SELECT 1 FROM ledgerr.accounts WHERE account_code = p_account_code) THEN
        RAISE EXCEPTION 'Account code already exists: %', p_account_code;
    END IF;
    
    -- Insert the GL account
    INSERT INTO ledgerr.accounts (
        account_id,
        account_code,
        account_name,
        account_type,
        parent_account_id,
        is_active
    ) VALUES (
        v_account_id,
        p_account_code,
        p_account_name,
        p_account_type,
        p_parent_account_id,
        TRUE
    );
    
    RETURN v_account_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;