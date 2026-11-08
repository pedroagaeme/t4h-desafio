#!/usr/bin/env bash
# Preenche a matriz USE (CPU, memória, E/S) de cada container lendo o cgroup v2,
# sob a MESMA carga do scripts/medir.sh, sem chamar o medir.sh e sem criar nada em resultados/.
#
#   diagnostico/scripts/use-sob-carga.sh <rotulo>
#   VUS=20 DURACAO=60s diagnostico/scripts/use-sob-carga.sh use-baseline
#   SAMPLE_INTERVAL=2 diagnostico/scripts/use-sob-carga.sh use-baseline
#
# Mesma carga: mesmo serviço "carga" do docker-compose.yml, mesmo carga/teste-carga.js,
# mesmos padrões do medir.sh (VUS=20, DURACAO=60s, AQUECIMENTO=15s, SEMENTE=42) e mesmo aquecimento
# antes (VUS=5, SEMENTE+1, fora da leitura). Se a linha de base usou outros valores, passe os mesmos aqui.
#
# Matriz (arquivo do cgroup v2 que alimenta cada célula):
#   CPU      utilização  cpu.stat usage_usec (delta / janela / limite)
#            saturação   cpu.stat nr_throttled, throttled_usec; cpu.pressure (PSI)
#   Memória  utilização  memory.current vs memory.max
#            saturação   memory.events high e max; memory.pressure (PSI)
#   Erros    memory.events oom e oom_kill
#   E/S      utilização  io.stat (bytes e operações; sem teto conhecido, só volume)
#            saturação   io.pressure (PSI)
# Arquivo ausente (ex.: sem PSI no kernel) aparece como "n/d": registre isso como lacuna, não como zero.
#
# Não escreve em resultados/ (a carga roda sem SAIDA). O que sai daqui é diagnóstico:
# nunca use como antes/depois de uma mudança.
#
# Saída: diagnostico/saidas/<data>-<rotulo>/
#   matriz-use.txt  a matriz preenchida por container
#   k6-resumo.txt   resumo impresso pelo k6 (diagnóstico, não é resultado oficial)
#   contexto.txt    parâmetros, commit, limites e PSI disponível
#   antes/ depois/  arquivos brutos lidos dos containers
#   amostras.csv    leituras a cada SAMPLE_INTERVAL s (padrão 5; 0 desliga)
#
# Atenção: o contexto.txt do medir.sh conta arquivos novos fora de resultados/ como "alterados sem commit".
# Commite (ou apague) diagnostico/saidas/ antes de rodar o medir.sh de verdade.

set -euo pipefail
cd "$(dirname "$0")/../.."

ROTULO="${1:-}"
if [[ -z "$ROTULO" || ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/use-sob-carga.sh <rotulo>   (letras, números, ponto, hífen ou sublinhado)" >&2
  exit 2
fi

VUS="${VUS:-20}"
DURACAO="${DURACAO:-60s}"
AQUECIMENTO="${AQUECIMENTO:-15s}"
SEMENTE="${SEMENTE:-42}"
PORTA_API="${PORTA_API:-3000}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-5}"
USUARIO="$(id -u):$(id -g)"
CG=/sys/fs/cgroup

for v in SEMENTE SAMPLE_INTERVAL; do
  if [[ ! "${!v}" =~ ^[0-9]+$ ]]; then
    echo "$v precisa ser um número inteiro." >&2
    exit 2
  fi
done

if ! curl -fsS "http://127.0.0.1:${PORTA_API}/saude" >/dev/null 2>&1; then
  echo "A API não respondeu em http://127.0.0.1:${PORTA_API}/saude. Suba tudo com: docker compose up -d --build" >&2
  exit 1
fi

# Mesma lista de serviços do medir.sh (as ferramentas ficam de fora, pelo perfil "ferramentas").
SERVICOS="$(docker compose config --services | tr '\n' ' ')"

for s in $SERVICOS; do
  if ! docker compose exec -T "$s" test -f "$CG/cpu.stat" 2>/dev/null; then
    echo "Não consegui ler $CG/cpu.stat em '$s'. O container não está rodando ou o cgroup é v1 (veja: docker compose exec $s ls /sys/fs/cgroup)." >&2
    exit 1
  fi
done

agora_ns() {
  local t
  t="$(date +%s%N)"
  if [[ "$t" == *N* ]]; then t="$(( $(date +%s) * 1000000000 ))"; fi
  echo "$t"
}

ARQUIVOS="cpu.stat cpu.max cpu.pressure memory.current memory.max memory.peak memory.events memory.pressure io.stat io.pressure"

# Lê cada arquivo; se o arquivo não existir, não cria o arquivo local (assim "n/d" fica distinguível de zero).
snapshot() {
  local destino="$1" s arquivo tmp
  mkdir -p "$destino"
  for s in $SERVICOS; do
    for arquivo in $ARQUIVOS; do
      tmp="$destino/$s.$arquivo"
      if docker compose exec -T "$s" cat "$CG/$arquivo" > "$tmp" 2>/dev/null; then :; else rm -f "$tmp"; fi
    done
  done
}

# valor <arquivo> <chave>: número da chave em arquivo "chave valor"; "nd" se o arquivo não existe
valor() {
  [[ -f "$1" ]] || { echo nd; return; }
  awk -v k="$2" '$1 == k { print $2; found = 1 } END { if (!found) print 0 }' "$1"
}

# psi_total <arquivo> <some|full>: total= em µs; "nd" se o arquivo não existe
psi_total() {
  [[ -f "$1" ]] || { echo nd; return; }
  awk -v l="$2" '$1 == l { for (i = 2; i <= NF; i++) if ($i ~ /^total=/) { sub("total=", "", $i); print $i; f = 1 } } END { if (!f) print 0 }' "$1"
}

# io_soma <arquivo> <campo>: soma do campo (rbytes, wbytes, rios, wios) em todos os dispositivos; "nd" se não existe
io_soma() {
  [[ -f "$1" ]] || { echo nd; return; }
  awk -v c="$2" '{ for (i = 2; i <= NF; i++) if ($i ~ "^" c "=") { split($i, p, "="); t += p[2] } } END { print t + 0 }' "$1"
}

# delta <depois> <antes>: diferença inteira, ou "nd" se qualquer lado for nd
delta() {
  if [[ "$1" == nd || "$2" == nd ]]; then echo nd; else echo $(( $1 - $2 )); fi
}

limite_cpu() {
  [[ -f "$1" ]] || { echo "?"; return; }
  awk '{ if ($1 == "max") print "sem-limite"; else printf "%.2f", $1 / $2 }' "$1"
}

# 1) Aquecimento: igual ao do medir.sh, fora da leitura.
echo "Aquecendo por ${AQUECIMENTO} (não entra na leitura)..."
docker compose run --rm --user "$USUARIO" -e VUS=5 -e DURACAO="$AQUECIMENTO" -e SEMENTE="$((SEMENTE + 1))" \
  carga run --quiet --no-summary /carga/teste-carga.js >/dev/null

# Opcional (usado por pgss-sob-carga.sh): com PGSS_RESET=1, zera os contadores do pg_stat_statements
# depois do aquecimento e antes da leitura, para que só a carga medida entre no ranking.
# Comando fixo, sem executar texto vindo do ambiente. Desligado por padrão.
if [[ "${PGSS_RESET:-0}" == "1" ]]; then
  docker compose exec -T banco psql -U loja -d loja -X -q -At -c 'SELECT pg_stat_statements_reset();' >/dev/null
fi

SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-${ROTULO}"
mkdir -p "$SAIDA"

snapshot "$SAIDA/antes"

{
  echo "rotulo: ${ROTULO}"
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "vus: ${VUS}"
  echo "duracao: ${DURACAO}"
  echo "aquecimento: ${AQUECIMENTO}"
  echo "semente: ${SEMENTE}"
  echo "intervalo de amostras: ${SAMPLE_INTERVAL} s (0 = sem amostras)"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo sem-commit)"
    echo "arquivos alterados sem commit: $(git status --porcelain -- . ':(exclude)resultados' ':(exclude)diagnostico/saidas' | wc -l | tr -d ' ')"
  fi
  echo
  echo "limites dos containers:"
  for s in $SERVICOS; do
    id="$(docker compose ps -q "$s")"
    [[ -z "$id" ]] && { echo "  ${s}: não está rodando"; continue; }
    docker inspect --format "  ${s}: cpus={{.HostConfig.NanoCpus}} (1e9 = 1 CPU, 0 = sem limite) memoria={{.HostConfig.Memory}} bytes (0 = sem limite)" "$id"
  done
  echo
  echo "arquivos do cgroup disponíveis (ok/ausente):"
  for s in $SERVICOS; do
    linha="  ${s}:"
    for arquivo in $ARQUIVOS; do
      if [[ -f "$SAIDA/antes/$s.$arquivo" ]]; then linha+=" $arquivo=ok"; else linha+=" $arquivo=ausente"; fi
    done
    echo "$linha"
  done
} > "$SAIDA/contexto.txt"

# 2) Leitura: só a carga medida.
SAMPLER=""
limpar() { [[ -n "$SAMPLER" ]] && kill "$SAMPLER" 2>/dev/null || true; }
trap limpar EXIT

amostrar() {
  echo "momento_ns,servico,usage_usec,nr_periods,nr_throttled,throttled_usec,memoria_bytes,cpu_psi_some_us,mem_psi_some_us,io_psi_some_us" > "$SAIDA/amostras.csv"
  while true; do
    local ns s
    ns="$(agora_ns)"
    for s in $SERVICOS; do
      docker compose exec -T "$s" sh -c "
        cat $CG/cpu.stat
        echo memory_current \$(cat $CG/memory.current)
        for f in cpu memory io; do
          t=\$(awk '\$1==\"some\" { for (i=2;i<=NF;i++) if (\$i ~ /^total=/) { sub(\"total=\",\"\",\$i); print \$i } }' $CG/\$f.pressure 2>/dev/null)
          echo psi_\$f \${t:-nd}
        done" 2>/dev/null \
        | awk -v t="$ns" -v s="$s" '
            { v[$1] = $2 }
            END { printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", t, s, v["usage_usec"], v["nr_periods"], v["nr_throttled"], v["throttled_usec"], v["memory_current"], v["psi_cpu"], v["psi_memory"], v["psi_io"] }' \
        >> "$SAIDA/amostras.csv" || true
    done
    sleep "$SAMPLE_INTERVAL"
  done
}

T0="$(agora_ns)"
if [[ "$SAMPLE_INTERVAL" -gt 0 ]]; then amostrar & SAMPLER=$!; fi

echo "Medindo recursos: ${VUS} usuários virtuais por ${DURACAO}..."
STATUS=0
# Sem SAIDA: o k6 imprime o resumo e não grava nada em resultados/.
docker compose run --rm --user "$USUARIO" -e VUS="$VUS" -e DURACAO="$DURACAO" -e SEMENTE="$SEMENTE" -e ROTULO="$ROTULO" \
  carga run --quiet /carga/teste-carga.js | tee "$SAIDA/k6-resumo.txt" || STATUS=$?

T1="$(agora_ns)"
if [[ -n "$SAMPLER" ]]; then kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true; SAMPLER=""; fi
snapshot "$SAIDA/depois"
JANELA_NS=$((T1 - T0))

# 3) Matriz USE
{
  echo "matriz USE: ${ROTULO}"
  awk -v ns="$JANELA_NS" 'BEGIN { printf "janela lida: %.1f s (do início ao fim do container do k6: a carga e ~1-2 s de partida)\n", ns / 1e9 }'
  echo "valores são deltas na janela, exceto onde indicado. nd = arquivo ausente (lacuna, não zero)."

  for s in $SERVICOS; do
    A="$SAIDA/antes"; D="$SAIDA/depois"
    lim="$(limite_cpu "$D/$s.cpu.max")"
    uso="$(delta "$(valor "$D/$s.cpu.stat" usage_usec)" "$(valor "$A/$s.cpu.stat" usage_usec)")"
    per="$(delta "$(valor "$D/$s.cpu.stat" nr_periods)" "$(valor "$A/$s.cpu.stat" nr_periods)")"
    thr="$(delta "$(valor "$D/$s.cpu.stat" nr_throttled)" "$(valor "$A/$s.cpu.stat" nr_throttled)")"
    thu="$(delta "$(valor "$D/$s.cpu.stat" throttled_usec)" "$(valor "$A/$s.cpu.stat" throttled_usec)")"
    psic="$(delta "$(psi_total "$D/$s.cpu.pressure" some)" "$(psi_total "$A/$s.cpu.pressure" some)")"
    mhigh="$(delta "$(valor "$D/$s.memory.events" high)" "$(valor "$A/$s.memory.events" high)")"
    mmax="$(delta "$(valor "$D/$s.memory.events" max)" "$(valor "$A/$s.memory.events" max)")"
    moom="$(delta "$(valor "$D/$s.memory.events" oom)" "$(valor "$A/$s.memory.events" oom)")"
    mkill="$(delta "$(valor "$D/$s.memory.events" oom_kill)" "$(valor "$A/$s.memory.events" oom_kill)")"
    psim="$(delta "$(psi_total "$D/$s.memory.pressure" some)" "$(psi_total "$A/$s.memory.pressure" some)")"
    psimf="$(delta "$(psi_total "$D/$s.memory.pressure" full)" "$(psi_total "$A/$s.memory.pressure" full)")"
    rb="$(delta "$(io_soma "$D/$s.io.stat" rbytes)" "$(io_soma "$A/$s.io.stat" rbytes)")"
    wb="$(delta "$(io_soma "$D/$s.io.stat" wbytes)" "$(io_soma "$A/$s.io.stat" wbytes)")"
    ri="$(delta "$(io_soma "$D/$s.io.stat" rios)" "$(io_soma "$A/$s.io.stat" rios)")"
    wi="$(delta "$(io_soma "$D/$s.io.stat" wios)" "$(io_soma "$A/$s.io.stat" wios)")"
    psii="$(delta "$(psi_total "$D/$s.io.pressure" some)" "$(psi_total "$A/$s.io.pressure" some)")"
    psiif="$(delta "$(psi_total "$D/$s.io.pressure" full)" "$(psi_total "$A/$s.io.pressure" full)")"
    memfim="$(tr -d '\n' < "$D/$s.memory.current" 2>/dev/null || echo nd)"
    memlim="$(tr -d '\n' < "$D/$s.memory.max" 2>/dev/null || echo nd)"
    mempeak="$(tr -d '\n' < "$D/$s.memory.peak" 2>/dev/null || echo nd)"

    echo
    echo "== ${s} =="
    awk -v lim="$lim" -v uso="$uso" -v ns="$JANELA_NS" -v per="$per" -v thr="$thr" -v thu="$thu" -v psic="$psic" \
        -v memfim="$memfim" -v memlim="$memlim" -v mempeak="$mempeak" -v mhigh="$mhigh" -v mmax="$mmax" \
        -v psim="$psim" -v psimf="$psimf" -v moom="$moom" -v mkill="$mkill" \
        -v rb="$rb" -v wb="$wb" -v ri="$ri" -v wi="$wi" -v psii="$psii" -v psiif="$psiif" '
      function pct_janela(us) { return (us == "nd" || ns <= 0) ? "nd" : sprintf("%.1f%% da janela", 100 * us / (ns / 1000)) }
      function mib(b) { return (b == "nd" || b == "max") ? b : sprintf("%.1f MiB", b / 1048576) }
      BEGIN {
        cpu = (uso == "nd" || ns <= 0) ? "nd" : sprintf("%.2f CPUs", uso / (ns / 1000))
        pt  = (per == "nd" || per <= 0) ? "nd" : sprintf("%.1f%% dos períodos", 100 * thr / per)
        printf "CPU      utilização  %s (limite %s)\n", cpu, lim
        printf "CPU      saturação   throttled %s (%s), throttled_usec %s s; PSI cpu some %s\n", thr, pt, (thu == "nd" ? "nd" : sprintf("%.2f", thu / 1e6)), pct_janela(psic)
        printf "Memória  utilização  fim %s de limite %s; pico desde o início do container %s\n", mib(memfim), mib(memlim), mib(mempeak)
        printf "Memória  saturação   events high=%s max=%s; PSI memory some %s, full %s\n", mhigh, mmax, pct_janela(psim), pct_janela(psimf)
        printf "Erros                oom=%s oom_kill=%s\n", moom, mkill
        printf "E/S      utilização  leitura %s (%s ops), escrita %s (%s ops)\n", (rb == "nd" ? "nd" : mib(rb)), ri, (wb == "nd" ? "nd" : mib(wb)), wi
        printf "E/S      saturação   PSI io some %s, full %s\n", pct_janela(psii), pct_janela(psiif)
      }'
  done

  if [[ -f "$SAIDA/amostras.csv" ]]; then
    echo
    echo "picos por amostra (de amostras.csv; cpu_pico = maior uso médio entre duas amostras seguidas; pode ser artefato de tempo, prefira os valores acima):"
    awk -F, '
      NR > 1 && $3 != "" {
        s = $2
        if (s in pn) {
          dt = ($1 - pn[s]) / 1e9
          if (dt > 0) { c = ($3 - pu[s]) / (dt * 1e6); if (c > cmax[s]) cmax[s] = c }
        }
        pn[s] = $1; pu[s] = $3
        m = $7 / 1048576; if (m > mmax[s]) mmax[s] = m
        n[s]++
      }
      END { for (s in n) printf "  %-8s amostras=%d cpu_pico=%.2f mem_pico=%.1f MiB\n", s, n[s], cmax[s], mmax[s] }
    ' "$SAIDA/amostras.csv"
  fi
} | tee "$SAIDA/matriz-use.txt"

echo
echo "Saída salva em $SAIDA/ (nada foi criado em resultados/)"
exit "$STATUS"