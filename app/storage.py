"""Storage layer. In-memory for now; swap for a database in a later formative
without touching routes or business logic."""


class GroupStore:
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
