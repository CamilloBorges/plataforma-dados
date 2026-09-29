"""Cópia do ERP atual (Informix/Logus, banco bd_bomgado_m) para o schema raw_logus.

Porta do antigo atual/Sync.java (repositório pleno_db_legado) para o Airflow + Postgres.
Segurança do lado do Informix: conexão read-only, isolamento "dirty read" (não segura nem espera
locks do ERP) e só "SELECT *" de nomes validados do tabelas.conf.

Cópia completa com troca atômica: a tabela nova é montada como raw_logus.<t>__novo e trocada
pela antiga na mesma transação, então quem consulta nunca vê tabela vazia ou pela metade.
O Informix é lido por JDBC (driver da IBM) dentro da JVM do JPype; os valores seguem como texto
para o COPY do Postgres, que converte pelo tipo da coluna.
"""
import glob
import logging
import os
import re
import time
from pathlib import Path

import psycopg
from psycopg import sql

CONF = Path(__file__).with_name("tabelas.conf")
JARS = os.environ.get("IFX_JDBC_JARS", "/opt/informix-jdbc/*.jar")
NOME = re.compile(r"^[a-z0-9_]+$")
AGENDA = re.compile(r"^(\d+min|diario \d{2}:\d{2})$")
LOTE = 2000  # fetch size do JDBC

log = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS raw_logus.carga (
    id bigserial PRIMARY KEY,
    tabela text NOT NULL,
    inicio timestamptz NOT NULL DEFAULT now(),
    fim timestamptz,
    linhas bigint,
    erro text
);
CREATE INDEX IF NOT EXISTS carga_tabela_idx ON raw_logus.carga (tabela, inicio DESC);
"""


def tabelas(conf: Path = CONF) -> dict[str, str]:
    """{tabela: agenda} do tabelas.conf, validando nomes e agendas."""
    saida = {}
    for linha in conf.read_text(encoding="utf-8").splitlines():
        linha = re.sub(r"#.*", "", linha).strip()
        if not linha:
            continue
        nome, _, agenda = linha.partition(" ")
        agenda = " ".join(agenda.split())
        if not NOME.match(nome):
            raise ValueError(f"nome de tabela inválido: {nome!r}")
        if not AGENDA.match(agenda):
            raise ValueError(f"{nome}: agenda inválida {agenda!r}")
        saida[nome] = agenda
    return saida


# java.sql.Types -> tipo do Postgres. Texto (CHAR, VARCHAR, LVARCHAR...) vira text.
_TIPOS = {
    -6: "smallint", 5: "smallint", 4: "integer", -5: "bigint",
    7: "real", 6: "double precision", 8: "double precision",
    16: "boolean", -7: "boolean",
    91: "date", 92: "time", 93: "timestamp",
    -2: "bytea", -3: "bytea", -4: "bytea", 2004: "bytea",
}


def tipo_pg(tipo: int, precisao: int, escala: int) -> str:
    if tipo in (2, 3):  # NUMERIC, DECIMAL (DECIMAL(p) "flutuante" do Informix vem com escala 255)
        return f"numeric({precisao},{escala})" if 0 < precisao <= 1000 and 0 <= escala <= precisao else "numeric"
    return _TIPOS.get(tipo, "text")


def _texto(rs, i):
    v = rs.getString(i)
    # CHAR do Informix vem com espaços à direita; o Postgres recusa NUL em text.
    return None if v is None else v.rstrip().replace("\x00", "")


def _objeto(metodo):
    """Data, hora, timestamp e decimal: toString() do objeto Java (formato ISO, independe do DBDATE)."""
    def ler(rs, i):
        v = getattr(rs, metodo)(i)
        return None if v is None else str(v)
    return ler


def _booleano(rs, i):
    v = rs.getBoolean(i)
    return None if rs.wasNull() else ("t" if v else "f")


def _bytes(rs, i):
    v = rs.getBytes(i)
    return None if v is None else bytes(v)


def _numero(rs, i):
    return rs.getString(i)  # inteiros e ponto flutuante: o texto já é o que o Postgres aceita


def leitor(tipo_postgres: str):
    """Função (rs, i) -> valor para o COPY, conforme o tipo da coluna de destino."""
    if tipo_postgres == "text":
        return _texto
    if tipo_postgres.startswith("numeric"):
        return _objeto("getBigDecimal")
    return {
        "date": _objeto("getDate"),
        "time": _objeto("getTime"),
        "timestamp": _objeto("getTimestamp"),
        "boolean": _booleano,
        "bytea": _bytes,
    }.get(tipo_postgres, _numero)


def colunas(meta) -> list[tuple[str, str]]:
    """[(nome, tipo do Postgres)] a partir do ResultSetMetaData."""
    return [
        (meta.getColumnName(i).strip().lower(),
         tipo_pg(meta.getColumnType(i), meta.getPrecision(i), meta.getScale(i)))
        for i in range(1, meta.getColumnCount() + 1)
    ]


def chave_primaria(ifx, tabela: str) -> list[str]:
    rs = ifx.getMetaData().getPrimaryKeys(None, None, tabela)
    pk = []
    while rs.next():
        pk.append((rs.getShort("KEY_SEQ"), rs.getString("COLUMN_NAME").strip().lower()))
    rs.close()
    return [nome for _, nome in sorted(pk)]


def copiar(pg: psycopg.Connection, tabela: str, cols: list[tuple[str, str]], pk: list[str], rs) -> int:
    """Grava as linhas do ResultSet em raw_logus.<tabela> com troca atômica; devolve o nº de linhas."""
    novo = f"{tabela}__novo"
    alvo = sql.Identifier("raw_logus", tabela)
    tmp = sql.Identifier("raw_logus", novo)
    ddl = sql.SQL(", ").join(sql.SQL("{} {}").format(sql.Identifier(n), sql.SQL(t)) for n, t in cols)
    leitores = [(i, leitor(t)) for i, (_, t) in enumerate(cols, start=1)]
    linhas = 0
    with pg.transaction():
        pg.execute(sql.SQL("DROP TABLE IF EXISTS {}").format(tmp))
        pg.execute(sql.SQL("CREATE TABLE {} ({})").format(tmp, ddl))
        with pg.cursor().copy(sql.SQL("COPY {} FROM STDIN").format(tmp)) as copia:
            while rs.next():
                copia.write_row([ler(rs, i) for i, ler in leitores])
                linhas += 1
        if pk:
            pg.execute(sql.SQL("ALTER TABLE {} ADD CONSTRAINT {} PRIMARY KEY ({})").format(
                tmp, sql.Identifier(f"{tabela}_pkey_novo"), sql.SQL(", ").join(map(sql.Identifier, pk))))
        pg.execute(sql.SQL("DROP TABLE IF EXISTS {}").format(alvo))
        pg.execute(sql.SQL("ALTER TABLE {} RENAME TO {}").format(tmp, sql.Identifier(tabela)))
        if pk:
            pg.execute(sql.SQL("ALTER TABLE {} RENAME CONSTRAINT {} TO {}").format(
                alvo, sql.Identifier(f"{tabela}_pkey_novo"), sql.Identifier(f"{tabela}_pkey")))
    return linhas


def conectar_informix(host: str, banco: str, servidor: str, usuario: str, senha: str):
    """Conexão JDBC somente leitura, em dirty read. host = "ip:porta"."""
    import jpype

    if not jpype.isJVMStarted():
        jars = sorted(glob.glob(JARS))
        if not jars:
            raise RuntimeError(f"driver JDBC do Informix não encontrado em {JARS}")
        jpype.startJVM("-Xmx256m", classpath=jars, convertStrings=True)
    jpype.JClass("com.informix.jdbc.IfxDriver")  # registra o driver no DriverManager
    DriverManager = jpype.JClass("java.sql.DriverManager")
    Connection = jpype.JClass("java.sql.Connection")
    Properties = jpype.JClass("java.util.Properties")
    props = Properties()
    props.setProperty("user", usuario)
    props.setProperty("password", senha)
    conn = DriverManager.getConnection(f"jdbc:informix-sqli://{host}/{banco}:INFORMIXSERVER={servidor}", props)
    conn.setReadOnly(True)
    conn.setTransactionIsolation(Connection.TRANSACTION_READ_UNCOMMITTED)
    return conn


def executar(db_url: str, agenda: str, host: str, banco: str, servidor: str, usuario: str, senha: str) -> dict:
    """Copia todas as tabelas da agenda. Falha de uma tabela não impede as demais, mas no fim
    levanta erro (a tarefa fica vermelha e as views dependentes não rodam)."""
    nomes = [t for t, a in tabelas().items() if a == agenda]
    if not nomes:
        raise ValueError(f"nenhuma tabela com a agenda {agenda!r}")
    resultado, erros = {}, {}
    ifx = conectar_informix(host, banco, servidor, usuario, senha)
    try:
        with psycopg.connect(db_url, autocommit=True) as pg:
            pg.execute(DDL)
            for tabela in nomes:
                carga = pg.execute("INSERT INTO raw_logus.carga (tabela) VALUES (%s) RETURNING id", [tabela]).fetchone()[0]
                inicio = time.monotonic()
                try:
                    pk = chave_primaria(ifx, tabela)
                    st = ifx.createStatement()
                    st.setFetchSize(LOTE)
                    rs = st.executeQuery(f"SELECT * FROM {tabela}")  # nome validado em tabelas()
                    try:
                        linhas = copiar(pg, tabela, colunas(rs.getMetaData()), pk, rs)
                    finally:
                        rs.close()
                        st.close()
                    pg.execute("UPDATE raw_logus.carga SET fim = now(), linhas = %s WHERE id = %s", [linhas, carga])
                    resultado[tabela] = linhas
                    log.info("Logus: %s, %s linhas em %.0f s", tabela, linhas, time.monotonic() - inicio)
                except Exception as e:  # noqa: BLE001 - registra e segue para a próxima tabela
                    pg.execute("UPDATE raw_logus.carga SET fim = now(), erro = %s WHERE id = %s", [str(e)[:2000], carga])
                    erros[tabela] = str(e)
                    log.error("Logus: erro em %s: %s", tabela, e)
    finally:
        ifx.close()
    if erros:
        raise RuntimeError(f"falha em {len(erros)} tabela(s): {erros}")
    return resultado
