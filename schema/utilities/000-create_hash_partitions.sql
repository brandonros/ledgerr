CREATE OR REPLACE FUNCTION create_hash_partitions(full_table_name TEXT, num_partitions INTEGER DEFAULT 16)
RETURNS void AS $$
DECLARE
    i INTEGER;
    schema_name TEXT;
    table_name TEXT;
    partition_name TEXT;
BEGIN
    -- Extract schema and table name
    schema_name := split_part(full_table_name, '.', 1);
    table_name := split_part(full_table_name, '.', 2);

    -- Loop over the number of partitions
    FOR i IN 0..(num_partitions - 1) LOOP
        partition_name := format('%s_p%s', table_name, i);
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES WITH (MODULUS %s, REMAINDER %s);',
            schema_name, partition_name, schema_name, table_name, num_partitions, i
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;