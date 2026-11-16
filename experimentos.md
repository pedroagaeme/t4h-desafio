# Experimentos

Uma linha por mudança.

## Procedimento

1. `unset COMPOSE_FILE` (nada do diagnóstico ligado).
2. Fazer uma única mudança.
3. `git commit` da mudança, para o `contexto.txt` mostrar 0 arquivos alterados sem commit.
4. `./scripts/verificar-contrato.sh comparar` passando (código de saída 0).
5. `./scripts/medir.sh <rotulo>` 3 vezes com o mesmo rótulo; comparar as medianas.
6. Commit separado de `resultados/` e nova linha na tabela abaixo.

Cada linha compara com o estado anterior, indicado na coluna "Pasta antes".

## Baseline

Rótulo `00-linha-de-base`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `fb41551`, 0 arquivos sem commit.

- `resultados/20261107-102646-00-linha-de-base`
- `resultados/20261107-102913-00-linha-de-base`
- `resultados/20261107-103052-00-linha-de-base`

Mediana de cada métrica entre as 3 execuções (valores de cada `resumo.txt`). Erros: 0,0% em todas as rotas, nas 3 execuções.

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 224 | 1048,1 | 20065,9 | 23204,7 |
| cliente | 54 | 396,8 | 699,4 | 795,7 |
| cliente-por-email | 38 | 998,8 | 1557,4 | 1958,0 |
| pedidos-do-cliente | 51 | 17494,2 | 22594,2 | 23449,4 |
| pedidos-por-status | 24 | 6447,1 | 9959,6 | 12041,3 |
| busca-produtos | 37 | 606,5 | 997,8 | 1128,9 |
| vendas-por-dia | 17 | 6066,3 | 7948,6 | 8135,5 |
| top-produtos | 3 | 14303,9 | 24825,4 | 25760,7 |

Requisições por segundo (total): 3,32.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 99,9% | 100,0% | 398,6 | 445,9 |
| api | 6,9% | 9,9% | 31,6 | 37,2 |

## Experimentos

Rodada = rodada de diagnóstico (`diagnostico/README.md`) que motivou a ideia. Pastas = rótulo das 3 execuções em `resultados/` (`*-<rótulo>`); a pasta "antes" é o estado de comparação (baseline ou o "depois" da linha anterior).

| # | Rodada | Ideia | Fonte | Status | Antes | Depois | Pasta antes | Pasta depois | Conclusão |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | Índice em `itens_pedido(pedido_id)` | [Docs 11.1](https://www.postgresql.org/docs/16/indexes-intro.html), [Docs 5.4.5](https://www.postgresql.org/docs/16/ddl-constraints.html) | Aplicada e medida | p95 `pedidos-do-cliente`: 22594,2 ms<br>p95 total: 20065,9 ms<br>3,32 req/s | p95 `pedidos-do-cliente`: 11518,9 ms<br>p95 total: 10717,4 ms<br>5,45 req/s | `*-00-linha-de-base` | `*-01-indice-itens-pedido` | H1 confirmada: p95 da rota caiu 49%, p95 total 47%, req/s +64%. `vendas-por-dia` piorou (p95 7948,6 → 14053,4 ms), causa não investigada |
| 2 | 1 | Índice em `pedidos(cliente_id)` | mesmas do #1 | Aplicada e medida | p95 `pedidos-do-cliente`: 11518,9 ms<br>p95 total: 10717,4 ms<br>5,45 req/s | p95 `pedidos-do-cliente`: 9388,6 ms<br>p95 total: 8796,8 ms<br>6,50 req/s | `*-01-indice-itens-pedido` | `*-02-indice-pedidos-cliente` | H2 confirmada: p95 da rota caiu 18,5%, p95 total 17,9%, req/s +19,3%. Ganho bem menor que o do #1; o banco segue em ~100% de CPU. `pedidos-por-status` melhorou sem ter sido alterada (p95 11004,6 → 8707,0 ms), causa não investigada |
| 3 | 2 | Trocar a conexão por consulta (`db.js`) por um `pg.Pool` na API | [node-postgres: Pooling](https://node-postgres.com/features/pooling), [node-postgres: Pool API](https://node-postgres.com/apis/pool), [Docs: client/server model](https://www.postgresql.org/docs/16/connect-estab.html) | Aplicada e medida | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | mediana total: 798,4 ms<br>p95 total: 7593,9 ms<br>p99 total: 12456,6 ms<br>8,82 req/s | `*-02-indice-pedidos-cliente` | `*-03-pool-api` | H3 confirmada: mediana total −11,0%, p95 −13,7%, p99 −24,8%, req/s +35,7%. O banco segue em CPU alta (média 91,7%, máx 100,0%) e a memória média da API subiu de 39,5 para 87,3 MiB. `pedidos-do-cliente` melhorou menos: mediana −24,5%, p95 −7,3%, p99 +4,0% |
| 4 | 2 | PgBouncer como serviço novo entre a API e o banco (API sem pool) | [PgBouncer: Features](https://www.pgbouncer.org/features.html), [PgBouncer: configuração](https://www.pgbouncer.org/config.html), [Yugabyte](https://www.yugabyte.com/blog/database-connection-management/) | Aplicada e medida | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | mediana total: 704,6 ms<br>p95 total: 7335,1 ms<br>p99 total: 13101,0 ms<br>8,61 req/s | `*-02-indice-pedidos-cliente` | `*-04-pgbouncer` | H4 confirmada: mediana total −21,5%, p95 −16,6%, p99 −20,9%, req/s +32,5%. Custo: contêiner novo com 3,9% de CPU média e 7,9 MiB de memória média. O banco segue em ~101% de CPU |
| 5 | 2 | Pgpool-II como serviço novo entre a API e o banco (API sem pool) | [Pgpool-II](https://www.pgpool.net/mediawiki/index.php/Main_Page), [Pgpool-II: pooling](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html), [Pgpool-II: conexões](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html) | Aplicada, sem ganho | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | mediana total: 546,9 ms<br>p95 total: 10688,1 ms<br>p99 total: 20878,4 ms<br>7,74 req/s | `*-02-indice-pedidos-cliente` | `*-05-pgpool` | H5 não confirmada: mediana total −39,1% e req/s +19,1%, mas p95 +21,5% e p99 +26,0%. Custo: contêiner novo com 11,8% de CPU média e 226,0 MiB de memória média. Configuração: limite de 256 MB e `enable_shared_relcache = off` (ver detalhe) |
| 6 | 2 | Índice em `pedidos(status, criado_em DESC, id DESC)` | [Docs 11.3](https://www.postgresql.org/docs/16/indexes-multicolumn.html), [Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html), [Winand: Pipelined/Indexed ORDER BY](https://use-the-index-luke.com/sql/sorting-grouping/indexed-order-by) | Aplicada e medida | mediana total: 798,4 ms<br>p95 total: 7593,9 ms<br>p99 total: 12456,6 ms<br>8,82 req/s | mediana total: 498,7 ms<br>p95 total: 5704,1 ms<br>p99 total: 9063,8 ms<br>14,83 req/s | `*-03-pool-api` | `*-06-indice-pedidos-status` | H6 confirmada: mediana total −37,5%, p95 −24,9%, p99 −27,2%, req/s +68,1%. As 21 comparações por rota (7 rotas × mediana, p95 e p99) melhoraram; `pedidos-por-status`: mediana 3090,7 → 680,0 ms. Sem serviço novo; o banco segue em ~100% de CPU. Tamanho do índice não medido |
| 7 | 2 | Índice em `pedidos(criado_em)` e filtro de `vendas-por-dia` reescrito como intervalo (`criado_em >= $1::date AND criado_em < $2::date + 1`, no lugar de `criado_em::date BETWEEN`); índice e reescrita só funcionam juntos, então são uma única mudança | [Winand: datas e índices](https://use-the-index-luke.com/sql/where-clause/obfuscation/dates) | Aplicada e medida | mediana `vendas-por-dia`: 1695,7 ms<br>p95 `vendas-por-dia`: 7386,2 ms<br>p99 `vendas-por-dia`: 9995,5 ms<br>14,83 req/s | mediana `vendas-por-dia`: 826,7 ms<br>p95 `vendas-por-dia`: 2583,2 ms<br>p99 `vendas-por-dia`: 3617,9 ms<br>17,34 req/s | `*-06-indice-pedidos-status` | `*-07-indice-pedidos-criado-em` | H7 confirmada: `vendas-por-dia` mediana −51,2%, p95 −65,0%, p99 −63,8%. Total: mediana −1,9%, p95 −19,7%, p99 −8,2%, req/s +16,9%. O p95 e o p99 de `pedidos-por-status` pioraram (3449,8 → 5999,1 e 6721,0 → 12042,7 ms), causa não investigada. Sem serviço novo; tamanho do índice não medido |
| 8 | 2 | View materializada `mv_top_produtos` com as somas por produto (pedidos não cancelados) e índice `(receita_centavos DESC, id)`; `top-produtos` passa a ler a view no lugar de agregar `itens_pedido` | [Docs 41.3](https://www.postgresql.org/docs/16/rules-materializedviews.html), [REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html), [Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html) | Aplicada e medida | mediana `top-produtos`: 7438,2 ms<br>p95 `top-produtos`: 14929,4 ms<br>p99 `top-produtos`: 16410,2 ms<br>17,34 req/s | mediana `top-produtos`: 70,7 ms<br>p95 `top-produtos`: 289,5 ms<br>p99 `top-produtos`: 364,6 ms<br>42,86 req/s | `*-07-indice-pedidos-criado-em` | `*-08-view-top-produtos` | H8 confirmada: `top-produtos` mediana −99,0%, p95 −98,1%, p99 −97,8%. Total: mediana −40,3%, p95 −62,4%, p99 −71,1%, req/s +147,2%. As 21 comparações por rota melhoraram. Memória do banco subiu (máx. 449,0 → 495,8 MiB de 512 MiB), causa não investigada. Sem serviço novo; a view ocupa 2664 kB (com o índice) e um `REFRESH` leva 1012,4 ms |

Status: `Aplicada e medida`, `Aplicada, sem ganho` ou `Pesquisada, teste futuro`. Ao medir, troque o status e preencha Depois (medianas das 3 execuções), a pasta e a conclusão.

### Detalhe do #1 (mediana das 3 execuções, antes → depois)

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 224 → 340 | 1048,1 → 898,4 | 20065,9 → 10717,4 | 23204,7 → 17400,8 |
| cliente | 54 → 83 | 396,8 → 297,8 | 699,4 → 598,5 | 795,7 → 819,9 |
| cliente-por-email | 38 → 56 | 998,8 → 896,9 | 1557,4 → 1340,1 | 1958,0 → 1782,4 |
| pedidos-do-cliente | 51 → 68 | 17494,2 → 8003,5 | 22594,2 → 11518,9 | 23449,4 → 12206,4 |
| pedidos-por-status | 24 → 48 | 6447,1 → 5723,1 | 9959,6 → 11004,6 | 12041,3 → 22125,4 |
| busca-produtos | 37 → 60 | 606,5 → 499,0 | 997,8 → 793,4 | 1128,9 → 977,3 |
| vendas-por-dia | 17 → 25 | 6066,3 → 6417,8 | 7948,6 → 14053,4 | 8135,5 → 18860,6 |
| top-produtos | 3 → 5 | 14303,9 → 16802,2 | 24825,4 → 30522,3 | 25760,7 → 32745,8 |

Requisições por segundo: 3,32 → 5,45. Erros: 0,0% nas 3 execuções.
O p95 de `pedidos-do-cliente` nas 3 execuções foi 11518,9, 10708,3 e 12513,5 ms, todos abaixo do menor valor da baseline (22017,4 ms).

### Detalhe do #2 (mediana das 3 execuções, antes → depois)

Rótulo `02-indice-pedidos-cliente`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `182842e`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções.

- `resultados/20261114-142312-02-indice-pedidos-cliente`
- `resultados/20261114-142444-02-indice-pedidos-cliente`
- `resultados/20261114-142617-02-indice-pedidos-cliente`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 340 → 417 | 898,4 → 897,5 | 10717,4 → 8796,8 | 17400,8 → 16570,7 |
| cliente | 83 → 111 | 297,8 → 303,3 | 598,5 → 586,4 | 819,9 → 700,5 |
| cliente-por-email | 56 → 64 | 896,9 → 894,2 | 1340,1 → 1178,8 | 1782,4 → 1475,3 |
| pedidos-do-cliente | 68 → 83 | 8003,5 → 5687,9 | 11518,9 → 9388,6 | 12206,4 → 10396,2 |
| pedidos-por-status | 48 → 57 | 5723,1 → 5598,3 | 11004,6 → 8707,0 | 22125,4 → 12159,9 |
| busca-produtos | 60 → 70 | 499,0 → 495,2 | 793,4 → 714,7 | 977,3 → 918,1 |
| vendas-por-dia | 25 → 29 | 6417,8 → 5622,4 | 14053,4 → 14231,2 | 18860,6 → 20786,4 |
| top-produtos | 5 → 5 | 16802,2 → 22700,8 | 30522,3 → 24875,9 | 32745,8 → 26467,6 |

Requisições por segundo: 5,45 → 6,50. Erros: 0,0% nas 3 execuções.
O p95 de `pedidos-do-cliente` nas 3 execuções foi 10390,8, 9100,6 e 9388,6 ms, todos abaixo do menor valor de antes (10708,3 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% | 99,9% | 398,9 | 466,5 |
| api | 11,7% | 9,7% | 39,5 | 54,0 |

### Detalhe do #3 (mediana das 3 execuções, antes → depois)

Rótulo `03-pool-api`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `ac59284`, 0 arquivos sem commit.

- `resultados/20261116-110453-03-pool-api`
- `resultados/20261116-110622-03-pool-api`
- `resultados/20261116-110757-03-pool-api`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 417 → 558 | 897,5 → 798,4 | 8796,8 → 7593,9 | 16570,7 → 12456,6 |
| cliente | 111 → 153 | 303,3 → 201,6 | 586,4 → 703,6 | 700,5 → 1131,2 |
| cliente-por-email | 64 → 82 | 894,2 → 685,1 | 1178,8 → 1194,5 | 1475,3 → 1403,9 |
| pedidos-do-cliente | 83 → 114 | 5687,9 → 4296,0 | 9388,6 → 8704,7 | 10396,2 → 10807,2 |
| pedidos-por-status | 57 → 79 | 5598,3 → 3090,7 | 8707,0 → 6748,1 | 12159,9 → 12942,0 |
| busca-produtos | 70 → 87 | 495,2 → 383,6 | 714,7 → 875,7 | 918,1 → 1469,3 |
| vendas-por-dia | 29 → 39 | 5622,4 → 2916,7 | 14231,2 → 8050,7 | 20786,4 → 10611,9 |
| top-produtos | 5 → 8 | 22700,8 → 12252,3 | 24875,9 → 21509,6 | 26467,6 → 21902,8 |

Requisições por segundo: 6,50 → 8,82 (9,51, 8,44 e 8,82 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Nas 3 execuções, a mediana total (798,4, 801,8 e 699,4 ms), o p95 total (7100,0, 8029,2 e 7593,9 ms) e o p99 total (11022,4, 15327,3 e 12456,6 ms) ficaram abaixo dos valores de antes (897,5, 8796,8 e 16570,7 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% → 91,7% | 99,9% → 100,0% | 398,9 → 403,0 | 466,5 → 458,7 |
| api | 11,7% → 11,0% | 9,7% → 9,9% | 39,5 → 87,3 | 54,0 → 96,6 |

### Detalhe do #4 (mediana das 3 execuções, antes → depois)

Rótulo `04-pgbouncer`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Configuração: imagem `edoburu/pgbouncer:v1.26.1-p0`, `pool_mode = transaction`, `default_pool_size = 10`, limites do contêiner de 0,25 CPU e 64 MB; a API sem pool, apontando para o PgBouncer.

- `resultados/20261116-113231-04-pgbouncer`
- `resultados/20261116-113402-04-pgbouncer`
- `resultados/20261116-113534-04-pgbouncer`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 417 → 558 | 897,5 → 704,6 | 8796,8 → 7335,1 | 16570,7 → 13101,0 |
| cliente | 111 → 153 | 303,3 → 199,3 | 586,4 → 710,8 | 700,5 → 899,3 |
| cliente-por-email | 64 → 80 | 894,2 → 601,0 | 1178,8 → 1283,6 | 1475,3 → 1517,5 |
| pedidos-do-cliente | 83 → 116 | 5687,9 → 4590,3 | 9388,6 → 8042,7 | 10396,2 → 9688,9 |
| pedidos-por-status | 57 → 78 | 5598,3 → 3400,4 | 8707,0 → 7861,8 | 12159,9 → 13757,6 |
| busca-produtos | 70 → 86 | 495,2 → 303,3 | 714,7 → 763,2 | 918,1 → 995,8 |
| vendas-por-dia | 29 → 38 | 5622,4 → 3787,1 | 14231,2 → 8411,6 | 20786,4 → 9993,8 |
| top-produtos | 5 → 8 | 22700,8 → 14461,4 | 24875,9 → 20464,0 | 26467,6 → 21238,4 |

Requisições por segundo: 6,50 → 8,61 (8,48, 8,61 e 8,82 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Nas 3 execuções, a mediana total (700,1, 704,6 e 708,8 ms), o p95 total (7272,5, 7335,1 e 7364,1 ms) e o p99 total (13554,4, 11243,3 e 13101,0 ms) ficaram abaixo dos valores de antes (897,5, 8796,8 e 16570,7 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% → 100,9% | 99,9% → 100,0% | 398,9 → 404,9 | 466,5 → 460,0 |
| pgbouncer | — → 3,9% | — → 7,8% | — → 7,9 | — → 8,2 |
| api | 11,7% → 14,5% | 9,7% → 9,6% | 39,5 → 37,5 | 54,0 → 45,5 |

### Detalhe do #5 (mediana das 3 execuções, antes → depois)

Rótulo `05-pgpool`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `57da491`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Configuração: imagem `pgpool/pgpool:latest` (Pgpool-II 4.4.2, criada em 2023-03-03, `sha256:3782cbf9…`), configurada por variáveis `PGPOOL_PARAMS_*` (backend `banco:5432`, escuta em `*:9999`, `connection_cache = on`), limites do contêiner de 0,25 CPU e 256 MB, e `enable_shared_relcache = off`. A API sem pool, apontando para o Pgpool-II.

Duas escolhas fora do padrão: limite de memória de 256 MB (com 128 MB o contêiner ficou com 127,8 MiB de uso em repouso, no limite) e `enable_shared_relcache = off` (o padrão da imagem é `on`; com ele ligado, processos-filho do Pgpool-II terminaram por falha de segmentação sob carga, causa não investigada).

- `resultados/20261116-124032-05-pgpool`
- `resultados/20261116-124335-05-pgpool`
- `resultados/20261116-131529-05-pgpool`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 417 → 536 | 897,5 → 546,9 | 8796,8 → 10688,1 | 16570,7 → 20878,4 |
| cliente | 111 → 146 | 303,3 → 99,5 | 586,4 → 202,9 | 700,5 → 349,6 |
| cliente-por-email | 64 → 80 | 894,2 → 507,6 | 1178,8 → 1102,0 | 1475,3 → 1391,4 |
| pedidos-do-cliente | 83 → 109 | 5687,9 → 1812,0 | 9388,6 → 3579,6 | 10396,2 → 3895,6 |
| pedidos-por-status | 57 → 75 | 5598,3 → 6788,3 | 8707,0 → 12895,4 | 12159,9 → 16404,9 |
| busca-produtos | 70 → 86 | 495,2 → 290,1 | 714,7 → 496,8 | 918,1 → 728,0 |
| vendas-por-dia | 29 → 38 | 5622,4 → 5913,9 | 14231,2 → 14839,1 | 20786,4 → 17625,2 |
| top-produtos | 5 → 7 | 22700,8 → 26090,0 | 24875,9 → 38327,0 | 26467,6 → 39030,9 |

Requisições por segundo: 6,50 → 7,74 (8,04, 7,74 e 7,38 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Nas 3 execuções, a mediana total (507,6, 546,9 e 601,6 ms) ficou abaixo do valor de antes (897,5 ms), e o p95 total (10688,1, 10092,2 e 11459,6 ms) e o p99 total (20878,4, 21799,7 e 19877,2 ms) ficaram acima dos de antes (8796,8 e 16570,7 ms).
Por rota, 13 das 21 comparações (7 rotas × mediana, p95 e p99) melhoraram. As 8 que pioraram: mediana de `pedidos-por-status` (5598,3 → 6788,3 ms), p95 de `pedidos-por-status` (8707,0 → 12895,4 ms), p99 de `pedidos-por-status` (12159,9 → 16404,9 ms), mediana de `vendas-por-dia` (5622,4 → 5913,9 ms), p95 de `vendas-por-dia` (14231,2 → 14839,1 ms), mediana de `top-produtos` (22700,8 → 26090,0 ms), p95 de `top-produtos` (24875,9 → 38327,0 ms) e p99 de `top-produtos` (26467,6 → 39030,9 ms).

Comparação com os outros dois (mesmo estado de antes): contra o #4 (PgBouncer), mediana −22,4%, p95 +45,7%, p99 +59,4%, req/s −10,1%; contra o #3 (`pg.Pool`), mediana −31,5%, p95 +40,7%, p99 +67,6%, req/s −12,2%.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% → 98,1% | 99,9% → 99,8% | 398,9 → 420,1 | 466,5 → 472,1 |
| pgpool | — → 11,8% | — → 9,8% | — → 226,0 | — → 227,6 |
| api | 11,7% → 15,8% | 9,7% → 9,3% | 39,5 → 41,9 | 54,0 → 60,0 |

### Detalhe do #6 (mediana das 3 execuções, antes → depois)

Rótulo `06-indice-pedidos-status`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `37e770e`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança: `banco/05-indice-pedidos-status.sql`, com `CREATE INDEX idx_pedidos_status_criado_em_id ON pedidos (status, criado_em DESC, id DESC)`. Estado de comparação: o #3 (`pg.Pool`).

`EXPLAIN (ANALYZE, BUFFERS)` da listagem com `status = 'pago'`, `ORDER BY criado_em DESC, id DESC`, `LIMIT 20`: página 1 (`OFFSET 0`) e página 1000 (`OFFSET 19980`) usam `Index Scan using idx_pedidos_status_criado_em_id`, sem etapa `Sort`, com 0,385 ms e 33,560 ms de execução.

- `resultados/20261116-134534-06-indice-pedidos-status`
- `resultados/20261116-134734-06-indice-pedidos-status`
- `resultados/20261116-134927-06-indice-pedidos-status`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 558 → 920 | 798,4 → 498,7 | 7593,9 → 5704,1 | 12456,6 → 9063,8 |
| cliente | 153 → 241 | 201,6 → 109,0 | 703,6 → 398,3 | 1131,2 → 592,2 |
| cliente-por-email | 82 → 141 | 685,1 → 506,5 | 1194,5 → 797,1 | 1403,9 → 956,4 |
| pedidos-do-cliente | 114 → 196 | 4296,0 → 2463,7 | 8704,7 → 6742,4 | 10807,2 → 8733,0 |
| pedidos-por-status | 79 → 133 | 3090,7 → 680,0 | 6748,1 → 3449,8 | 12942,0 → 6721,0 |
| busca-produtos | 87 → 138 | 383,6 → 286,9 | 875,7 → 599,4 | 1469,3 → 760,0 |
| vendas-por-dia | 39 → 63 | 2916,7 → 1695,7 | 8050,7 → 7386,2 | 10611,9 → 9995,5 |
| top-produtos | 8 → 15 | 12252,3 → 9588,0 | 21509,6 → 18367,9 | 21902,8 → 19411,3 |

Requisições por segundo: 8,82 → 14,83 (15,08, 14,71 e 14,83 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Nas 3 execuções, a mediana total (498,7, 504,8 e 496,9 ms), o p95 total (5897,7, 5704,1 e 4734,5 ms) e o p99 total (8539,1, 9063,8 e 10696,5 ms) ficaram abaixo dos valores de antes (798,4, 7593,9 e 12456,6 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 91,7% → 99,8% | 100,0% → 99,7% | 403,0 → 424,6 | 458,7 → 483,4 |
| api | 11,0% → 16,1% | 9,9% → 9,4% | 87,3 → 38,5 | 96,6 → 55,1 |

A memória média da API caiu de 87,3 para 38,5 MiB com o `db.js` ainda usando `pg.Pool`; causa não investigada.

### Detalhe do #7 (mediana das 3 execuções, antes → depois)

Rótulo `07-indice-pedidos-criado-em`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança, em um só commit: `banco/06-indice-pedidos-criado-em.sql` (`CREATE INDEX idx_pedidos_criado_em ON pedidos (criado_em)`) e, em `api/src/rotas.js`, o filtro de `vendas-por-dia` de `p.criado_em::date BETWEEN $1 AND $2` para `p.criado_em >= $1::date AND p.criado_em < $2::date + 1`. Estado de comparação: o #6.

Conferência antes de medir: para 2024-03-01 a 2024-03-07, `criado_em::date BETWEEN` e o intervalo contaram os mesmos 4793 pedidos. O `EXPLAIN (ANALYZE, BUFFERS)` da consulta nova usa `Bitmap Index Scan on idx_pedidos_criado_em` e `Parallel Bitmap Heap Scan on pedidos` (descarta 159 linhas por processo, contra 165228 da leitura sequencial anterior), com 37,7 ms de execução em uma chamada, contra 102,8 ms no plano anterior; são execuções únicas, com estado de cache diferente.

- `resultados/20261116-144036-07-indice-pedidos-criado-em`
- `resultados/20261116-144254-07-indice-pedidos-criado-em`
- `resultados/20261116-144427-07-indice-pedidos-criado-em`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 920 → 1091 | 498,7 → 489,0 | 5704,1 → 4579,8 | 9063,8 → 8316,2 |
| cliente | 241 → 287 | 109,0 → 103,0 | 398,3 → 370,2 | 592,2 → 591,4 |
| cliente-por-email | 141 → 169 | 506,5 → 515,4 | 797,1 → 807,7 | 956,4 → 993,7 |
| pedidos-do-cliente | 196 → 223 | 2463,7 → 2287,0 | 6742,4 → 5140,7 | 8733,0 → 6292,5 |
| pedidos-por-status | 133 → 153 | 680,0 → 606,6 | 3449,8 → 5999,1 | 6721,0 → 12042,7 |
| busca-produtos | 138 → 167 | 286,9 → 234,3 | 599,4 → 494,7 | 760,0 → 607,8 |
| vendas-por-dia | 63 → 75 | 1695,7 → 826,7 | 7386,2 → 2583,2 | 9995,5 → 3617,9 |
| top-produtos | 15 → 18 | 9588,0 → 7438,2 | 18367,9 → 14929,4 | 19411,3 → 16410,2 |

Requisições por segundo: 14,83 → 17,34 (17,34, 17,88 e 17,10 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Em `vendas-por-dia`, nas 3 execuções a mediana (885,9, 826,7 e 814,3 ms), o p95 (2482,7, 3215,3 e 2583,2 ms) e o p99 (3759,0, 3617,9 e 3594,8 ms) ficaram abaixo dos valores de antes (1695,7, 7386,2 e 9995,5 ms).
Por rota, 16 das 21 comparações (7 rotas × mediana, p95 e p99) melhoraram. As 5 que pioraram: mediana de `cliente-por-email` (506,5 → 515,4 ms), p95 de `cliente-por-email` (797,1 → 807,7 ms), p99 de `cliente-por-email` (956,4 → 993,7 ms), p95 de `pedidos-por-status` (3449,8 → 5999,1 ms) e p99 de `pedidos-por-status` (6721,0 → 12042,7 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 99,8% → 98,5% | 99,7% → 99,8% | 424,6 → 413,2 | 483,4 → 449,0 |
| api | 16,1% → 16,3% | 9,4% → 9,8% | 38,5 → 34,2 | 55,1 → 44,0 |

### Detalhe do #8 (mediana das 3 execuções, antes → depois)

Rótulo `08-view-top-produtos`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança, em um só commit: `banco/07-view-top-produtos.sql` (`CREATE MATERIALIZED VIEW mv_top_produtos` com as somas por produto dos pedidos não cancelados, índice `(receita_centavos DESC, id)` e `ANALYZE`) e, em `api/src/rotas.js`, a consulta de `top-produtos` passa a ler a view. Estado de comparação: o #7.

Uma primeira série de 3 execuções foi descartada porque o `contexto.txt` mostrava 1 arquivo sem commit (uma pasta de diagnóstico ainda não comitada); as 3 execuções abaixo foram feitas depois de comitar.

- `resultados/20261116-154430-08-view-top-produtos`
- `resultados/20261116-154551-08-view-top-produtos`
- `resultados/20261116-154712-08-view-top-produtos`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 1091 → 2604 | 489,0 → 291,9 | 4579,8 → 1721,2 | 8316,2 → 2401,0 |
| cliente | 287 → 681 | 103,0 → 82,1 | 370,2 → 299,6 | 591,4 → 442,0 |
| cliente-por-email | 169 → 377 | 515,4 → 380,4 | 807,7 → 598,0 | 993,7 → 697,9 |
| pedidos-do-cliente | 223 → 532 | 2287,0 → 1200,7 | 5140,7 → 2386,3 | 6292,5 → 2871,2 |
| pedidos-por-status | 153 → 362 | 606,6 → 378,5 | 5999,1 → 1014,2 | 12042,7 → 1738,7 |
| busca-produtos | 167 → 396 | 234,3 → 194,0 | 494,7 → 402,0 | 607,8 → 579,7 |
| vendas-por-dia | 75 → 207 | 826,7 → 390,6 | 2583,2 → 709,8 | 3617,9 → 1010,0 |
| top-produtos | 18 → 44 | 7438,2 → 70,7 | 14929,4 → 289,5 | 16410,2 → 364,6 |

Requisições por segundo: 17,34 → 42,86 (43,08, 42,81 e 42,86 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Em `top-produtos`, nas 3 execuções a mediana (27,6, 80,5 e 70,7 ms), o p95 (310,8, 289,5 e 199,8 ms) e o p99 (369,7, 364,6 e 354,8 ms) ficaram abaixo dos valores de antes (7438,2, 14929,4 e 16410,2 ms). A rota teve 44 a 45 requisições por execução, então os percentis têm pouca amostra, e a mediana variou de 27,6 a 80,5 ms entre as execuções.
Por rota, as 21 comparações (7 rotas × mediana, p95 e p99) melhoraram.

Custo da view (`diagnostico/saidas/20261116-153548-top-produtos-view/`): `pg_total_relation_size('mv_top_produtos')` = 2664 kB, somando a view e o índice. O tempo de criação não foi medido; como proxy, `REFRESH MATERIALIZED VIEW mv_top_produtos` levou 1012,357 ms, porque o `REFRESH` executa de novo a mesma consulta (documentação do PostgreSQL). O `EXPLAIN (ANALYZE, BUFFERS)` da consulta nova usa `Index Scan using idx_mv_top_produtos_receita` e leva 0,119 ms em uma chamada, contra 1287,6 ms e 1329,5 ms nos planos anteriores; são execuções únicas, com estado de cache diferente.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 98,5% → 91,4% | 99,8% → 99,6% | 413,2 → 473,4 | 449,0 → 495,8 |
| api | 16,3% → 38,9% | 9,8% → 50,4% | 34,2 → 40,6 | 44,0 → 49,4 |

## Hipóteses (escritas antes de aplicar)

**H1 (#1).** Criar um índice em `itens_pedido(pedido_id)` deve reduzir o p95 da rota `pedidos-do-cliente`, porque, segundo a Rodada 1, cada uma das 5 consultas por requisição hoje lê a tabela inteira (varredura sequencial) e descarta 499999 linhas para devolver 2.

**H2 (#2).** Criar um índice em `pedidos(cliente_id)` deve reduzir o p95 da rota `pedidos-do-cliente` sobre o estado após o #1, porque, segundo a Rodada 1, a consulta hoje lê a tabela inteira (varredura sequencial) e descarta 166665 linhas por processo para devolver 5.

**H3 (#3).** Trocar a conexão por consulta (`db.js`) por um `pg.Pool` deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, porque criar uma conexão leva tempo e hoje cada consulta cria a sua.

**H4 (#4).** Colocar o PgBouncer entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3: o custo vem de abrir conexões ao banco, que está saturado, e o PgBouncer é um pooler de conexões que reaproveita as conexões ao servidor. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

**H5 (#5).** Colocar o Pgpool-II entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3, porque o Pgpool-II lista pool de conexões entre as suas funções. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

**H6 (#6).** Criar um índice em `pedidos(status, criado_em DESC, id DESC)` deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #3, porque, segundo a Rodada 2, `pedidos-por-status` é 45,6% da CPU do banco no mix do k6 e a lista lê `pedidos` inteira e, na página 1000, ordena ~300.000 linhas em arquivo temporário no disco, e um índice na mesma ordem do `ORDER BY` entrega as linhas já ordenadas e dispensa essa ordenação ([Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html)), o que Winand chama de *pipelined order by* ([Use The Index, Luke](https://use-the-index-luke.com/sql/sorting-grouping/indexed-order-by)).

**H7 (#7).** Criar um índice em `pedidos(criado_em)` e trocar o filtro de `vendas-por-dia`, de `criado_em::date BETWEEN $1 AND $2` para o intervalo `criado_em >= $1::date AND criado_em < $2::date + 1`, deve reduzir a mediana, o p95 e o p99 da rota `vendas-por-dia` sobre o estado após o #6, porque, segundo a Rodada 2, a rota gasta 185,0 ms de CPU do banco por requisição (11,9% da CPU do banco no mix do k6) e o plano lê `pedidos` inteira (~500.000 linhas, descartando ~495.700) para devolver ~4.300, já que o filtro com conversão sobre a coluna impede o uso de um índice sobre ela, e uma condição de intervalo permite usá-lo ([Winand](https://use-the-index-luke.com/sql/where-clause/obfuscation/dates)). Como `criado_em` é `timestamp without time zone`, a reescrita deve devolver os mesmos pedidos; isso é conferido por consulta antes de medir.

**H8 (#8).** Criar a view materializada `mv_top_produtos`, com a soma de `quantidade` e de `quantidade * preco_unitario_centavos` por produto sobre os pedidos não cancelados, e um índice nela em `(receita_centavos DESC, id)`, e trocar a consulta de `top-produtos` para ler a view, deve reduzir a mediana, o p95 e o p99 da rota `top-produtos` sobre o estado após o #7, porque, segundo a Rodada 2, a rota gasta 1056,2 ms de CPU do banco por requisição (17,0% da CPU do banco no mix do k6, com 2 de 100 pontos de peso) e o plano lê e junta cerca de 1,35 milhão de linhas a cada requisição para calcular as somas de 19.206 produtos e devolver 10 (duração real do plano: 1287,6 e 1329,5 ms), e uma view materializada guarda esse resultado já calculado, de modo que ler dela costuma ser bem mais rápido que consultar as tabelas de origem ([Docs 41.3](https://www.postgresql.org/docs/16/rules-materializedviews.html)); o índice na mesma ordem do `ORDER BY` entrega as linhas já ordenadas ([Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html)). A view só reflete os dados até o último `REFRESH` ([REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html)); como nenhuma rota da API altera `itens_pedido` nem `pedidos`, a view criada depois da carga não fica defasada. O custo (tamanho da view e tempo de criação) entra na comparação. A saída deve ficar idêntica; isso é conferido por `comparar` antes de medir.


Os #3, #4 e #5 são testados separadamente, cada um sobre o estado após o #2 e sem os outros dois aplicados.
O #6 parte do estado após o #3 (o `pg.Pool`, adotado entre os três por melhorar as métricas sem contêiner novo).
O #7 parte do estado após o #6.
O #8 parte do estado após o #7.