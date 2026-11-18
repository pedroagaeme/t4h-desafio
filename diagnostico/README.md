# diagnostico/

Saídas de diagnóstico (não são medições). Antes e depois de cada mudança vêm só de `medir.sh`, em `resultados/`.
Os valores de k6 destas pastas usam duração curta e **não são baseline**.

## Rodada 1

### Saídas

**`saidas/20261108-095016-use-baseline`**
- *Por que rodei:* a baseline (`recursos.txt`) já mostrava a utilização: banco em ~100% da CPU e API em ~7%. Faltava saber se há saturação (trabalho esperando por recurso) e erros, que o `recursos.txt` não mede.
- *O que descobri:*
  - Saturação: a CPU do banco está saturada. O sistema o segurou por causa do limite em 96,3% dos períodos de controle, e em 86,9% do tempo havia alguma tarefa esperando CPU. A memória do banco também encostou no limite de 512 MiB (atingiu o limite 2414 vezes, com pressão de memória em 5,9% do tempo), bem menos que a CPU. A API quase não tem saturação (0,7% dos períodos). Disco sem saturação relevante (0,6% do tempo).
  - Erros: nenhum, no banco nem na API (`oom=0`, `oom_kill=0`).

**`saidas/20261108-160654-pgss-baseline`**
- *Por que rodei:* como o banco é o gargalo, para saber quais consultas SQL gastam mais tempo nele.
- *O que descobri:* da soma do tempo gasto em consultas durante o teste, 44,0% foi na consulta que busca os itens de um pedido (`itens_pedido` por `pedido_id`) e 12,8% na que lista os pedidos de um cliente (`pedidos` por `cliente_id`). Em seguida vêm a listagem de pedidos por `status` (11,5%), `vendas-por-dia` (10,4%) e `top-produtos` (9,3%).

**`saidas/20261108-101356-rotas-isoladas`**
- *Por que rodei:* para ver o que cada rota faz no banco quando está sozinha, sem outras requisições competindo, e ler o plano de execução de cada consulta (o roteiro que o PostgreSQL escolhe para buscar os dados).
- *O que descobri:* uma única requisição a `pedidos-do-cliente` dispara 17 consultas: 1 de cliente, 1 da lista de pedidos, 5 de itens e 10 de produtos. As 6 consultas de pedidos e itens fazem varredura sequencial: leem a tabela inteira, linha por linha, para devolver de 2 a 5 linhas. Cada uma leva de 70 a 92 ms, e juntas são ~99,9% do tempo que a rota gasta no banco (~470 ms). As outras 11 buscam pela chave primária, que já tem índice, e levam 0,2 ms ou menos. O plano é o mesmo na chamada 1 (cache frio) e na 2 (cache quente).

**`saidas/indices-antes.txt`**
- *Por que rodei:* para conferir se `pedidos` e `itens_pedido` têm índice nas colunas que as consultas usam para filtrar.
- *O que descobri:* só existem as chaves primárias. Não há índice em `pedidos.cliente_id` nem em `itens_pedido.pedido_id`, o que é coerente com o banco ter de ler a tabela inteira nessas consultas.

### Hipóteses de causa

Três problemas encadeados. Cada hipótese é suposição até a medição de `experimentos.md` confirmar ou refutar.

**1. p95 alto → a CPU do banco está saturada.**
- Evidência: a baseline mostra o banco em ~100% da CPU e a API em ~7% (`recursos.txt`); `use-baseline` mostra que o banco está saturado, com trabalho esperando CPU.

**2. CPU do banco saturada → consultas mal otimizadas.**
- Evidência: as consultas de pedidos do cliente gastam ~57% do tempo do banco com ~22,5% das requisições (`pgss-baseline`). Em `rotas-isoladas`, 6 das 17 consultas da rota somam ~99,9% do tempo dela no banco.

**3. Consultas mal otimizadas → falta de índice em `itens_pedido.pedido_id` e `pedidos.cliente_id`.**
- Evidência: só existem chaves primárias (`indices-antes.txt`), e os planos mostram o banco lendo a tabela inteira (descartando 499999 linhas em `itens_pedido` e 166665 por processo em `pedidos`) para devolver de 2 a 5. `itens_pedido` roda 5 vezes por requisição (≈82–83% do tempo da rota no banco); `pedidos`, 1 vez (≈17–18%).

## Rodada 2

Rodei depois dos dois índices (`01-indice-itens-pedido` e `02-indice-pedidos-cliente`, em `experimentos.md`). Os dois reduziram o p95 de `pedidos-do-cliente` (de 22594,2 para 9388,6 ms, −58,5%), mas o banco continuou saturado e o p95 continuou alto. Esta rodada mostra onde a CPU do banco é gasta e fecha em três frentes, nesta ordem:

1. **Conexões**: `db.js` abre uma conexão por consulta, em todas as rotas.
2. **`pedidos-por-status`**: maior parcela da CPU do banco.
3. **`top-produtos`**: maior custo de CPU por requisição e pior p95.

### Saídas

**`saidas/20261114-143738-pgss-pos-indices`**
- *Por que rodei:* depois dos dois índices, para saber se o banco continua saturado e quais consultas gastam mais tempo nele.
- *O que descobri:*
  - Saturação: o banco usou 0,99 CPU do limite de 1,00 e foi segurado em 96,0% dos períodos de controle (um período são ~100 ms em que o sistema confere quanto de CPU o contêiner gastou), com tarefa esperando CPU em 82,0% da janela. A API usou 0,14 CPU do limite de 0,50 e foi segurada em 1,8% dos períodos.
  - Consultas (tempo decorrido, não CPU): a lista e a contagem de `pedidos-por-status` somam 53,4% do tempo (32,9% + 20,5%), `vendas-por-dia` 16,5% e `top-produtos` 14,0%. As consultas da rota `pedidos-do-cliente` somam 1,5%.
  - Nessa execução, `pedidos-do-cliente` teve mediana de 7148,3 ms e p95 de 11600,6 ms (k6 de diagnóstico, não é baseline).

**`saidas/20261114-194425-conexoes-1`, `20261114-194655-conexoes-2` e `20261114-194853-conexoes-3`**
- *Por que rodei:* o `pg_stat_statements` mede só a execução da consulta, não o tempo de abrir a conexão. Em `api/src/db.js`, cada consulta abre e fecha a própria conexão, e `pedidos-do-cliente` faz 17 em sequência (`rotas.js`). Medi dentro do contêiner da API, com o sistema ocioso e sob a mesma carga do `medir.sh` (20 usuários, 60 s, semente 42), três vezes.
- *O que descobri:* (medianas por execução; `connect` é o tempo de abrir a conexão e `consulta` é um `select 1`)

  | fase | `connect` (1 / 2 / 3) | `consulta` (1 / 2 / 3) |
  |---|---|---|
  | ocioso | 4,2 / 4,2 / 4,2 ms | 0,5 / 0,5 / 0,5 ms |
  | sob carga | 196,3 / 149,3 / 196,25 ms | 94,0 / 5,35 / 3,5 ms |

  - Sob carga, abrir uma conexão leva tipicamente 196 ms (mediana das três medianas), contra 4,2 ms ocioso. Das 237 conexões sob carga, só 5 levaram menos de 50 ms e 77 levaram 200 ms ou mais. A mediana de fechar a conexão (`end`) foi 4,0 ms.
  - Custo de CPU: descontado o repouso do banco (saída seguinte), cada conexão custou ~5,9 a ~6,0 ms de CPU do banco (5.930, 5.979 e 6.006 µs).

**`saidas/20261114-202137-conexoes-controle-1`, `20261114-202228-conexoes-controle-2` e `20261114-202319-conexoes-controle-3`**
- *Por que rodei:* para descontar a CPU que o banco gasta em repouso, medi o banco sozinho, sem k6 e sem conexões, por 30 s, três vezes (`scripts/conexoes-controle.sh`).
- *O que descobri:* 375.168, 397.593 e 381.554 µs em 30,2 s (0,012 a 0,013 CPU), sem nenhum período segurado. A mediana é 381.554 µs.

**`saidas/20261115-112714-rotas-isoladas-pos-indices`**
- *Por que rodei:* para ler os planos de execução das consultas depois dos índices, rota por rota, sem concorrência (`scripts/rotas-isoladas.sh`).
- *O que descobri:*
  - `pedidos-do-cliente`: as 17 consultas somam ~0,6 ms no banco. A requisição inteira leva 127,0 ms ociosa.
  - `pedidos-por-status`: são duas consultas por requisição, a contagem e a lista. As duas fazem varredura sequencial de `pedidos` (500.000 linhas, 3 processos em paralelo). A lista ordena as linhas do status por `criado_em`: na página 1 guarda só as 20 primeiras (`top-N heapsort`, 42 kB); na página 1000 ordena ~300.000 linhas de `pago` em arquivo temporário no disco (`external merge`, ~30 MB por processo).
  - `top-produtos`: uma consulta que soma todos os itens de pedidos não cancelados e agrupa por produto. O plano lê `itens_pedido` inteira (1,5 milhão de linhas), junta com `pedidos` e `produtos` (1,35 milhão de linhas) e agrupa em 19.206 produtos. O plano é o mesmo de antes dos índices.
  - Medianas ociosas (ms, 5 chamadas por rota): cliente 9,6; cliente-por-email 36,7; pedidos-do-cliente 127,0; pedidos-por-status 187,1 (pago, página 1), 243,5 (cancelado, 500), 444,2 (pago, 1000); busca-produtos 19,8; vendas-por-dia 205,7; top-produtos 1007,0.

**`saidas/20261115-114814-cpu-por-rota-1`, `20261115-115049-cpu-por-rota-2` e `20261115-115322-cpu-por-rota-3`**
- *Por que rodei:* o `pg_stat_statements` ranqueia por tempo decorrido, que inclui a espera por CPU. `scripts/cpu-por-rota.sh` lê a CPU usada pelos contêineres (`cpu.stat`) antes e depois de 30 requisições em sequência a cada rota, descontando o repouso medido no início, e combina com os pesos do k6.
- *O que descobri:* (mediana das 3 execuções da CPU do banco por requisição; "parcela" usa os pesos do k6; "razão" é a parcela dividida pelo peso)

  | rota | peso no k6 | CPU do banco por requisição | parcela da CPU do banco | razão |
  |---|---|---|---|---|
  | `top-produtos` | 2% | 1056,2 ms | 17,0% | 8,5× |
  | `pedidos-por-status` (página 500) | 15% | 382,3 ms | 45,6% | 3,0× |
  | `vendas-por-dia` | 8% | 185,0 ms | 11,9% | 1,5× |
  | `pedidos-do-cliente` | 20% | 110,1 ms | 17,4% | 0,87× |
  | `cliente-por-email` | 15% | 37,5 ms | 4,4% | 0,29× |
  | `busca-produtos` | 15% | 19,6 ms | 2,3% | 0,15× |
  | `cliente` | 25% | 7,4 ms | 1,6% | 0,07× |

  - No mix do k6, uma requisição custa em média 123,8 a 127,3 ms de CPU do banco (três execuções).
  - `pedidos-por-status` custou 271 ms de CPU do banco na página 1 e 522 ms na página 1000.
  - A API gastou 15,6 a 18,7 ms de CPU por requisição no mix.

### Hipóteses de causa

Cada hipótese é suposição até a medição de `experimentos.md` confirmar ou refutar.

**1. p95 ainda alto depois dos índices → o banco segue saturado.**
- Evidência: `pgss-pos-indices` mostra o banco em 0,99 CPU, segurado em 96,0% dos períodos, e a API em 0,14 CPU (1,8% dos períodos). O mesmo padrão aparece nas outras duas execuções de USE (96,3% e 96,2%).

**2. Banco saturado → a CPU está concentrada em poucas rotas.**
- Evidência: em `cpu-por-rota`, `pedidos-por-status` (45,6%), `top-produtos` (17,0%) e `vendas-por-dia` (11,9%) somam 74 a 75% da CPU do banco no mix do k6, e `pedidos-do-cliente` outros 17,4%. No ranking do `pg_stat_statements`, as consultas de `pedidos-do-cliente` somam 1,5% do tempo.

### Frente 1: conexões

**3. Cada consulta abre uma conexão (`db.js`) → `pedidos-do-cliente` gasta CPU do banco em abrir 17 conexões.**
- Evidência: as consultas da rota somam ~0,6 ms no banco, mas a rota gasta 104,5 a 111,4 ms de CPU do banco por requisição (`cpu-por-rota`), perto de 17 conexões × ~6 ms (~102 ms). Sob carga, abrir uma conexão leva 196 ms de mediana, contra 4,2 ms ocioso; 17 conexões em sequência somam ~3,5 s por requisição (17 × 206 ms, soma das medianas de `connect`, `consulta` e `end`), contra 7148,3 ms de mediana da rota no k6.

### Frente 2: `pedidos-por-status`

**4. `pedidos-por-status` é a maior parcela da CPU → cada requisição lê `pedidos` inteira duas vezes e, em páginas fundas, ordena ~300.000 linhas em disco.**
- Evidência: 45,6% da CPU do banco no mix (382 ms por requisição na página 500, 271 ms na 1 e 522 ms na 1000). Nos planos, a contagem (36,7 a 95,7 ms) e a lista (90,4 ms na página 1, 390,8 ms na 1000) fazem varredura sequencial de `pedidos`, e a lista da página 1000 usa `external merge` em disco.

### Frente 3: `top-produtos`

**5. `top-produtos` é a rota mais cara por requisição → a consulta lê e agrega quase todos os itens.**
- Evidência: 1056 ms de CPU do banco por requisição (8,5× a parcela do seu peso) e p95 de 16813,5 ms no k6 do `pgss-pos-indices`. O plano lê `itens_pedido` inteira (1,5 milhão de linhas), junta com `pedidos` (só os cancelados são descartados, ~10%) e `produtos` e agrupa em 19.206 produtos. No plano, a leitura de `itens_pedido` leva 76 ms e a de `pedidos` 39 ms, de um total de 1329 ms.

## Scripts

| Script | Função |
|---|---|
| `scripts/use-sob-carga.sh <rotulo>` | Matriz USE via cgroup v2, sob a carga do `medir.sh` |
| `scripts/pgss-sob-carga.sh <rotulo>` | Igual, com `pg_stat_statements` zerado após o aquecimento; grava o ranking |
| `scripts/rotas-isoladas.sh` | Mede cada rota sozinha, sem concorrência (conferir descrição) |
| `scripts/conexoes-sob-carga.sh <rotulo>` | Mede `connect`, `select 1` e `end` de uma conexão do `pg`, de dentro da API, ocioso e sob a carga do `medir.sh`; grava `conexoes.csv` |
| `scripts/conexoes-controle.sh <rotulo>` | Mede o CPU do banco em repouso (sem k6 e sem conexões) numa janela de 30 s, para descontar o ruído de fundo |
| `scripts/cpu-por-rota.sh <rotulo>` | Mede a CPU do banco e da API por requisição de cada rota (30 requisições em sequência, descontado o repouso) e combina com os pesos do k6 |
| `pgss.yml` | Liga `pg_stat_statements` só no diagnóstico: `export COMPOSE_FILE=docker-compose.yml:diagnostico/pgss.yml`. Para medir: `unset COMPOSE_FILE` |

## IA

Usei IA para escrever estes scripts e buscar fontes; rodei tudo e as conclusões são minhas (ver seção 9 do artigo).
## Rodada 3: estado após o #8

Saídas em `diagnostico/saidas/`: `20261116-161317-rotas-isoladas-pos-8`, `20261116-161636-cpu-por-rota-pos-8-1`, `…161738-…-2`, `…161840-…-3` e `20261116-162256-pgss-pos-8`.

**Rota sozinha (`rotas-isoladas`).** `pedidos-do-cliente` dispara 17 consultas, que somam 0,2–0,3 ms no banco; a requisição leva 9,2 ms (mediana). `cliente-por-email` leva 27,7 ms e dispara 1 consulta (24,8–26,6 ms no banco). `vendas-por-dia`: 14,0 ms no banco na 2ª chamada e 229,2 ms de mediana HTTP.

**CPU por requisição (3 execuções).** Mix do k6: banco 11,48–12,34 ms, API 10,42–11,17 ms. `pedidos-do-cliente`: banco 3,42–3,62 ms, API 10,24–11,41 ms. `vendas-por-dia`: banco 38,2–40,6 ms, API 78,1–84,1 ms. A medição é sequencial e subestima o banco sob carga (veja abaixo).

**Sob carga (`pgss-pos-8`, 20 usuários, 60 s).** 45,92 req/s; mediana 276,5 ms, p95 1609,1 ms, p99 2222,6 ms; 0% de erros. Banco: 0,91 CPU de 1,00, throttled em 82,5% dos períodos, memória de 202,1 MiB no fim e 254,9 MiB no pico. API: 0,41 CPU de 0,50, throttled em 62,5% dos períodos, memória de 35,2 MiB no fim e 51,2 MiB no pico.

**Tempo do banco por consulta.** `lower(email)`: 39,1% (235,0 ms por chamada). `vendas-por-dia`: 16,9% (182,3 ms; 12,9 mil linhas por chamada). Listagem por status: 16,6% (103,4 ms; 21195 blocos temporários escritos). `count(*)` por status: 15,2% (95,1 ms). `produtos ILIKE`: 11,4% (65,6 ms). As consultas de `pedidos-do-cliente` somam 0,6%.

## Rodada 4: CPU e consultas não otimizadas

Estado medido: depois do #12 (branch `exp-12-indice-email-clientes-refeito`, commit b424474). Coleta em `diagnostico/saidas/20261118-094652-coleta/`, gerada por `diagnostico/coleta/*.sh`. A carga `diagnostico-carga` (65,6 req/s, p95 693 ms, 0% de erros, contrato mantido) não é medição de experimento: o banco foi reiniciado para ativar o `pg_stat_statements`.

### Fatos medidos

| fato | valor | arquivo |
|---|---|---|
| API no limite da cota | `nr_throttled` 715 de 782 períodos; CPU média 48,4%, máxima 51% | 06 |
| CPU da API por requisição | 37,6 s para ~4.800 requisições, ≈ 7,8 ms; teto ≈ 64 req/s (observado: 65,6) | 06 |
| `vendas-por-dia` na API | 81,6 ms de CPU por chamada; 392 chamadas ≈ 32 s, ~85% da CPU da API | 05, 06, 07 |
| Rotas leves | 2,0 a 2,8 ms de CPU de API e 0,4 a 0,8 ms de banco por requisição; mediana sob carga 190 a 200 ms | 05, 06 |
| Banco | 64% de CPU média; 42% dos períodos limitados; 46% da CPU em kernel; teto ≈ 95 req/s | 06 |
| Conexões | pool de 10; 0 a 1 ativa na maioria das amostras (amostras a cada ~2 s) | 06 |
| Memória do banco | 242 MiB de 512 MiB; sem eventos `high`/`max` | 06 |
| Tempo no banco (pgss, proporção) | vendas 43,6%; listagem 30,9%; busca 24,5%; resto ≤ 0,6% cada | 07 |
| Listagem | ~1 buffer por linha pulada pelo OFFSET (página 500: 10.003 buffers, 10,1 ms; página 6000: 117 mil, 67 ms) | 10 |
| Carga da listagem | `pagina` de 1 a 1000 (`carga/teste-carga.js:48`) | 10 |
| Página profunda | página 15000 vira Parallel Seq Scan com ordenação em disco, 600 ms; 68 arquivos temporários, 352 MB | 08, 10 |
| Vendas, plano | Gather com 2 workers, 14,6 ms; 17.308 de 18.322 buffers nas 4.313 sondagens em `itens_pedido` | 10 |
| Vendas, linhas | ~12,9 mil linhas por chamada; `observacoes` tem 277 bytes em média e o JS não a usa | 03, 07 |
| Busca | Seq Scan em `produtos` (713 varreduras); 9,9 ms de 10,3 ms no filtro `ILIKE`; collation `en_US.utf8`; `pg_trgm` 1.6 disponível | 08, 10 |
| Mapa de visibilidade | `relallvisible` = 0 em todas as tabelas no momento da coleta 03 | 03 |
| JIT | nenhuma consulta usou JIT | 10 |
| Log da API | `api/src/server.js` grava, em toda requisição, uma linha JSON com a resposta inteira (`resposta: corpo`) | 09 |

### Diagnóstico (inferências)

- A CPU da API é o gargalo. Quase toda ela vem de `vendas-por-dia` (SQL devolvendo ~4 MB por chamada e laço em JS). A cota de 0,5 CPU pausa o contêiner no meio dessas chamadas, o que provavelmente explica o piso de ~190 ms das rotas leves. A confirmar medindo a latência das rotas leves depois de reduzir a CPU de `vendas-por-dia`.
- O banco é o segundo limite (~95 req/s). Se a API deixar de ser o gargalo, o ganho fica limitado por ele, então precisa de mais de um passo.
- Os tempos do pg_stat_statements estão inflados pela divisão de CPU; usar só proporções.

### Candidatos, em ordem

1. `vendas-por-dia`: tirar `observacoes` do SELECT (isola o custo de transferência e conversão).
2. `vendas-por-dia`: agregar por dia no SQL (retestar o antigo #11; antes o banco saturava, agora o gargalo é a API).
3. Listagem: junção adiada sobre o índice existente `(status, criado_em DESC, id DESC)`, que já contém `id`, mais `VACUUM` num novo `banco/10-….sql` para preencher o mapa de visibilidade.
4. Busca: índice trigram (`pg_trgm`) em `produtos.nome`.
5. Paralelismo: comparar o custo de `vendas-por-dia` com `max_parallel_workers_per_gather` em 2 e em 0 (script `11`).
6. Índice de cobertura `INCLUDE (quantidade, preco_unitario_centavos)` em `itens_pedido`: ganho limitado (~1/4 dos buffers de vendas).
7. Log da API: registrar o corpo da resposta só quando o status for ≥ 400 e manter a linha por requisição (método, URL, status, duração).
   - O log não é requisito: o enunciado (seção 07) fixa o que a rota devolve, e `scripts/`, `carga/` e `verificar.js` não leem os logs da API. O README só diz onde os logs ficam (`docker compose logs -f api`), e isso continua valendo.
   - Os corpos de erro desta API são mensagens curtas (`{ erro: '...' }`), sem dados de clientes. O corpo das respostas 200 inclui nome e e-mail de clientes, o que em uma aplicação real seria dado pessoal nos logs.
   - Declarar a mudança no `experimentos.md`, porque o conteúdo do log muda. O ganho de CPU é hipótese até medir.

### Descartados ou sem evidência

- Tamanho do pool: 0 a 1 conexão ativa por amostra.
- JIT: não usado.
- `shared_buffers` e `effective_cache_size`: só depois de ver se ainda há custo de kernel no banco depois dos passos 1 a 4.

### Limites

- A amostragem de conexões (~2 s) é fraca.
- O custo por rota foi medido sem carga, em sequência.
- A lei da utilização (teto = capacidade ÷ custo por requisição) ainda não tem fonte aberta.
- O custo do log com corpo ainda não foi medido isoladamente.

Fonte aberta: PostgreSQL 16, Index-Only Scans and Covering Indexes (https://www.postgresql.org/docs/16/indexes-index-only-scans.html).
