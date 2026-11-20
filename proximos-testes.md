# Próximos testes

Ideias pesquisadas que **não foram aplicadas** neste trabalho. As duas têm o status "Pesquisada, teste futuro". Nenhuma tem resultado medido, e nenhum número abaixo foi estimado por mim: o que aparece vem de uma medição já registrada em `experimentos.md` ou em `diagnostico/saidas/`, ou de uma fonte citada.

## 1. Paginação por chave (seek method) em `GET /pedidos`

**Status:** Pesquisada, teste futuro.

**De onde veio.**
- Markus Winand, *Use The Index, Luke*, ["Paginação sem OFFSET"](https://use-the-index-luke.com/no-offset) e ["Fetch next page"](https://use-the-index-luke.com/sql/partial-results/fetch-next-page). Guia técnico de um especialista, não documentação do fabricante.
- Documentação do PostgreSQL 16, ["Row Constructor Comparison"](https://www.postgresql.org/docs/16/functions-comparisons.html). Fonte primária.

**O que as fontes dizem.** Com `OFFSET`, o banco lê e descarta as linhas anteriores. No seek method a consulta filtra pela chave da última linha vista, com ordem determinística (uma coluna única no `ORDER BY` e no índice) e uma comparação de linha como `(criado_em, id) < (?, ?)`. Segundo o guia, o PostgreSQL aceita essa comparação e consegue usá-la no índice, e a documentação confirma que ela é lexicográfica. O limite apontado pelo guia é que não se pode saltar direto para a página N.

**Premissa medida aqui.** Depois do #14 a listagem usa um Index Only Scan em `idx_pedidos_status_criado_em_id`, mas ele ainda lê `OFFSET + 20` linhas: 10.000 linhas para `OFFSET 9980` e 300.000 para `OFFSET 299980` (`EXPLAIN ANALYZE`). Na página 15000 a CPU do banco por requisição foi de 21,75 ms (`05-cpu-por-rota.sh`, só para comparação relativa). O teste de carga pede `pagina` de 1 a 1000, ou seja, `OFFSET` de até 19.980, então quase não exercita páginas fundas.

**Quando faria sentido.** Se o uso real fosse sequencial, com o cliente avançando da página 1 em diante, como na rolagem infinita que a fonte cita como o caso em que o método funciona bem. Nesse padrão, cada página parte da chave da última linha da anterior, e o custo de uma página deixa de crescer com o número dela, em vez de reler todas as linhas anteriores.

**O que eu acredito que ganharia.** No uso sequencial, páginas fundas deixariam de custar proporcionalmente ao `OFFSET`. O teste de carga do desafio não reproduz esse padrão: ele sorteia `pagina` de 1 a 1000, sem relação entre uma requisição e a seguinte. Por isso não espero, nessa carga, uma diferença que se separe do ruído entre execuções, e por isso não apliquei.

**Conflito com o contrato.** A rota recebe `pagina=N` e precisa devolver exatamente o mesmo de hoje. O seek method precisa da chave da última linha da página anterior e, segundo a fonte, não permite ir direto à página N. Uma versão compatível precisaria de uma estrutura auxiliar com a chave de início de cada página, por status (por exemplo uma tabela ou view materializada em `banco/NN-….sql`).
**Como testaria.**
1. Escrever a hipótese e commitar antes de mexer no código.
2. Criar a estrutura auxiliar em um `.sql` novo e trocar a consulta de listagem.
3. Rodar `verificar-contrato.sh comparar`, incluindo páginas inválidas e páginas além do fim, que devem continuar devolvendo o mesmo que hoje.
4. Comparar `EXPLAIN ANALYZE` e `05-cpu-por-rota.sh` nas páginas 1, 500, 1000 e 15000, antes e depois.
5. Medir três vezes com `medir.sh` e o mesmo rótulo.

**O que precisaria.** Espaço extra para a estrutura auxiliar, uma decisão sobre como ela é atualizada e a recriação do banco do zero a cada mudança de `.sql`.

**O que mudaria minha conclusão.** Se a estrutura auxiliar custar mais em espaço e manutenção do que economiza nas páginas de 1 a 1000, ou se o contrato quebrar, a ideia é descartada. Se o uso real for sequencial ou tiver muitas páginas fundas, ela passa a valer.

## 2. Data warehouse para as rotas de relatório

**Status:** Pesquisada, teste futuro.

**De onde veio.**
- Stonebraker et al., ["C-Store: A Column-oriented DBMS"](https://dsl.cds.iisc.ac.in/~course/DBMS/papers/cstore.pdf), VLDB 2005. Fonte acadêmica primária (cópia hospedada fora do VLDB).
- Documentação do PostgreSQL 16, ["Materialized Views"](https://www.postgresql.org/docs/16/rules-materializedviews.html), que descreve a técnica que usei no lugar.

**O que as fontes dizem.** O artigo descreve data warehouses como sistemas otimizados para leitura, carregados em lotes e consultados de forma ad hoc, e diz que o armazenamento por coluna lê só as colunas de que a consulta precisa, o que favorece agregações sobre muitos dados. Ele separa um armazenamento de escrita de um de leitura: os dados novos entram primeiro no de escrita e são movidos em lotes para o de leitura, e as consultas leem os dois. O artigo descreve um princípio e não avalia o caso desta aplicação.

**Premissa medida aqui.** Os relatórios (`vendas-por-dia`, 8% das requisições, e `top-produtos`, 2%) foram resolvidos dentro do próprio Postgres: agregação no SQL (#15, ganho de vazão de 22,0%) e view materializada (#18, ganho de 153,4%), registrados em `experimentos.md`. A view guarda o resultado do momento em que o banco foi criado, sem atualização.

**Premissa do autor.** Quem consulta relatórios para tomar decisão não é o cliente da loja, então essas consultas não precisam passar pela API principal nem pelo banco que atende as consultas operacionais. Separá-las em um serviço e um armazenamento próprios evita que as analíticas, mesmo as baratas, disputem CPU e cache com as operacionais (clientes, pedidos, busca): cada requisição consome CPU da API e do banco, então menos requisições nesses recursos significa mais vazão para o que importa ao cliente. Isso é uma premissa de uso, não uma medição.

**O que eu acredito que ganharia.** Que a API principal passe a servir as demais rotas com mais vazão só por ter menos concorrência, porque ela está em ~99% da cota de CPU e todo pedido, mesmo barato, gasta um custo fixo nela. O teto desse ganho é a fatia do tráfego que sai: os dois relatórios são ~10% das requisições (8% e 2%). Se o custo de CPU da API por requisição nos relatórios for parecido com o da média, as demais rotas ganhariam cerca de um décimo a mais de capacidade (conta minha, 1 ÷ 0,9, sem medição por rota). O serviço novo tem a própria cota, então a vazão total medida pelo k6 passa a incluir recursos que antes não existiam, e o ganho da API principal precisa ser separado desse efeito. O banco, a ~46–52% de CPU, não é hoje o recurso saturado. Para consultas analíticas pesadas, que não existem nesta aplicação, o benefício de isolar seria maior.

**Conflito com o contrato.** O teste de carga chama os relatórios no mesmo endereço das outras rotas. Tirá-los da API principal exige que esse endereço continue respondendo (por exemplo, um proxy na frente dos dois serviços, ou a API principal repassando a chamada), e isso é mais um componente com custo próprio. Não testei.

**Custo.** É um serviço novo, e o enunciado diz que recurso a mais custa mais. Haveria também um processo de carga entre os dois bancos e mais um ponto onde os dados ficam desatualizados.

**Como testaria.**
1. Escolher o motor depois de ler a documentação dele (não escolhi nenhum aqui).
2. Subir o serviço no `docker-compose.yml`, com limites declarados.
3. Carregar os dados a partir do Postgres com um script versionado.
4. Apontar só as duas rotas de relatório para o novo serviço.
5. Conferir o contrato e medir três vezes, registrando CPU e memória de todos os containers, para separar o ganho da API principal do efeito de ter mais recursos.

**O que precisaria.** A escolha do motor, um processo de carga e atualização dos dados, e mais CPU e memória no compose.

**O que mudaria minha conclusão.** Se a vazão das demais rotas na API principal não subir de forma compatível com a fatia de tráfego que saiu, ou se a CPU e a memória do serviço novo anularem o ganho, a ideia não compensa. Se os relatórios virarem uma parte maior da carga ou passarem a exigir filtros que a view não cobre, ela passa a valer mais.

## Referências

1. Winand, M. *Use The Index, Luke: Paginação sem OFFSET.* https://use-the-index-luke.com/no-offset. Acesso em 20/11/2026.
2. Winand, M. *Use The Index, Luke: Fetch next page.* https://use-the-index-luke.com/sql/partial-results/fetch-next-page. Acesso em 20/11/2026.
3. PostgreSQL 16. *Row Constructor Comparison.* https://www.postgresql.org/docs/16/functions-comparisons.html. Acesso em 20/11/2026.
4. Stonebraker, M. et al. *C-Store: A Column-oriented DBMS.* VLDB 2005. https://dsl.cds.iisc.ac.in/~course/DBMS/papers/cstore.pdf. Acesso em 20/11/2026.
5. PostgreSQL 16. *Materialized Views.* https://www.postgresql.org/docs/16/rules-materializedviews.html. Acesso em 20/11/2026.