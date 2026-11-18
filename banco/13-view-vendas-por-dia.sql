CREATE MATERIALIZED VIEW mv_vendas_por_dia AS
SELECT t.dia,
       COUNT(*)         AS pedidos,
       SUM(t.itens)     AS itens,
       SUM(t.receita)   AS receita_centavos
  FROM (SELECT p.criado_em::date AS dia,
               SUM(i.quantidade) AS itens,
               SUM(i.quantidade::bigint * i.preco_unitario_centavos) AS receita
          FROM pedidos p
          JOIN itens_pedido i ON i.pedido_id = p.id
         WHERE p.status <> 'cancelado'
         GROUP BY p.id) t
 GROUP BY t.dia;

CREATE UNIQUE INDEX idx_mv_vendas_por_dia_dia ON mv_vendas_por_dia (dia);
ANALYZE mv_vendas_por_dia;
