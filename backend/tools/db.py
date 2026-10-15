"""
Database access for the import tools — the same scripts run from a laptop (over SSH) and on the OVH host itself.

  SP_DB=ssh    (default) ssh ubuntu@51.195.148.252 sudo docker exec … psql
  SP_DB=local  on the server: sudo docker exec … psql
"""
import csv, io, os, subprocess

HOST = os.environ.get("SP_DB_HOST", "ubuntu@51.195.148.252")
PSQL = ["sudo", "docker", "exec", "-i", "supabase-db", "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1"]


def _run(sql: str, args: list[str]) -> str:
    """psql with the SQL on stdin, locally or over SSH — no shell quoting of SQL anywhere."""
    cmd = PSQL + args if os.environ.get("SP_DB", "ssh") == "local" else ["ssh", "-o", "BatchMode=yes", HOST, " ".join(PSQL + args)]
    return subprocess.run(cmd, input=sql, capture_output=True, text=True, check=True).stdout


def rows(query: str) -> list[dict]:
    """SELECT → list of dicts (via COPY … CSV)."""
    return list(csv.DictReader(io.StringIO(_run(f"copy ({query}) to stdout with csv header;", ["-q"]))))


def apply(sql: str) -> str:
    """Run a SQL script in one transaction."""
    return _run(sql, ["-1", "-q"])
