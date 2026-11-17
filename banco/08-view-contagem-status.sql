CREATE MATERIALIZED VIEW mv_pedidos_por_status AS
SELECT status, count(*) AS total
  FROM pedidos
 GROUP BY status;

ANALYZE mv_pedidos_por_status;
