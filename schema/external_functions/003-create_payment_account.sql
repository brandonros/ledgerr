CREATE OR REPLACE FUNCTION ledgerr_api.create_payment_account(
    p_external_account_id VARCHAR(50),
    p_partner_id UUID,
    p_account_holder_name VARCHAR(100),
    p_account_type VARCHAR(20),
    p_gl_account_id UUID,
    p_daily_limit DECIMAL(15,2) DEFAULT 5000.00,
    p_monthly_limit DECIMAL(15,2) DEFAULT 50000.00,
    p_risk_level VARCHAR(10) DEFAULT 'LOW',
    p_payment_account_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_payment_account_id UUID;
BEGIN
    -- Use provided UUID or generate new one
    v_payment_account_id := COALESCE(p_payment_account_id, gen_random_uuid());

    -- Validate account type
    IF p_account_type NOT IN ('CHECKING', 'SAVINGS', 'PREPAID', 'MERCHANT', 'CAPITAL') THEN
        RAISE EXCEPTION 'Invalid account type: %. Must be one of: CHECKING, SAVINGS, PREPAID, MERCHANT, CAPITAL', p_account_type;
    END IF;
    
    -- Validate risk level
    IF p_risk_level NOT IN ('LOW', 'MEDIUM', 'HIGH') THEN
        RAISE EXCEPTION 'Invalid risk level: %. Must be one of: LOW, MEDIUM, HIGH', p_risk_level;
    END IF;
    
    -- Validate required fields
    IF p_external_account_id IS NULL OR trim(p_external_account_id) = '' THEN
        RAISE EXCEPTION 'External account ID cannot be empty';
    END IF;
    
    IF p_account_holder_name IS NULL OR trim(p_account_holder_name) = '' THEN
        RAISE EXCEPTION 'Account holder name cannot be empty';
    END IF;
    
    -- Validate partner exists and is active
    IF NOT EXISTS (SELECT 1 FROM ledgerr.partners WHERE partner_id = p_partner_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Partner not found or inactive: %', p_partner_id;
    END IF;
    
    -- Validate GL account exists and is active
    IF NOT EXISTS (SELECT 1 FROM ledgerr.gl_accounts WHERE gl_account_id = p_gl_account_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'GL account not found or inactive: %', p_gl_account_id;
    END IF;
    
    -- Check for duplicate external account ID within the same partner
    IF EXISTS (
        SELECT 1 FROM ledgerr.payment_accounts 
        WHERE partner_id = p_partner_id 
          AND external_account_id = p_external_account_id
    ) THEN
        RAISE EXCEPTION 'External account ID already exists for this partner: %', p_external_account_id;
    END IF;
    
    -- Validate limits
    IF p_daily_limit <= 0 OR p_monthly_limit <= 0 THEN
        RAISE EXCEPTION 'Daily and monthly limits must be positive values';
    END IF;
    
    IF p_daily_limit > p_monthly_limit THEN
        RAISE EXCEPTION 'Daily limit cannot exceed monthly limit';
    END IF;
    
    -- Insert the payment account
    INSERT INTO ledgerr.payment_accounts (
        payment_account_id,
        external_account_id,
        partner_id,
        account_holder_name,
        account_type,
        gl_account_id,
        current_balance,
        available_balance,
        pending_debits,
        pending_credits,
        daily_limit,
        monthly_limit,
        daily_debit_total,
        daily_credit_total,
        last_daily_reset,
        is_active,
        risk_level,
        balance_version
    ) VALUES (
        v_payment_account_id,
        p_external_account_id,
        p_partner_id,
        p_account_holder_name,
        p_account_type,
        p_gl_account_id,
        0.00,
        0.00,
        0.00,
        0.00,
        p_daily_limit,
        p_monthly_limit,
        0.00,
        0.00,
        CURRENT_DATE,
        TRUE,
        p_risk_level,
        1
    );
    
    RETURN v_payment_account_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;