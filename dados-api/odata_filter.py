"""Tradução de um subconjunto do $filter do OData v4 para SQL parametrizado (Postgres).

Suporta o que o Power Query costuma enviar ao "dobrar" filtros:
  comparações  eq ne gt ge lt le  (inclusive "eq null")
  lógicos      and or not, parênteses
  funções      contains startswith endswith tolower toupper trim year month day date
  literais     'texto' (com '' escapado), números, true/false, null,
               datas 2026-01-31, data-hora 2026-01-31T10:00:00Z / ±hh:mm
Colunas só entram se existirem na view; valores sempre vão como parâmetro (%s).
Qualquer coisa fora disso gera FiltroInvalido (vira HTTP 400).
"""
import re
from datetime import date, datetime

TOKEN = re.compile(r"""
    \s*(?:
      (?P<str>'(?:[^']|'')*')
    | (?P<dt>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?)
    | (?P<date>\d{4}-\d{2}-\d{2})
    | (?P<num>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?[mMdDfFlL]?)
    | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<sym>[(),])
    )""", re.VERBOSE)

COMPARA = {"eq": "=", "ne": "<>", "gt": ">", "ge": ">=", "lt": "<", "le": "<="}
FUNCOES_TEXTO = {"tolower": "LOWER", "toupper": "UPPER", "trim": "TRIM"}
FUNCOES_DATA = {"year": "EXTRACT(YEAR FROM {})", "month": "EXTRACT(MONTH FROM {})",
                "day": "EXTRACT(DAY FROM {})", "date": "CAST({} AS date)"}


class FiltroInvalido(ValueError):
    pass


def tokens(texto):
    pos, saida = 0, []
    while pos < len(texto):
        if texto[pos:].strip() == "":
            break
        m = TOKEN.match(texto, pos)
        if not m or m.end() == pos:
            raise FiltroInvalido(f"trecho não reconhecido no $filter: {texto[pos:pos + 20]!r}")
        tipo = m.lastgroup
        saida.append((tipo, m.group(tipo)))
        pos = m.end()
    return saida


class Parser:
    def __init__(self, texto, colunas):
        self.t = tokens(texto)
        self.i = 0
        self.colunas = colunas
        self.params = []

    def olhar(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def pegar(self, esperado=None):
        tipo, valor = self.olhar()
        if tipo is None or (esperado and valor != esperado):
            raise FiltroInvalido(f"esperado {esperado or 'mais conteúdo'} no $filter")
        self.i += 1
        return tipo, valor

    def palavra(self, *opcoes):
        tipo, valor = self.olhar()
        return tipo == "ident" and valor.lower() in opcoes

    def analisar(self):
        sql = self.ou()
        if self.i != len(self.t):
            raise FiltroInvalido(f"sobrou conteúdo no $filter: {self.olhar()[1]!r}")
        return sql, self.params

    def ou(self):
        sql = self.e()
        while self.palavra("or"):
            self.pegar()
            sql = f"({sql} OR {self.e()})"
        return sql

    def e(self):
        sql = self.nao()
        while self.palavra("and"):
            self.pegar()
            sql = f"({sql} AND {self.nao()})"
        return sql

    def nao(self):
        if self.palavra("not"):
            self.pegar()
            return f"(NOT {self.nao()})"
        return self.comparacao()

    def comparacao(self):
        esq = self.operando()
        if self.palavra(*COMPARA):
            op = self.pegar()[1].lower()
            dir_ = self.operando()
            if dir_ == "NULL" or esq == "NULL":
                if op not in ("eq", "ne"):
                    raise FiltroInvalido("null só pode ser comparado com eq/ne")
                campo = esq if dir_ == "NULL" else dir_
                return f"({campo} IS {'NOT ' if op == 'ne' else ''}NULL)"
            return f"({esq} {COMPARA[op]} {dir_})"
        return esq  # função booleana (contains/startswith/endswith) ou expressão entre parênteses

    def operando(self):
        tipo, valor = self.olhar()
        if tipo == "sym" and valor == "(":
            self.pegar()
            sql = self.ou()
            self.pegar(")")
            return f"({sql})"
        if tipo == "str":
            self.pegar()
            return self.param(valor[1:-1].replace("''", "'"))
        if tipo == "dt":
            self.pegar()
            return self.param(datetime.fromisoformat(valor.replace("Z", "+00:00")).replace(tzinfo=None))
        if tipo == "date":
            self.pegar()
            return self.param(date.fromisoformat(valor))
        if tipo == "num":
            self.pegar()
            v = valor.rstrip("mMdDfFlL")
            return self.param(float(v) if any(c in v for c in ".eE") else int(v))
        if tipo == "ident":
            nome = valor
            baixo = nome.lower()
            if baixo in ("true", "false"):
                self.pegar()
                return "TRUE" if baixo == "true" else "FALSE"
            if baixo == "null":
                self.pegar()
                return "NULL"
            self.pegar()
            if self.olhar() == ("sym", "("):
                return self.funcao(baixo)
            if nome not in self.colunas:
                raise FiltroInvalido(f"coluna inexistente no $filter: {nome}")
            return f'"{nome}"'
        raise FiltroInvalido(f"valor inesperado no $filter: {valor!r}")

    def funcao(self, nome):
        self.pegar("(")
        args = [self.ou()]
        while self.olhar() == ("sym", ","):
            self.pegar()
            args.append(self.ou())
        self.pegar(")")
        if nome in ("contains", "startswith", "endswith") and len(args) == 2:
            campo, valor = args
            molde = {"contains": "CONCAT('%%', {}, '%%')", "startswith": "CONCAT({}, '%%')",
                     "endswith": "CONCAT('%%', {})"}[nome]
            return f"({campo} ILIKE {molde.format(valor)})"  # ILIKE: sem diferenciar maiúsculas, como no MySQL
        if nome in FUNCOES_TEXTO and len(args) == 1:
            return f"{FUNCOES_TEXTO[nome]}({args[0]})"
        if nome in FUNCOES_DATA and len(args) == 1:
            return FUNCOES_DATA[nome].format(args[0])
        raise FiltroInvalido(f"função não suportada no $filter: {nome}/{len(args)}")

    def param(self, valor):
        self.params.append(valor)
        return "%s"


def traduzir(texto, colunas):
    """Devolve (sql, params) para usar num WHERE. colunas = nomes válidos da view."""
    return Parser(texto, set(colunas)).analisar()
