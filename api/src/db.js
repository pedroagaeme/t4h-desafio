const { Pool } = require('pg');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
};

// H3 (#3): um pool compartilhado reaproveita conexões em vez de abrir uma por consulta.
// Tamanho padrão do pg (max = 10).
const pool = new Pool(config);

async function consultar(sql, parametros = []) {
  const resultado = await pool.query(sql, parametros);
  return resultado.rows;
}

module.exports = { consultar };