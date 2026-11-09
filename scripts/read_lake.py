"""
Read a Delta table straight from the Azure data lake (ADLS Gen2), with DuckDB.

Run it from Project 2's venv (it has duckdb), after `az login`:

    python scripts\\read_lake.py                          silver/products (default)
    python scripts\\read_lake.py silver exchange_rates     another table, if you uploaded it

How it logs in: the "azure" extension uses your `az login` session (credential chain "cli"), so
the data-plane ROLE you gave yourself with Terraform is what allows the read. No storage key.
"""
import sys

import duckdb

ACCOUNT = "stlusitaniadevjf01"


def main() -> None:
    container = sys.argv[1] if len(sys.argv) > 1 else "silver"
    table = sys.argv[2] if len(sys.argv) > 2 else "products"
    path = f"abfss://{container}@{ACCOUNT}.dfs.core.windows.net/{table}"

    con = duckdb.connect()
    for ext in ("azure", "delta"):
        con.execute(f"INSTALL {ext}")
        con.execute(f"LOAD {ext}")
    con.execute(f"""
        CREATE SECRET lake (TYPE azure, PROVIDER credential_chain, CHAIN 'cli', ACCOUNT_NAME '{ACCOUNT}')
    """)

    print(f"Reading the Delta table {path}\n")
    rows = con.execute(f"SELECT COUNT(*) FROM delta_scan('{path}')").fetchall()[0][0]
    print(f"rows: {rows:,}\n")

    result = con.execute(f"SELECT * FROM delta_scan('{path}') LIMIT 5")
    columns = [d[0] for d in result.description]
    print(" | ".join(columns))
    for row in result.fetchall():
        print(" | ".join(str(v) for v in row))


if __name__ == "__main__":
    main()
