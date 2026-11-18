CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_produtos_nome_trgm ON produtos USING gin (nome gin_trgm_ops);
ANALYZE produtos;
