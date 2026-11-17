CREATE INDEX idx_clientes_lower_email ON clientes (lower(email));
ANALYZE clientes;
