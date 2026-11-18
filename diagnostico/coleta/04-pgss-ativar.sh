# Ativa pg_stat_statements se faltar (reinicia banco e API). Depois, recrie com: docker compose down -v && docker compose up -d --build
source "$(dirname "$0")/lib.sh"
{
  pre=$(sql -At -c "SHOW shared_preload_libraries" | tr -d '[:space:]')
  case "$pre" in
    *pg_stat_statements*) echo "já carregado" ;;
    *) echo "ativando (reinicia banco e API)"
       sql -c "ALTER SYSTEM SET shared_preload_libraries='pg_stat_statements'"
       docker compose restart banco
       for _ in $(seq 30); do docker compose exec -T banco pg_isready -U loja -d loja >/dev/null 2>&1 && break; sleep 2; done
       docker compose restart api
       esperar_api || echo "API não voltou" ;;
  esac
  sql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
} 2>&1 | saida
