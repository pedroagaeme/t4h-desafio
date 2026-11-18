source "$(dirname "$0")/lib.sh"
E="EXPLAIN (ANALYZE, BUFFERS, SETTINGS)"
{
  echo "=== extensões e collation"
  sql -c "SELECT name, default_version FROM pg_available_extensions WHERE name IN ('pg_trgm','pg_stat_statements')" \
      -c "SELECT datname, datcollate, datctype FROM pg_database WHERE datname='loja'"
  echo "=== JIT nas consultas medidas"
  sql -c "SELECT calls, jit_functions, round(jit_generation_time::numeric) gen_ms, round(jit_inlining_time::numeric) inl_ms, round(jit_optimization_time::numeric) opt_ms, round(jit_emission_time::numeric) emi_ms, left(regexp_replace(query,'\s+',' ','g'),70) consulta FROM pg_stat_statements WHERE jit_functions>0 ORDER BY jit_generation_time DESC LIMIT 10"
  for p in 1 500 3000 6000 15000; do
    echo "=== listagem status=pago pagina $p"
    sql -c "$E SELECT * FROM pedidos WHERE status='pago' ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET $(( (p-1)*20 ))"
  done
  echo "=== busca"
  sql -c "$E SELECT * FROM produtos WHERE nome ILIKE '%cadeira%' ORDER BY nome, id LIMIT 20"
  echo "=== vendas-por-dia (7 dias)"
  sql -c "$E SELECT p.id AS pedido_id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos FROM pedidos p JOIN itens_pedido i ON i.pedido_id = p.id WHERE p.criado_em >= '2024-01-01'::date AND p.criado_em < '2024-01-07'::date + 1 AND p.status <> 'cancelado'"
  echo "=== parâmetros da carga"
  ls carga; grep -rn -i "pagina\|inicio\|fim\|random\|status\|q=" carga | head -60
} 2>&1 | saida
