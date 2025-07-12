CREATE OR REPLACE FUNCTION ledgerr_api.create_partner(
    p_partner_name VARCHAR(100),
    p_partner_type VARCHAR(20),
    p_external_partner_id VARCHAR(50) DEFAULT NULL, 
    p_partner_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_partner_id UUID;
BEGIN
    -- Use provided UUID or generate new one
    v_partner_id := COALESCE(p_partner_id, gen_random_uuid());

    -- Validate partner type
    IF p_partner_type NOT IN ('INDIVIDUAL', 'BUSINESS', 'FINTECH', 'BANK') THEN
        RAISE EXCEPTION 'Invalid partner type: %. Must be one of: INDIVIDUAL, BUSINESS, FINTECH, BANK', p_partner_type;
    END IF;
    
    -- Validate partner name
    IF p_partner_name IS NULL OR trim(p_partner_name) = '' THEN
        RAISE EXCEPTION 'Partner name cannot be empty';
    END IF;
    
    -- Check for duplicate external partner ID if provided
    IF p_external_partner_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM ledgerr.partners WHERE external_partner_id = p_external_partner_id) THEN
            RAISE EXCEPTION 'External partner ID already exists: %', p_external_partner_id;
        END IF;
    END IF;
    
    -- Insert the partner
    INSERT INTO ledgerr.partners (
        partner_id,
        partner_name,
        partner_type,
        external_partner_id,
        is_active
    ) VALUES (
        v_partner_id,
        p_partner_name,
        p_partner_type,
        p_external_partner_id,
        TRUE
    );
    
    RETURN v_partner_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;