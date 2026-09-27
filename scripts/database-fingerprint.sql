-- Only counts and aggregate fingerprints leave the database, never row contents.
-- Suitable for this small course database; a large database needs chunked checks.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL timezone = 'UTC';
SELECT format(
    'SELECT %L, count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '''' ORDER BY md5(to_jsonb(t)::text)), '''')) FROM %I.%I AS t;',
    schemaname || '.' || tablename, schemaname, tablename
)
FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
\gexec
SELECT format('SELECT %L, last_value, is_called FROM %I.%I;',
    schemaname || '.' || sequencename, schemaname, sequencename)
FROM pg_sequences WHERE schemaname = 'public' ORDER BY sequencename
\gexec
COMMIT;
