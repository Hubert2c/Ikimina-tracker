"""Storage layer.

Two interchangeable stores with the SAME methods:

* GroupStore    - keeps data in memory (used by unit tests and quick local runs).
* PostgresStore - keeps data in PostgreSQL (used by Docker Compose).

Because routes and services only call these methods, switching from one store
to the other needs no change anywhere else in the app.
"""


class GroupStore:
    """In-memory store. Data is lost when the process stops."""

    def __init__(self):
        self._groups = {}
        self._next_id = 1

    def create_group(self, name):
        gid = self._next_id
        self._next_id += 1
        self._groups[gid] = {"id": gid, "name": name, "members": [], "contributions": []}
        return self._groups[gid]

    def get_group(self, gid):
        return self._groups.get(gid)

    def list_groups(self):
        return list(self._groups.values())

    def add_member(self, gid, member):
        self._groups[gid]["members"].append(member)
        return self._groups[gid]

    def add_contribution(self, gid, member, amount):
        self._groups[gid]["contributions"].append({"member": member, "amount": amount})
        return self._groups[gid]


# SQL that creates the tables if they don't exist yet. Running it on every
# start-up is safe because of "IF NOT EXISTS".
SCHEMA = """
CREATE TABLE IF NOT EXISTS groups (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS members (
    id       SERIAL PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name     TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS contributions (
    id       SERIAL PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    member   TEXT NOT NULL,
    -- NUMERIC stores money exactly (no floating-point rounding errors)
    amount   NUMERIC(14, 2) NOT NULL CHECK (amount > 0)
);
"""


def _to_number(value):
    """Turn a database NUMERIC (Decimal) into an int when it is whole, else a float,
    so the JSON looks the same as with the in-memory store (5000, not "5000.00")."""
    return int(value) if value == int(value) else float(value)


class PostgresStore:
    """PostgreSQL-backed store. Data survives restarts (kept in a Docker volume)."""

    def __init__(self, database_url):
        # Imported here so the in-memory mode and the unit tests
        # don't need the PostgreSQL driver installed.
        import psycopg

        self._psycopg = psycopg
        self._url = database_url
        with self._connect() as conn:
            conn.execute(SCHEMA)

    def _connect(self):
        # A new short-lived connection per operation: simple and safe across
        # the several worker processes Gunicorn starts. "with" commits on
        # success and rolls back on error.
        return self._psycopg.connect(self._url)

    def create_group(self, name):
        with self._connect() as conn:
            gid = conn.execute(
                "INSERT INTO groups (name) VALUES (%s) RETURNING id", (name,)
            ).fetchone()[0]
        return self.get_group(gid)

    def get_group(self, gid):
        with self._connect() as conn:
            row = conn.execute("SELECT id, name FROM groups WHERE id = %s", (gid,)).fetchone()
            if row is None:
                return None
            members = conn.execute(
                "SELECT name FROM members WHERE group_id = %s ORDER BY id", (gid,)
            ).fetchall()
            contributions = conn.execute(
                "SELECT member, amount FROM contributions WHERE group_id = %s ORDER BY id",
                (gid,),
            ).fetchall()
        return {
            "id": row[0],
            "name": row[1],
            "members": [m[0] for m in members],
            "contributions": [{"member": c[0], "amount": _to_number(c[1])} for c in contributions],
        }

    def list_groups(self):
        with self._connect() as conn:
            rows = conn.execute("SELECT id FROM groups ORDER BY id").fetchall()
        return [self.get_group(r[0]) for r in rows]

    def add_member(self, gid, member):
        with self._connect() as conn:
            conn.execute("INSERT INTO members (group_id, name) VALUES (%s, %s)", (gid, member))
        return self.get_group(gid)

    def add_contribution(self, gid, member, amount):
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO contributions (group_id, member, amount) VALUES (%s, %s, %s)",
                (gid, member, amount),
            )
        return self.get_group(gid)
