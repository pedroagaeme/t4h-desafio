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
| 9 | 1 e 3 | Junção única (`pedidos LEFT JOIN itens_pedido LEFT JOIN produtos`) em `pedidos-do-cliente`, no lugar de uma consulta de itens por pedido e uma de produto por item; o agrupamento por pedido passa a ser feito em JavaScript | [Winand: Nested Loops, ORMs and the N+1 Problem](https://use-the-index-luke.com/sql/join/nested-loops-join-n1-problem) | Aplicada e medida | mediana `pedidos-do-cliente`: 1200,7 ms<br>p95 `pedidos-do-cliente`: 2386,3 ms<br>p99 `pedidos-do-cliente`: 2871,2 ms<br>42,86 req/s | mediana `pedidos-do-cliente`: 393,9 ms<br>p95 `pedidos-do-cliente`: 767,1 ms<br>p99 `pedidos-do-cliente`: 938,6 ms<br>45,21 req/s | `*-08-view-top-produtos` | `*-09-juncao-pedidos-do-cliente` | H9 confirmada: `pedidos-do-cliente` mediana −67,2%, p95 −67,9%, p99 −67,3%. Total: p95 −47,1%, p99 −39,4%, req/s +5,5%, mas a mediana total subiu de 291,9 para 398,1 ms (+36,4%) e as 18 comparações das outras 6 rotas (mediana, p95 e p99) pioraram; causa não investigada (ver detalhe). A rota passou de 17 para 2 consultas por requisição (pelo código; contagem não medida depois da mudança). Sem serviço novo; CPU média do banco 91,4% → 92,1% |
| 10 | 3 | View materializada `mv_pedidos_por_status` (status, total) e `pedidos-por-status` lendo a contagem dela no lugar de `count(*)` | [Wiki: Slow Counting](https://wiki.postgresql.org/wiki/Slow_Counting), [Docs 41.3](https://www.postgresql.org/docs/16/rules-materializedviews.html), [REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html) | Aplicada e medida | mediana `pedidos-por-status`: 679,4 ms<br>p95 `pedidos-por-status`: 1596,0 ms<br>p99 `pedidos-por-status`: 2473,5 ms<br>45,21 req/s | mediana `pedidos-por-status`: 404,3 ms<br>p95 `pedidos-por-status`: 1203,3 ms<br>p99 `pedidos-por-status`: 1669,5 ms<br>55,57 req/s | `*-09-juncao-pedidos-do-cliente` | `*-10-view-contagem-status` | H10 confirmada: `pedidos-por-status` mediana −40,5%, p95 −24,6%, p99 −32,5% (as 3 execuções melhores que o antes nas 3 métricas). Total: mediana −21,6%, p95 −12,5%, p99 −21,7%, req/s +22,9%. CPU por requisição do banco 20,4 → 15,5 ms (−24,1%). Das 18 comparações das outras 6 rotas, 17 melhoraram e 1 piorou (p99 de `busca-produtos`, +18,7%). Sem serviço novo; a view ocupa 16 kB e um `REFRESH` leva 70,583 ms. A primeira tentativa do #10 não alterou a rota e foi refeita (ver nota no detalhe). Memória do banco: máx. 507,2 MiB de 512 MiB (ver detalhe) |
| 11 | 3 | `vendas-por-dia` agrupando por dia no banco (`GROUP BY`, `count(DISTINCT p.id)`, `sum`), sem a coluna `observacoes`, no lugar de trazer uma linha por item e agrupar em JavaScript | [Docs 9.21](https://www.postgresql.org/docs/16/functions-aggregate.html) | Aplicada, sem ganho | mediana `vendas-por-dia`: 593,2 ms<br>p95 `vendas-por-dia`: 1025,7 ms<br>p99 `vendas-por-dia`: 1250,7 ms<br>55,57 req/s | mediana `vendas-por-dia`: 605,5 ms<br>p95 `vendas-por-dia`: 1032,9 ms<br>p99 `vendas-por-dia`: 1397,7 ms<br>54,26 req/s | `*-10-view-contagem-status` | `*-11-agregacao-vendas-por-dia` | H11 retestada não confirmada: `vendas-por-dia` mediana +2,1%, p95 +0,7%, p99 +11,8% (mediana acima do antes nas 3 execuções; p95 e p99 abaixo em 1 das 3). Total: mediana −3,7%, p95 −0,6%, p99 +31,3%, req/s −2,4%. A CPU média da API caiu de 43,9% para 5,9% e a do banco subiu de 85,9% para 100,4%; CPU por requisição do banco 15,5 → 18,5 ms (+19,7%). Das 18 comparações das outras 6 rotas, 12 melhoraram e 6 pioraram (de +0,2% a +33,4%): as rotas ligadas à API melhoraram na cauda e `pedidos-por-status` piorou (p95 +32,8%, p99 +33,4%). Não adotada: o código fica na branch `exp-11-agregacao-vendas-por-dia-refeito`, fora da linha principal; o #12 parte do estado após o #10. A primeira tentativa, sobre o estado do #9 com uma view sem uso, também não confirmou (ver nota no detalhe) |
| 12 | 3 | Índice em `clientes (lower(email))` para `cliente-por-email` | [Docs 11.7](https://www.postgresql.org/docs/16/indexes-expressional.html) | Aplicada e medida | mediana `cliente-por-email`: 486,8 ms<br>p95 `cliente-por-email`: 786,7 ms<br>p99 `cliente-por-email`: 899,8 ms<br>55,57 req/s | mediana `cliente-por-email`: 195,3 ms<br>p95 `cliente-por-email`: 507,7 ms<br>p99 `cliente-por-email`: 700,5 ms<br>65,71 req/s | `*-10-view-contagem-status` | `*-12-indice-email-clientes` | H12 confirmada: `cliente-por-email` mediana −59,9%, p95 −35,5%, p99 −22,1% (as 3 execuções melhores que o antes nas 3 métricas). Total: mediana −9,3%, p95 −12,3%, p99 −12,7%, req/s +18,2%. CPU por requisição do banco 15,5 → 9,8 ms (−36,9%); CPU média da API 43,9% → 48,6%, cerca de 97% da quota de 0,5 CPU. Das 18 comparações das outras 6 rotas, 13 melhoraram e 5 pioraram (de +0,6% a +32,1%; a maior em `top-produtos`, com 56 a 66 requisições por execução). Sem serviço novo; o índice ocupa 4.907.008 bytes (4792 kB) e a criação leva 422,075 ms (ver detalhe). A primeira tentativa, sobre o estado do #9 com uma view sem uso, deu resultado parecido (ver nota no detalhe) |
| 13 | 4 | Tirar `p.observacoes` do SELECT de `vendas-por-dia` (o JS não usa a coluna) | Rodada 4 (`diagnostico/README.md`) | Aplicada e medida | mediana `vendas-por-dia`: 540,0 ms<br>p95 `vendas-por-dia`: 988,7 ms<br>p95 total: 698,6 ms<br>65,71 req/s | mediana `vendas-por-dia`: 386,8 ms<br>p95 `vendas-por-dia`: 737,8 ms<br>p95 total: 521,1 ms<br>87,66 req/s | `*-12-indice-email-clientes` | `*-13-vendas-sem-observacoes` | H13 confirmada: `vendas-por-dia` mediana −28,4%, p95 −25,4%; req/s +33,4%. Total: mediana −31,0%, p95 −25,4%, p99 −2,0%. CPU média da API 48,6% → 43,1% com mais requisições (0,74 → 0,49 pontos percentuais de CPU por req/s); CPU média do banco 64,1% → 93,0%, então o banco passou a ser o limite (inferência). O p95 e o p99 de `pedidos-por-status` pioraram (903,3 → 1129,1 ms e 1227,9 → 1640,5 ms), causa não investigada. Sem serviço novo |
| 14 | 4 | Listagem de `pedidos` com junção adiada: subconsulta lê só `id` pelo índice `(status, criado_em DESC, id DESC)` e a consulta externa busca as 4 colunas da rota para os 20 `id`s; `VACUUM (ANALYZE) pedidos` em `banco/10-vacuum-pedidos.sql` | [Docs: Index-Only Scans and Covering Indexes](https://www.postgresql.org/docs/16/indexes-index-only-scans.html); Rodada 4 (`diagnostico/README.md`) | Aplicada e medida | mediana `pedidos-por-status`: 285,3 ms<br>p95 `pedidos-por-status`: 1129,1 ms<br>p99 `pedidos-por-status`: 1640,5 ms<br>87,66 req/s | mediana `pedidos-por-status`: 200,0 ms<br>p95 `pedidos-por-status`: 420,7 ms<br>p99 `pedidos-por-status`: 520,7 ms<br>107,34 req/s | `*-13-vendas-sem-observacoes` | `*-14-listagem-juncao-adiada` | H14 confirmada: `pedidos-por-status` mediana −29,9%, p95 −62,7%, p99 −68,3%; req/s +22,5%. Total: mediana −9,8%, p95 −21,9%, p99 −47,6%. Plano: Index Only Scan com `Heap Fetches: 0`; blocos lidos na página 500: 10.052 → 139 e na página 6000: 120.594 → 681 (`diagnostico/saidas/20261118-104954-explain-listagem-juncao-adiada/planos.txt` e `diagnostico/saidas/20261118-094652-coleta/10-explain-consultas.txt`). CPU média do banco 93,0% → 65,2%; da API 43,1% → 49,5% (cpu máx da API 51,7%), então a API voltou a ser o limite (inferência). Sem serviço novo; o `VACUUM` roda na criação do banco |
| 15 | 4 | Agregar `vendas-por-dia` no SQL (`GROUP BY` por dia, `COUNT(DISTINCT)`, `SUM`) em vez de somar em JavaScript | Rodada 4 (`diagnostico/README.md`) | Aplicada e medida | 107,3 req/s | 131,0 req/s (+22.0%) | 20261118-104326-14-listagem-juncao-adiada, 20261118-104445-14-listagem-juncao-adiada, 20261118-104605-14-listagem-juncao-adiada | 20261118-105823-15-vendas-agregacao-sql, 20261118-105943-15-vendas-agregacao-sql, 20261118-110103-15-vendas-agregacao-sql | API cai de 49,5% para 11,2% de CPU; o banco vira o limite (98,8%). Contrato mantido. |
| 16 | 4 | Índice GIN trigram (`pg_trgm`) em `produtos.nome` para a busca com `ILIKE` | Rodada 4 (`diagnostico/README.md`) | Aplicada e medida | 131,0 req/s | 169,6 req/s (+29.5%) | 20261118-105823-15-vendas-agregacao-sql, 20261118-105943-15-vendas-agregacao-sql, 20261118-110103-15-vendas-agregacao-sql | 20261118-110855-16-indice-trigram-produtos, 20261118-111014-16-indice-trigram-produtos, 20261118-111134-16-indice-trigram-produtos | Busca: mediana 202,0 → 96,8 ms; banco segue no limite (100,6%). Contrato mantido. |
| 17 | 4 | Desligar o paralelismo de consultas no banco (`max_parallel_workers_per_gather = 0`) | Documentação do PostgreSQL 16: When Can Parallel Query Be Used?, How Parallel Query Works, Planner Cost Constants | Aplicada e medida | 169,6 req/s | 270,9 req/s (+59.8%) | 20261118-110855-16-indice-trigram-produtos, 20261118-111014-16-indice-trigram-produtos, 20261118-111134-16-indice-trigram-produtos | 20261118-115137-17-sem-paralelismo-banco, 20261118-115257-17-sem-paralelismo-banco, 20261118-115416-17-sem-paralelismo-banco | Sem workers, o banco gasta 3,7 ms de CPU por requisição (antes 5,9); as rotas leves caem para ~10,8 ms. Contrato mantido. |
| 18 | 4 | View materializada `mv_vendas_por_dia` (uma linha por dia) para a rota `vendas-por-dia` | Documentação do PostgreSQL 16: Materialized Views, CREATE MATERIALIZED VIEW | Aplicada e medida | 270,9 req/s | 686,5 req/s (+153.4%) | 20261118-115137-17-sem-paralelismo-banco, 20261118-115257-17-sem-paralelismo-banco, 20261118-115416-17-sem-paralelismo-banco | 20261118-121030-18-view-vendas-por-dia, 20261118-121149-18-view-vendas-por-dia, 20261118-121308-18-view-vendas-por-dia | vendas-por-dia: mediana 290,7 → 11,7 ms; a API vira o limite (CPU 49,8%, banco 51,6%). Contrato mantido. |

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

### Detalhe do #9 (mediana das 3 execuções, antes → depois)

Rótulo `09-juncao-pedidos-do-cliente`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42). Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança, em um só commit: em `api/src/rotas.js`, a rota `GET /clientes/:id/pedidos` passa a usar uma consulta `pedidos LEFT JOIN itens_pedido LEFT JOIN produtos`, ordenada por `p.criado_em DESC, p.id DESC, i.id`, e o agrupamento por pedido é feito em JavaScript; a consulta do cliente (para o 404) fica como estava. Limite da verificação: para essa rota o contrato cobre 4 clientes (7, 42, 31337 e 99999, todos com 5 pedidos e nenhum pedido sem itens) e 1 caso de 404 (100001); não cobre `id` inválido nem pedido sem itens.

- `resultados/20261117-092959-09-juncao-pedidos-do-cliente`
- `resultados/20261117-093120-09-juncao-pedidos-do-cliente`
- `resultados/20261117-093241-09-juncao-pedidos-do-cliente`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 2604 → 2731 | 291,9 → 398,1 | 1721,2 → 910,6 | 2401,0 → 1454,3 |
| cliente | 681 → 696 | 82,1 → 196,4 | 299,6 → 536,4 | 442,0 → 694,6 |
| cliente-por-email | 377 → 395 | 380,4 → 535,5 | 598,0 → 822,3 | 697,9 → 993,8 |
| pedidos-do-cliente | 532 → 576 | 1200,7 → 393,9 | 2386,3 → 767,1 | 2871,2 → 938,6 |
| pedidos-por-status | 362 → 383 | 378,5 → 679,4 | 1014,2 → 1596,0 | 1738,7 → 2473,5 |
| busca-produtos | 396 → 421 | 194,0 → 317,0 | 402,0 → 614,2 | 579,7 → 720,4 |
| vendas-por-dia | 207 → 215 | 390,6 → 676,6 | 709,8 → 1200,6 | 1010,0 → 1490,8 |
| top-produtos | 44 → 44 | 70,7 → 199,1 | 289,5 → 599,1 | 364,6 → 755,5 |

Requisições por segundo: 42,86 → 45,21 (45,35, 44,08 e 45,21 nas 3 execuções). Erros: 0,0% nas 3 execuções.
A rota da hipótese, `pedidos-do-cliente`, melhorou nas 3 execuções em mediana (391,7, 393,9 e 395,0 ms), p95 (767,1, 849,6 e 729,1 ms) e p99 (938,6, 1012,8 e 916,1 ms), todas abaixo dos valores de antes (1200,7, 2386,3 e 2871,2 ms).
Nas outras 6 rotas, as 18 comparações (6 rotas × mediana, p95 e p99) pioraram, de +24,3% (p99 de `busca-produtos`) a +181,6% (mediana de `top-produtos`).

Leitura (inferência, não testada): a carga não tem pausa entre requisições e o banco já estava a cerca de 92% de CPU, com os dois contêineres em saturação. Com `pedidos-do-cliente` respondendo mais rápido, os usuários virtuais enviam mais requisições por segundo das outras rotas ao mesmo tempo; a vazão total subiu só 5,5%, então o trabalho a dividir cresceu mais que a capacidade e a espera dessas rotas aumentou. Um teste que a confirmaria ou refutaria: medir a mesma mudança com menos usuários virtuais, ou comparar o `pgss` antes e depois.

CPU por requisição (cálculo: CPU média ÷ req/s; 100% = 1 CPU): banco 21,3 → 20,4 ms (−4,5%); API 9,1 → 8,5 ms (−6,7%).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 91,4% → 92,1% | 99,6% → 99,8% | 473,4 → 461,9 | 495,8 → 492,5 |
| api | 38,9% → 38,3% | 50,4% → 50,2% | 40,6 → 41,4 | 49,4 → 59,3 |

### Detalhe do #10 (mediana das 3 execuções, antes → depois)

Rótulo `10-view-contagem-status`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança: `banco/08-view-contagem-status.sql` (`CREATE MATERIALIZED VIEW mv_pedidos_por_status` com a contagem de pedidos por status) e, em um commit `perf` separado, `api/src/rotas.js`, em que a rota `GET /pedidos` passa a ler `total` da view no lugar de `count(*)` sobre `pedidos`; a listagem com `LIMIT` e `OFFSET` não mudou. O banco foi recriado (`docker compose down -v`) antes das medições.

- `resultados/20261117-191003-10-view-contagem-status`
- `resultados/20261117-191124-10-view-contagem-status`
- `resultados/20261117-191245-10-view-contagem-status`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 2731 → 3357 | 398,1 → 312,0 | 910,6 → 796,5 | 1454,3 → 1138,6 |
| cliente | 696 → 871 | 196,4 → 188,6 | 536,4 → 491,8 | 694,6 → 619,1 |
| cliente-por-email | 395 → 485 | 535,5 → 486,8 | 822,3 → 786,7 | 993,8 → 899,8 |
| pedidos-do-cliente | 576 → 687 | 393,9 → 311,5 | 767,1 → 712,8 | 938,6 → 889,2 |
| pedidos-por-status | 383 → 484 | 679,4 → 404,3 | 1596,0 → 1203,3 | 2473,5 → 1669,5 |
| busca-produtos | 421 → 507 | 317,0 → 299,2 | 614,2 → 596,7 | 720,4 → 854,8 |
| vendas-por-dia | 215 → 267 | 676,6 → 593,2 | 1200,6 → 1025,7 | 1490,8 → 1250,7 |
| top-produtos | 44 → 56 | 199,1 → 150,6 | 599,1 → 482,7 | 755,5 → 674,8 |

Requisições por segundo: 45,21 → 55,57 (56,20, 54,50 e 55,57 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Na rota da hipótese, `pedidos-por-status`, as 3 execuções ficaram abaixo dos valores de antes (679,4, 1596,0 e 2473,5 ms) em mediana (404,3, 398,3 e 406,0 ms), p95 (1203,3, 1341,4 e 1139,4 ms) e p99 (1630,7, 1835,9 e 1669,5 ms).
Nas outras 6 rotas, 17 das 18 comparações melhoraram e 1 piorou: o p99 de `busca-produtos` (720,4 → 854,8 ms), que ficou acima do valor de antes nas 3 execuções (854,8, 894,9 e 786,9 ms); a causa não foi investigada.

CPU por requisição (cálculo: CPU média ÷ req/s; 100% = 1 CPU): banco 20,4 → 15,5 ms (−24,1%); API 8,5 → 7,9 ms (−6,7%).

Leitura (inferência, não testada): a rota fazia duas consultas, e a contagem recalculava a cada chamada um `count(*)` sobre `pedidos`; ao trocá-la por uma leitura de uma tabela de 4 linhas, o banco, que era o recurso saturado, ganhou folga, e a espera diminuiu em todas as rotas, o que a vazão total (+22,9%) acompanha. A listagem com `OFFSET` continua na rota.

Custo da view (`diagnostico/saidas/20261117-*-view-contagem-status/`): `pg_total_relation_size('mv_pedidos_por_status')` = 16 kB (16384 bytes). O tempo de criação não foi medido; como proxy, `REFRESH MATERIALIZED VIEW mv_pedidos_por_status` levou 70,583 ms, porque o `REFRESH` executa de novo a mesma consulta ([REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html)).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 92,1% → 85,9% | 99,8% → 99,7% | 461,9 → 464,7 | 492,5 → 500,5 |
| api | 38,3% → 43,9% | 50,2% → 52,0% | 41,4 → 36,9 | 59,3 → 58,4 |

A memória do banco chegou a 507,2 MiB de 512 MiB (99,1% do limite) na primeira execução; a causa não foi investigada.

Nota de método: a primeira tentativa do #10 (`resultados/20261117-100339-…`, `-100500-…` e `-100622-10-view-sem-uso-no-codigo`) não alterou `api/src/rotas.js`: o commit `perf` daquela época só continha o `banco/08`, então a rota continuou com `count(*)` e a view ficou sem uso. Isso foi descoberto depois, ao ver o `count(*)` no `pg_stat_statements` e o `git log` do arquivo, e o experimento foi refeito. Os números daquela tentativa (mesmo código, com uma view sem uso) servem como estimativa do ruído entre estados sem mudança de código, em uma comparação de 3 execuções: `pedidos-por-status` mediana −8,9%, p95 −4,8%, p99 −14,8%; total mediana −0,4%, p95 −1,8%, p99 −1,7%, req/s +2,6%; 7 das 18 comparações das outras 6 rotas pioraram (até +8,3%).

### Detalhe do #11 (mediana das 3 execuções, antes → depois)

Rótulo `11-agregacao-vendas-por-dia`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança, em um só commit (`perf`, na branch `exp-11-agregacao-vendas-por-dia-refeito`): em `api/src/rotas.js`, a consulta de `vendas-por-dia` passa a agrupar por dia no banco (`to_char(p.criado_em::date, 'YYYY-MM-DD')`, `count(DISTINCT p.id)`, `sum(i.quantidade)` e `sum(i.quantidade::bigint * i.preco_unitario_centavos)`), com o mesmo filtro da versão anterior e sem a coluna `observacoes`; a rota converte os resultados com `Number()` e deixa de agrupar em JavaScript. O banco foi recriado (`docker compose down -v`) antes das medições; o estado de partida é o #10 corrigido.

- `resultados/20261117-192011-11-agregacao-vendas-por-dia`
- `resultados/20261117-192131-11-agregacao-vendas-por-dia`
- `resultados/20261117-192252-11-agregacao-vendas-por-dia`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 3357 → 3281 | 312,0 → 300,6 | 796,5 → 792,1 | 1138,6 → 1494,8 |
| cliente | 871 → 844 | 188,6 → 192,5 | 491,8 → 301,2 | 619,1 → 400,3 |
| cliente-por-email | 485 → 475 | 486,8 → 596,9 | 786,7 → 796,4 | 899,8 → 896,9 |
| pedidos-do-cliente | 687 → 675 | 311,5 → 299,1 | 712,8 → 503,0 | 889,2 → 604,2 |
| pedidos-por-status | 484 → 470 | 404,3 → 396,2 | 1203,3 → 1597,4 | 1669,5 → 2226,5 |
| busca-produtos | 507 → 499 | 299,2 → 299,8 | 596,7 → 500,3 | 854,8 → 597,0 |
| vendas-por-dia | 267 → 262 | 593,2 → 605,5 | 1025,7 → 1032,9 | 1250,7 → 1397,7 |
| top-produtos | 56 → 56 | 150,6 → 106,1 | 482,7 → 301,2 | 674,8 → 396,8 |

Requisições por segundo: 55,57 → 54,26 (53,62, 54,26 e 54,68 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Na rota da hipótese, `vendas-por-dia`, a mediana das 3 execuções (604,4, 691,0 e 605,5 ms) ficou acima do valor de antes (593,2 ms); o p95 (1032,9, 995,6 e 1085,8 ms) e o p99 (1240,0, 1439,8 e 1397,7 ms) ficaram abaixo dos de antes (1025,7 e 1250,7 ms) em uma execução cada.
O p99 total (1494,8, 1497,4 e 1404,4 ms) ficou acima do de antes (1138,6 ms) nas 3 execuções.
Nas outras 6 rotas, 12 das 18 comparações melhoraram e 6 pioraram: mediana de `cliente` (+2,1%), mediana de `cliente-por-email` (+22,6%), p95 de `cliente-por-email` (+1,2%), mediana de `busca-produtos` (+0,2%), p95 de `pedidos-por-status` (+32,8%) e p99 de `pedidos-por-status` (+33,4%).

CPU por requisição (cálculo: CPU média ÷ req/s; 100% = 1 CPU): banco 15,5 → 18,5 ms (+19,7%); API 7,9 → 1,1 ms (−86,2%).

Leitura (inferência, não testada): a API passou a ficar quase ociosa (5,9% de 1 CPU) e o banco voltou a saturar (100,4%), com a agregação custando cerca de 3 ms a mais de CPU do banco por requisição, e a vazão não subiu. As rotas que esperavam pela API melhoraram na cauda (p95 de `cliente` −38,8%, de `top-produtos` −37,6%, de `pedidos-do-cliente` −29,4% e de `busca-produtos` −16,2%), enquanto as ligadas ao banco pioraram (`pedidos-por-status` e `cliente-por-email`). Ou seja, a premissa de que a API limitava as rotas explica a melhora das caudas das rotas leves, mas não a da própria `vendas-por-dia`, que depende do banco.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 85,9% → 100,4% | 99,7% → 100,0% | 464,7 → 466,7 | 500,5 → 496,8 |
| api | 43,9% → 5,9% | 52,0% → 8,1% | 36,9 → 26,7 | 58,4 → 27,2 |

Nota de método: a primeira tentativa do #11 (`resultados/20261117-181527-…`, `-181648-…` e `-181809-11-agregacao-vendas-por-dia-1a-tentativa`) foi medida sobre o estado do #9 com uma view sem uso no banco (o #10 ainda não alterava a rota; ver o detalhe do #10) e também não confirmou a H11: `vendas-por-dia` mediana 614,5 → 702,1 ms (+14,2%), p95 1075,5 → 1565,8 ms (+45,6%), p99 1276,7 → 2086,0 ms (+63,4%); CPU média da API 37,3% → 5,0% e do banco 95,6% → 97,0%. O `EXPLAIN (ANALYZE, BUFFERS)` da consulta agregada, sem carga (`diagnostico/saidas/20261117-183000-explain-agregacao-vendas-por-dia/`), levou 28,1 ms, com `Sort` por `(dia, id)` e `Gather Merge` com 2 workers antes do `GroupAggregate`; o plano antigo do mesmo período, registrado na Rodada 3, levava 7,6 ms (execuções diferentes, comparação aproximada).

### Detalhe do #12 (mediana das 3 execuções, antes → depois)

Rótulo `12-indice-email-clientes`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Mudança: novo arquivo `banco/09-indice-email-clientes.sql` com `CREATE INDEX idx_clientes_lower_email ON clientes (lower(email))` e `ANALYZE clientes`, aplicado ao recriar o banco (`docker compose down -v && up -d --build`); a consulta da rota (`WHERE lower(email) = lower($1)`) não mudou. O estado de partida é o #10 corrigido; o #11 não foi adotado.

- `resultados/20261117-192805-12-indice-email-clientes`
- `resultados/20261117-192926-12-indice-email-clientes`
- `resultados/20261117-193047-12-indice-email-clientes`

Custo (`diagnostico/saidas/20261117-183147-indice-email-clientes/`): índice de 4.907.008 bytes (4792 kB); `CREATE INDEX` em 422,075 ms e `ANALYZE clientes` em 210,318 ms (tempos medidos recriando o índice com o banco já populado). `EXPLAIN (ANALYZE, BUFFERS)` de uma busca por e-mail, sem carga: `Index Scan using idx_clientes_lower_email`, 0,080 ms e 4 buffers (1 em cache e 3 lidos); a Rodada 3 registrava `Seq Scan` com 99.999 linhas descartadas, 1156 buffers e 24,8 ms (outra execução e outro e-mail, comparação aproximada).

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 3357 → 3973 | 312,0 → 283,1 | 796,5 → 698,6 | 1138,6 → 994,6 |
| cliente | 871 → 1037 | 188,6 → 194,4 | 491,8 → 494,8 | 619,1 → 685,2 |
| cliente-por-email | 485 → 570 | 486,8 → 195,3 | 786,7 → 507,7 | 899,8 → 700,5 |
| pedidos-do-cliente | 687 → 815 | 311,5 → 299,6 | 712,8 → 695,9 | 889,2 → 920,2 |
| pedidos-por-status | 484 → 576 | 404,3 → 380,0 | 1203,3 → 903,3 | 1669,5 → 1227,9 |
| busca-produtos | 507 → 597 | 299,2 → 286,3 | 596,7 → 572,5 | 854,8 → 783,9 |
| vendas-por-dia | 267 → 310 | 593,2 → 540,0 | 1025,7 → 988,7 | 1250,7 → 1096,3 |
| top-produtos | 56 → 66 | 150,6 → 199,0 | 482,7 → 455,1 | 674,8 → 550,6 |

Requisições por segundo: 55,57 → 65,71 (64,76, 65,71 e 66,29 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Na rota da hipótese, `cliente-por-email`, as 3 execuções ficaram abaixo dos valores de antes (486,8, 786,7 e 899,8 ms) em mediana (195,3, 198,5 e 191,6 ms), p95 (498,7, 507,7 e 512,9 ms) e p99 (700,5, 633,4 e 797,7 ms).
Nas outras 6 rotas, 13 das 18 comparações melhoraram e 5 pioraram: mediana (+3,1%), p95 (+0,6%) e p99 (+10,7%) de `cliente`, p99 de `pedidos-do-cliente` (+3,5%) e mediana de `top-produtos` (+32,1%, com 56 a 66 requisições por execução).

CPU por requisição (cálculo: CPU média ÷ req/s; 100% = 1 CPU): banco 15,5 → 9,8 ms (−36,9%); API 7,9 → 7,4 ms (−6,3%).

Leitura (inferência, não testada): a consulta por e-mail era das mais pesadas para o banco e, ao ser trocada por uma leitura de poucos blocos, o banco ganhou folga (CPU média de 85,9% para 64,1%) e a vazão subiu 18,2%. A API passou a ser o recurso mais exigido: 48,6% de 1 CPU é cerca de 97% da quota de 0,5 CPU. Isso muda o quadro em que o #11 foi medido (banco saturado, API com folga) e justifica repetir o #11 sobre este estado.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 85,9% → 64,1% | 99,7% → 99,8% | 464,7 → 470,7 | 500,5 → 501,5 |
| api | 43,9% → 48,6% | 52,0% → 52,9% | 36,9 → 36,9 | 58,4 → 51,7 |

A memória máxima do banco segue perto do limite de 512 MiB (506,8 MiB na segunda execução); a causa não foi investigada.

Nota de método: a primeira tentativa do #12 (`resultados/20261117-183203-…`, `-183324-…` e `-183444-12-indice-email-clientes-1a-tentativa`) foi medida sobre o estado do #9 com uma view sem uso no banco e deu resultado parecido: `cliente-por-email` mediana 579,7 → 195,4 ms (−66,3%), p95 857,0 → 491,0 ms (−42,7%), p99 964,4 → 680,8 ms (−29,4%), req/s 46,38 → 60,33 (+30,1%), CPU por requisição do banco 20,6 → 14,5 ms. O ganho de vazão foi maior lá porque o banco ainda não tinha a contagem de `pedidos-por-status` em view.

### Detalhe do #13 (mediana das 3 execuções, antes → depois)

Rótulo `13-vendas-sem-observacoes`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `62a5493`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções.

- `resultados/20261118-102920-13-vendas-sem-observacoes`
- `resultados/20261118-103041-13-vendas-sem-observacoes`
- `resultados/20261118-103201-13-vendas-sem-observacoes`

Antes: as 3 execuções do #12 refeito (`resultados/20261117-192805-12-indice-email-clientes`, `-192926-` e `-193047-`).

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 3973 → 5286 | 283,1 → 195,3 | 698,6 → 521,1 | 994,6 → 974,7 |
| cliente | 1037 → 1366 | 194,4 → 115,4 | 494,8 → 326,0 | 685,2 → 425,3 |
| cliente-por-email | 570 → 779 | 195,3 → 114,5 | 507,7 → 330,4 | 700,5 → 448,2 |
| pedidos-do-cliente | 815 → 1102 | 299,6 → 220,3 | 695,9 → 497,8 | 920,2 → 605,9 |
| pedidos-por-status | 576 → 757 | 380,0 → 285,3 | 903,3 → 1129,1 | 1227,9 → 1640,5 |
| busca-produtos | 597 → 781 | 286,3 → 218,9 | 572,5 → 441,8 | 783,9 → 551,3 |
| vendas-por-dia | 310 → 407 | 540,0 → 386,8 | 988,7 → 737,8 | 1096,3 → 974,0 |
| top-produtos | 66 → 92 | 199,0 → 127,9 | 455,1 → 322,8 | 550,6 → 409,3 |

Requisições por segundo: 65,71 → 87,66. Erros: 0,0% nas 3 execuções.

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 64,1 → 93,0% | 99,8 → 99,9% | 470,7 → 461,6 | 501,5 → 492,7 |
| api | 48,6 → 43,1% | 52,9 → 53,0% | 36,9 → 32,0 | 51,7 → 35,4 |

CPU média da API por req/s (pontos percentuais por requisição por segundo): 0,74 → 0,49.
O banco ficou em 93,0% de CPU média e 492,7 MiB de memória máxima (limite de 512 MiB); `pedidos-por-status` recebeu 757 requisições (antes 576) com p95 e p99 maiores, o que é compatível com o banco saturado (inferência, não testada).

### Detalhe do #14 (mediana das 3 execuções, antes → depois)

Rótulo `14-listagem-juncao-adiada`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `ee7980d`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções.

- `resultados/20261118-104326-14-listagem-juncao-adiada`
- `resultados/20261118-104445-14-listagem-juncao-adiada`
- `resultados/20261118-104605-14-listagem-juncao-adiada`

Antes: as 3 execuções do #13 (`resultados/*-13-vendas-sem-observacoes`). Planos do depois: `diagnostico/saidas/20261118-104954-explain-listagem-juncao-adiada/planos.txt`.

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 5286 → 6458 | 195,3 → 176,1 | 521,1 → 406,9 | 974,7 → 510,9 |
| cliente | 1366 → 1632 | 115,4 → 111,5 | 326,0 → 315,3 | 425,3 → 408,4 |
| cliente-por-email | 779 → 961 | 114,5 → 112,6 | 330,4 → 362,0 | 448,2 → 443,1 |
| pedidos-do-cliente | 1102 → 1374 | 220,3 → 188,2 | 497,8 → 412,6 | 605,9 → 512,5 |
| pedidos-por-status | 757 → 934 | 285,3 → 200,0 | 1129,1 → 420,7 | 1640,5 → 520,7 |
| busca-produtos | 781 → 952 | 218,9 → 210,4 | 441,8 → 414,5 | 551,3 → 516,4 |
| vendas-por-dia | 407 → 501 | 386,8 → 270,9 | 737,8 → 491,6 | 974,0 → 616,5 |
| top-produtos | 92 → 111 | 127,9 → 113,9 | 322,8 → 308,1 | 409,3 → 401,8 |

Requisições por segundo: 87,66 → 107,34. Erros: 0,0% nas 3 execuções.

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 93,0 → 65,2% | 99,9 → 83,2% | 461,6 → 476,5 | 492,7 → 486,5 |
| api | 43,1 → 49,5% | 53,0 → 51,7% | 32,0 → 28,8 | 35,4 → 31,7 |

Blocos lidos (acertos mais leituras) pela listagem, antes → depois: página 500 10.052 → 139; página 6000 120.594 → 681.
O p95 e o p99 de `pedidos-por-status`, que haviam subido no #13 com o banco em 93,0% de CPU média, foram de 1129,1 para 420,7 ms e de 1640,5 para 520,7 ms com o banco em 65,2% (a ligação com a saturação do banco é inferência, não testada).

### Detalhe do #15 (mediana das 3 execuções, antes → depois)

O #15 parte do estado após o #14.

- req/s: 107,3 → 131,0 (+22.0%)
- total: mediana 176,1 → 103,2 ms, p95 406,9 → 399,9 ms, p99 510,9 → 509,9 ms
- vendas-por-dia: mediana 270,9 → 404,5 ms, p95 491,6 → 598,7 ms
- busca-produtos: mediana 210,4 → 202,0 ms, p95 414,5 → 304,7 ms
- cliente: mediana 111,5 → 95,9 ms
- CPU média: API 49,5% → 11,2%, banco 65,2% → 98,8%
- Memória máxima do banco: 504,5 → 497,1 MiB (limite 512 MiB; máximo das 3 execuções)
- Inferência (CPU média do banco / req/s): custo de CPU do banco por requisição 6,1 → 7,5 ms.
- A agregação passou a ser feita pelo banco. A CPU da API foi de 49,5% para 11,2% e o banco passou a ser o limite (CPU ~98,8%).
- A coluna cpu_max da API ficou abaixo da média nesta rodada e não foi usada.
- Contrato mantido nas 3 execuções.

### Detalhe do #16 (mediana das 3 execuções, antes → depois)

O #16 parte do estado após o #15.

- req/s: 131,0 → 169,6 (+29.5%)
- total: mediana 103,2 → 97,9 ms, p95 399,9 → 392,6 ms, p99 509,9 → 498,9 ms
- vendas-por-dia: mediana 404,5 → 398,3 ms, p95 598,7 → 510,3 ms
- busca-produtos: mediana 202,0 → 96,8 ms, p95 304,7 → 193,0 ms
- cliente: mediana 95,9 → 92,4 ms
- CPU média: API 11,2% → 14,7%, banco 98,8% → 100,6%
- Memória máxima do banco: 497,1 → 498,2 MiB (limite 512 MiB; máximo das 3 execuções)
- Inferência (CPU média do banco / req/s): custo de CPU do banco por requisição 7,5 → 5,9 ms.
- Planos (EXPLAIN dos termos do contrato, em diagnostico/saidas/*-explain-busca-trigram): Bitmap Index Scan em idx_produtos_nome_trgm em todos, 0,2–3,5 ms. O índice ainda devolve 1000–2000 linhas por termo e o ORDER BY ... LIMIT 20 as ordena. O planejador estimou 2 linhas para "sem fio" e vieram 2000, mas manteve o índice.
- O tamanho do ganho não foi decomposto por rota.
- A coluna cpu_max da API ficou inconsistente com a média e não foi usada.
- Contrato mantido nas 3 execuções.

### Detalhe do #17 (mediana das 3 execuções, antes → depois)

O #17 parte do estado após o #16.

- req/s: 169,6 → 270,9 (+59.8%)
- total: mediana 97,9 → 83,9 ms, p95 392,6 → 215,1 ms, p99 498,9 → 392,9 ms
- vendas-por-dia: mediana 398,3 → 290,7 ms, p95 510,3 → 401,9 ms
- busca-produtos: mediana 96,8 → 77,1 ms, p95 193,0 → 99,2 ms
- cliente: mediana 92,4 → 10,8 ms
- CPU média: API 14,7% → 21,2%, banco 100,6% → 99,5%
- Memória máxima do banco: 498,2 → 510,3 MiB (limite 512 MiB; máximo das 3 execuções)
- Inferência (CPU média do banco / req/s): custo de CPU do banco por requisição 5,9 → 3,7 ms.
- O EXPLAIN isolado de vendas (banco ocioso, uma amostra por configuração) mostrou 37,8 ms de execução + 5,05 ms de planejamento com 2 workers e 32,4 ms + 0,88 ms sem workers. Sob carga o ganho foi muito maior. Explicação provável (inferência; CPU por processo não medida): os workers somavam CPU relevante num banco de 1 CPU, e as rotas leves esperavam atrás deles (a mediana de cliente caiu para ~10,8 ms).
- Plano: com a configuração aplicada, o EXPLAIN de vendas não mostra Gather (diagnostico/saidas/*-explain-vendas-sem-paralelismo).
- Contrato mantido nas 3 execuções.

### Detalhe do #18 (mediana das 3 execuções, antes → depois)

O #18 parte do estado após o #17.

- req/s: 270,9 → 686,5 (+153.4%)
- total: mediana 83,9 → 14,9 ms, p95 215,1 → 71,7 ms, p99 392,9 → 80,8 ms
- vendas-por-dia: mediana 290,7 → 11,7 ms, p95 401,9 → 66,8 ms
- busca-produtos: mediana 77,1 → 15,3 ms, p95 99,2 → 71,6 ms
- cliente: mediana 10,8 → 11,5 ms
- CPU média: API 21,2% → 49,8%, banco 99,5% → 51,6%
- Memória máxima do banco: 510,3 → 468,0 MiB (limite 512 MiB; máximo das 3 execuções)
- Inferência (CPU média do banco / req/s): custo de CPU do banco por requisição 3,7 → 0,8 ms.
- req/s das 3 execuções: 753,1, 673,5, 686,5 (faixa 673,5–753,1).
- A rota passou a ler `mv_vendas_por_dia` (731 linhas, uma por dia; mesmo JOIN interno e mesmo filtro `status <> 'cancelado'` da consulta anterior). A view foi comparada com a agregação direta em todos os dias (EXCEPT nos dois sentidos: 0 linhas).
- Plano da rota na view: Bitmap Index Scan em idx_mv_vendas_por_dia_dia, execução 0,152 ms (diagnostico/saidas/*-explain-view-vendas).
- A API passou a ser o limite: CPU média 49,8% (cota de 0,5 CPU) contra 51,6% do banco.
- Custo: a rota reflete o último REFRESH da view (aqui, a criação do banco); a API só tem rotas GET.
- A dispersão entre as execuções foi maior que nos experimentos anteriores; a causa não foi investigada.
- Contrato mantido nas 3 execuções.

## Hipóteses (escritas antes de aplicar)

**H1 (#1).** Criar um índice em `itens_pedido(pedido_id)` deve reduzir o p95 da rota `pedidos-do-cliente`, porque, segundo a Rodada 1, cada uma das 5 consultas por requisição hoje lê a tabela inteira (varredura sequencial) e descarta 499999 linhas para devolver 2.

**H2 (#2).** Criar um índice em `pedidos(cliente_id)` deve reduzir o p95 da rota `pedidos-do-cliente` sobre o estado após o #1, porque, segundo a Rodada 1, a consulta hoje lê a tabela inteira (varredura sequencial) e descarta 166665 linhas por processo para devolver 5.

**H3 (#3).** Trocar a conexão por consulta (`db.js`) por um `pg.Pool` deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, porque criar uma conexão leva tempo e hoje cada consulta cria a sua.

**H4 (#4).** Colocar o PgBouncer entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3: o custo vem de abrir conexões ao banco, que está saturado, e o PgBouncer é um pooler de conexões que reaproveita as conexões ao servidor. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

**H5 (#5).** Colocar o Pgpool-II entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3, porque o Pgpool-II lista pool de conexões entre as suas funções. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

**H6 (#6).** Criar um índice em `pedidos(status, criado_em DESC, id DESC)` deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #3, porque, segundo a Rodada 2, `pedidos-por-status` é 45,6% da CPU do banco no mix do k6 e a lista lê `pedidos` inteira e, na página 1000, ordena ~300.000 linhas em arquivo temporário no disco, e um índice na mesma ordem do `ORDER BY` entrega as linhas já ordenadas e dispensa essa ordenação ([Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html)), o que Winand chama de *pipelined order by* ([Use The Index, Luke](https://use-the-index-luke.com/sql/sorting-grouping/indexed-order-by)).

**H7 (#7).** Criar um índice em `pedidos(criado_em)` e trocar o filtro de `vendas-por-dia`, de `criado_em::date BETWEEN $1 AND $2` para o intervalo `criado_em >= $1::date AND criado_em < $2::date + 1`, deve reduzir a mediana, o p95 e o p99 da rota `vendas-por-dia` sobre o estado após o #6, porque, segundo a Rodada 2, a rota gasta 185,0 ms de CPU do banco por requisição (11,9% da CPU do banco no mix do k6) e o plano lê `pedidos` inteira (~500.000 linhas, descartando ~495.700) para devolver ~4.300, já que o filtro com conversão sobre a coluna impede o uso de um índice sobre ela, e uma condição de intervalo permite usá-lo ([Winand](https://use-the-index-luke.com/sql/where-clause/obfuscation/dates)). Como `criado_em` é `timestamp without time zone`, a reescrita deve devolver os mesmos pedidos; isso é conferido por consulta antes de medir.

**H8 (#8).** Criar a view materializada `mv_top_produtos`, com a soma de `quantidade` e de `quantidade * preco_unitario_centavos` por produto sobre os pedidos não cancelados, e um índice nela em `(receita_centavos DESC, id)`, e trocar a consulta de `top-produtos` para ler a view, deve reduzir a mediana, o p95 e o p99 da rota `top-produtos` sobre o estado após o #7, porque, segundo a Rodada 2, a rota gasta 1056,2 ms de CPU do banco por requisição (17,0% da CPU do banco no mix do k6, com 2 de 100 pontos de peso) e o plano lê e junta cerca de 1,35 milhão de linhas a cada requisição para calcular as somas de 19.206 produtos e devolver 10 (duração real do plano: 1287,6 e 1329,5 ms), e uma view materializada guarda esse resultado já calculado, de modo que ler dela costuma ser bem mais rápido que consultar as tabelas de origem ([Docs 41.3](https://www.postgresql.org/docs/16/rules-materializedviews.html)); o índice na mesma ordem do `ORDER BY` entrega as linhas já ordenadas ([Docs 11.4](https://www.postgresql.org/docs/16/indexes-ordering.html)). A view só reflete os dados até o último `REFRESH` ([REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html)); como nenhuma rota da API altera `itens_pedido` nem `pedidos`, a view criada depois da carga não fica defasada. O custo (tamanho da view e tempo de criação) entra na comparação. A saída deve ficar idêntica; isso é conferido por `comparar` antes de medir.

**H9 (#9).** Trocar, na rota `pedidos-do-cliente`, as consultas de itens (uma por pedido) e de produto (uma por item) por uma única junção `pedidos LEFT JOIN itens_pedido LEFT JOIN produtos`, com o agrupamento por pedido feito em JavaScript, deve reduzir a mediana, o p95 e o p99 da rota `pedidos-do-cliente` sobre o estado após o #8, porque, segundo a Rodada 1, uma requisição dessa rota dispara 17 consultas em sequência (1 de cliente, 1 de pedidos, 5 de itens e 10 de produtos) e, segundo a Rodada 3, essas consultas são baratas no banco e a rota é cara fora delas: sozinha, as 17 consultas somam 0,2 a 0,3 ms no banco e a requisição leva 9,2 ms; no `pg_stat_statements` sob carga as três consultas por pedido somam cerca de 0,6% do tempo do banco; a CPU por requisição é de 3,42 a 3,62 ms no banco e de 10,24 a 11,41 ms na API; e, sob carga, a mediana da rota é de 1200,7 ms. Isso é compatível com um custo que vem do número de idas e voltas ao banco, e não do trabalho de cada consulta. Winand descreve esse padrão como o problema N+1 e aponta a junção no banco como correção, porque cada comando extra é uma ida e volta ao banco e o número de idas e voltas pesa mais no tempo de resposta do que o volume de dados ([Winand](https://use-the-index-luke.com/sql/join/nested-loops-join-n1-problem)). Ficam 2 consultas por requisição (a do cliente e a junção). A resposta deve ficar idêntica: pedidos por `criado_em DESC, id DESC`, itens por `id`, e pedido sem itens com `itens: []` e `total_centavos: 0`; isso é conferido por `comparar` antes de medir.

**H10 (#10).** Criar a view materializada `mv_pedidos_por_status`, com `status` e a contagem de pedidos por status, e trocar o `SELECT count(*) FROM pedidos WHERE status = $1` de `pedidos-por-status` pela leitura dela deve reduzir a mediana, o p95 e o p99 da rota `pedidos-por-status` sobre o estado após o #9, porque, segundo a Rodada 3, o `count(*)` é 15,2% do tempo do banco (95,1 ms por chamada sob carga) e, para `pago`, o plano percorre 300.000 entradas de índice em 2 processos extras (19,4 ms, 1484 buffers), e a CPU do banco por requisição é de 43,45 a 51,34 ms com `pago` contra 13,47 a 15,62 ms com `entregue` na página 500. No PostgreSQL, `count(*)` precisa verificar a visibilidade das linhas ([Wiki: Slow Counting](https://wiki.postgresql.org/wiki/Slow_Counting)), enquanto uma view materializada guarda o resultado já calculado ([Docs 41.3](https://www.postgresql.org/docs/16/rules-materializedviews.html)). A view só reflete os dados até o último `REFRESH` ([REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-refreshmaterializedview.html)); como nenhuma rota da API altera `pedidos`, a view criada depois da carga não fica defasada. Os quatro status válidos têm pedidos (300.000, 125.000, 50.000 e 25.000), então todos aparecem na view. O custo (tamanho da view e tempo de criação) entra na comparação. A saída deve ficar idêntica; isso é conferido por `comparar` antes de medir.

**H11 (#11).** Trocar a consulta de `vendas-por-dia`, que devolve uma linha por item e agrupa por dia em JavaScript, por uma consulta que agrupa por dia no banco (`GROUP BY` do dia de `criado_em`, `count(DISTINCT p.id)`, `sum(i.quantidade)` e `sum(i.quantidade * i.preco_unitario_centavos)`) e não traz a coluna `observacoes`, deve reduzir a mediana, o p95 e o p99 da rota `vendas-por-dia` sobre o estado após o #10, porque, segundo a Rodada 3, a rota gasta 78,1 a 84,1 ms de CPU da API por requisição (contra 38,2 a 40,6 ms do banco), o plano devolve 12.951 linhas de 296 bytes para a API (a consulta leva 7,6 ms no banco desde o #7) e a rota responde por cerca de 60% da CPU da API no mix (estimativa: peso 8 × 78,1 a 84,1 ms, em ~10,7 ms por requisição do mix), enquanto a resposta final tem só uma linha por dia (até 7). A coluna `observacoes` só aparece no `SELECT` dessa rota (`api/src/rotas.js`): não entra no cálculo nem na resposta, e o `base.json` do contrato não a contém. Os resultados de `sum` e `count` têm tipo `bigint` ou `numeric` no PostgreSQL ([Docs 9.21](https://www.postgresql.org/docs/16/functions-aggregate.html)), que o driver entrega como texto; a rota converte esses campos com `Number()` para manter os mesmos números, e o produto `quantidade * preço` é calculado em `bigint` para não estourar o `integer`. A resposta deve ficar idêntica (dias em ordem crescente, só dias com pedidos não cancelados); isso é conferido por `comparar` antes de medir.

**H11, retestada (#11).** A primeira medição desta ideia, feita sobre o estado do #9 com uma view sem uso no banco, não confirmou a H11: a CPU do banco estava perto de 96% e a agregação passou para ele. A ideia é refeita sobre o estado após o #10 corrigido, em que a CPU média do banco é 85,9% (antes 92,1%) e a da API é 43,9% de 1 CPU, cerca de 88% da quota de 0,5 CPU (antes 38,3%, cerca de 77%). Agrupar `vendas-por-dia` no banco deve reduzir a mediana, o p95 e o p99 da rota, porque, se a API passou a ser o recurso mais limitante e o banco tem alguma folga, trocar o laço em JavaScript sobre 12.951 linhas (CPU da API de 78 a 84 ms por requisição na Rodada 3) por uma agregação no banco tira trabalho do recurso mais saturado. Se o banco seguir sendo o limite, o resultado deve repetir a piora da primeira tentativa.

**H12 (#12).** Criar um índice em `clientes (lower(email))` deve reduzir a mediana, o p95 e o p99 da rota `cliente-por-email` sobre o estado após o #10, porque, segundo a Rodada 3, o plano faz `Seq Scan` em `clientes` (99.999 linhas descartadas para devolver 1, 1156 buffers, 24,8 ms), a consulta é 39,1% do tempo do banco sob carga (235,0 ms por chamada) e a CPU do banco é de 25,36 a 27,88 ms por requisição (cerca de 90% do custo da rota). Uma consulta que filtra pela mesma expressão, como `WHERE lower(col) = 'valor'`, pode usar um índice sobre a expressão e roda como uma busca por igualdade simples; o custo é calcular a expressão a cada inserção e atualização ([Docs 11.7](https://www.postgresql.org/docs/16/indexes-expressional.html)); como nenhuma rota da API altera `clientes`, esse custo não aparece na carga. O custo (tamanho do índice e tempo de criação) entra na comparação. A saída deve ficar idêntica; isso é conferido por `comparar` antes de medir.

**H13 (#13).** Tirar `p.observacoes` do SELECT de `vendas-por-dia` deve aumentar as requisições por segundo gerais e reduzir a mediana e o p95 da rota, sobre o estado após o #12, porque, segundo a Rodada 4 (`diagnostico/saidas/20261118-094652-coleta/`), a API está no limite da cota de 0,5 CPU (715 de 782 períodos pausados), `vendas-por-dia` gasta 81,6 ms de CPU de API por chamada e responde por ~85% da CPU da API, e cada chamada traz ~12,9 mil linhas em que `observacoes` (277 bytes em média, ~3,6 MB por chamada) não é usada pelo JS. Se a CPU de API por chamada (`diagnostico/coleta/05-cpu-por-rota.sh`) não cair de forma mensurável, ou se as req/s ficarem dentro da variação entre execuções idênticas, o custo está na conversão e no laço por linha, não no volume de bytes, e o caminho passa a ser o #14. Sem serviço novo.

**H14 (#14).** Buscar os 20 `id`s da página numa subconsulta que lê só o índice `(status, criado_em DESC, id DESC)` e trazer as 4 colunas que a rota devolve apenas para esses 20, com `VACUUM (ANALYZE) pedidos` num novo `banco/10-vacuum-pedidos.sql`, deve reduzir os blocos lidos por chamada de `/pedidos` (hoje ~9.900, segundo a coleta da Rodada 4) para dezenas, reduzir a CPU do banco e reduzir o p95 e o p99 de `pedidos-por-status`, sobre o estado após o #13, porque, segundo a Rodada 4, cada linha pulada pelo OFFSET custa um acesso ao heap (página 500: 10.003 buffers para 20 linhas) e `relallvisible` é 0, o que impede o Index Only Scan. Depois do #13 o banco passou a ser o limite (CPU média de 93,0%, `resultados/*-13-vendas-sem-observacoes`) e `pedidos-por-status` piorou no p95 e no p99 (903,3 → 1129,1 ms e 1227,9 → 1640,5 ms), então reduzir o custo da listagem ataca o recurso saturado. A documentação do PostgreSQL diz que a consulta só usa Index Only Scan se referenciar apenas colunas do índice e que, sem o bit do mapa de visibilidade, a página do heap precisa ser consultada. Se o plano novo não for Index Only Scan, ou mostrar muitos `Heap Fetches`, a hipótese cai. A ordem `criado_em DESC, id DESC` é reaplicada fora da subconsulta. Sem serviço novo.

**H15 (#15).** Premissa (medida no #14): a API está no limite da cota (CPU médio 48,9–49,6% de 50%) e o banco está em ~65–67%. Na rodada 4, a `vendas-por-dia` custava 81,6 ms de CPU da API por chamada, porque o Node recebe ~12,9 mil linhas por chamada e as agrega em JS. Hipótese: fazer a agregação no SQL (`GROUP BY` por dia, `COUNT(DISTINCT p.id)`, `SUM(quantidade)`, `SUM(quantidade * preco_unitario_centavos)`) reduz as linhas trafegadas para o número de dias do intervalo e tira da API o parse e o laço. Previsão: a CPU da API por requisição cai e a vazão aumenta; o banco volta a ser o limite. Refuta se: o req/s subir menos que o ruído observado (até ~15% numa comparação A/A anterior), ou se o contrato mudar. Cuidados: o dia deve sair igual ao do JS atual (`toISOString().slice(0,10)`, ou seja, data em UTC); `COUNT`/`SUM` chegam como string no `pg`, então converter para número; manter `ORDER BY` por dia.

**H16 (#16).** Premissa (medida no #15): o banco é o limite (CPU média ~98%, API ~11%), e a `busca-produtos` é a rota leve mais lenta (mediana ~202 ms contra ~96–108 ms das outras). Na rodada 4, a busca fazia Seq Scan nas 20 mil linhas de `produtos`, com 9,9 dos 10,3 ms de execução gastos no `ILIKE` (colação en_US.utf8), e respondia por 24,5% do tempo de consultas no `pg_stat_statements`. Hipótese: um índice GIN com `gin_trgm_ops` em `produtos.nome` (extensão `pg_trgm`, na migração `banco/11-...sql`) permite ao planejador usar Bitmap Index Scan para `nome ILIKE '%' || $1 || '%'` sem mudar a consulta nem o resultado (termos têm 3 caracteres ou mais, o mínimo que o trigram precisa). Previsão (a confirmar com `EXPLAIN`): o custo de CPU do banco por busca cai e, como a busca é uma parte relevante das requisições, o req/s sobe. Refuta se: o `EXPLAIN` dos termos do contrato (`cadeira`, `lumin`, `ERGO`, `sem fio`) mostrar Seq Scan; se o req/s subir menos que o ruído observado (até ~15% numa comparação A/A anterior); ou se o contrato mudar. Risco: termos muito frequentes podem fazer o planejador preferir o Seq Scan mesmo com o índice, e o `ORDER BY nome, id LIMIT 20` ainda ordena os resultados do bitmap.

**H17 (#17).** Premissa (medida): o banco está no limite de CPU (~100% de 1 CPU no #16) e a única consulta de rota com plano paralelo é a de `vendas-por-dia` (`EXPLAIN` das consultas das demais rotas sem `Gather` nem `Parallel`). No `EXPLAIN (ANALYZE, BUFFERS)` dessa consulta, com banco ocioso e cache aquecido, o plano com 2 workers (Gather Merge) tem custo estimado de 25.849 e levou 37,8 ms de execução + 5,05 ms de planejamento; o plano serial tem custo estimado de 39.424 e levou 32,4 ms + 0,88 ms. Ou seja, o planejador estimou o plano paralelo como mais barato e ele foi mais lento (uma amostra por configuração). Mecanismo, segundo a documentação do PostgreSQL 16: com `max_parallel_workers_per_gather = 0` nenhum plano paralelo é gerado ([When Can Parallel Query Be Used?](https://www.postgresql.org/docs/16/when-can-parallel-query-be-used.html)); o líder também lê todas as tuplas produzidas pelos workers e, com muitas tuplas, passa a maior parte do tempo coletando resultados ([How Parallel Query Works](https://access.crunchydata.com/documentation/postgresql16/16.6/how-parallel-query-works.html)); o planejador estima o custo de iniciar workers (`parallel_setup_cost`, padrão 1000) e de passar cada linha a outro processo (`parallel_tuple_cost`, padrão 0,1) ([Planner Cost Constants](https://www.postgresql.org/docs/16/runtime-config-query.html)). A rota devolve ~12,9 mil linhas ao líder para produzir poucos grupos. Hipótese (não vem da documentação): com 1 CPU e outras rotas disputando o mesmo núcleo, o custo de iniciar e coordenar os workers não traz ganho e consome CPU. Mudança: `ALTER DATABASE loja SET max_parallel_workers_per_gather = 0` em `banco/12-sem-paralelismo.sql`. Previsão: o `EXPLAIN` da consulta passa a mostrar plano serial e o custo de CPU do banco por requisição cai, o que aumenta o req/s. Refuta se: o req/s subir menos que o ruído; o `EXPLAIN` ainda mostrar `Gather`; o contrato mudar; ou outra rota piorar. Risco: o `EXPLAIN` das demais rotas foi feito com valores literais, e a amostragem de `pg_stat_activity` durante a carga ainda não confirmou que só essa consulta usa workers.

**H18 (#18).** Premissa (medida): o banco segue no limite de CPU (~99,5% de 1 CPU no #17) e `vendas-por-dia` é a rota mais lenta: 1.323 chamadas em 60 s (~8% das requisições) com mediana ~290 ms. A consulta lê ~12,9 mil linhas por chamada e executa em ~20 ms de banco (serial, ocioso, cache aquecido). Os dados não mudam durante a carga: as rotas da API são só GET. Mecanismo, segundo a documentação do PostgreSQL 16: uma view materializada guarda o resultado da consulta de forma semelhante a uma tabela e as consultas leem esse dado direto; o dado reflete o último `REFRESH` e só é atualizado por ele ([Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html); [CREATE MATERIALIZED VIEW](https://www.postgresql.org/docs/16/sql-creatematerializedview.html)). Mudança: criar `mv_vendas_por_dia` (uma linha por dia, com pedidos, itens e receita, mesmo `JOIN` interno e mesmo filtro `status <> 'cancelado'` da consulta atual) em `banco/13-view-vendas-por-dia.sql`, com índice único em `dia`, e fazer a rota ler as linhas do intervalo `[inicio, fim]` da view. Previsão: o custo de CPU do banco por chamada de vendas cai muito, a mediana da rota cai e o req/s sobe. Custo: a rota passa a refletir o último `REFRESH` da view (aqui, a criação do banco); numa aplicação real com escrita seria preciso definir quando atualizar. Refuta se: o req/s subir menos que o ruído observado (até ~15% numa comparação A/A anterior); o contrato mudar (riscos: dias nas bordas do intervalo, pedidos sem item, pedidos cancelados, tipos numéricos); ou o plano da rota não usar a view.


Os #3, #4 e #5 são testados separadamente, cada um sobre o estado após o #2 e sem os outros dois aplicados.
O #6 parte do estado após o #3 (o `pg.Pool`, adotado entre os três por melhorar as métricas sem contêiner novo).
O #7 parte do estado após o #6.
O #8 parte do estado após o #7.
O #9 parte do estado após o #8.
O #10 parte do estado após o #9.
O #11 parte do estado após o #10.
O #12 parte do estado após o #10 (o #11 não foi adotado).
O #13 parte do estado após o #12.
O #14 parte do estado após o #13.