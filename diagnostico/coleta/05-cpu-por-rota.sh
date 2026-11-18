source "$(dirname "$0")/lib.sh"
{
  A0=$(cpu api); B0=$(cpu banco); sleep 10; A1=$(cpu api); B1=$(cpu banco)
  IA=$(( (A1-A0)/10 )); IB=$(( (B1-B0)/10 )); echo "ocioso us/s: api=$IA banco=$IB"
  echo "n | rota | ms/req | cpu_api_ms/req | cpu_banco_ms/req | bytes"
  for item in \
   "100|/clientes/500" "100|/clientes?email=cliente3%40exemplo.com" "100|/clientes/42/pedidos" \
   "60|/pedidos?status=pago&pagina=1" "60|/pedidos?status=pago&pagina=500" "30|/pedidos?status=pago&pagina=15000" \
   "60|/pedidos?status=entregue&pagina=3" "60|/pedidos?status=cancelado&pagina=250" \
   "60|/produtos/busca?q=cadeira" "60|/produtos/busca?q=ERGO" "60|/produtos/busca?q=sem%20fio" \
   "30|/relatorios/vendas-por-dia?inicio=2024-01-01&fim=2024-01-07" \
   "10|/relatorios/vendas-por-dia?inicio=2024-01-01&fim=2024-03-01" "100|/relatorios/top-produtos"; do
    n=${item%%|*}; u=${item#*|}
    for _ in 1 2 3; do curl -s -o /dev/null "$BASE$u"; done
    a0=$(cpu api); b0=$(cpu banco); t0=$(date +%s%N)
    for _ in $(seq "$n"); do curl -s -o /dev/null "$BASE$u"; done
    t1=$(date +%s%N); a1=$(cpu api); b1=$(cpu banco)
    by=$(curl -s -o /dev/null -w '%{size_download}' "$BASE$u")
    awk -v n="$n" -v u="$u" -v dt=$(( (t1-t0)/1000000 )) -v a0="$a0" -v a1="$a1" -v b0="$b0" -v b1="$b1" -v ia="$IA" -v ib="$IB" -v by="$by" \
      'BEGIN{s=dt/1000; printf "%d | %s | %.1f | %.2f | %.2f | %d\n", n,u,dt/n,((a1-a0)-ia*s)/n/1000,((b1-b0)-ib*s)/n/1000,by}'
  done
} 2>&1 | saida
