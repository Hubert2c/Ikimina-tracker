"""Business logic, kept separate from HTTP concerns (separation of concerns)."""


class ValidationError(ValueError):
    pass


class NotFoundError(LookupError):
    pass


def _require_group(store, gid):
    group = store.get_group(gid)
    if group is None:
        raise NotFoundError("group not found")
    return group


def create_group(store, name):
    name = (name or "").strip()
    if not name:
        raise ValidationError("name is required")
    return store.create_group(name)


def add_member(store, gid, member):
    group = _require_group(store, gid)
    member = (member or "").strip()
    if not member:
        raise ValidationError("member name is required")
    if member.lower() in (m.lower() for m in group["members"]):
        raise ValidationError("member already exists")
    group["members"].append(member)
    return group


def add_contribution(store, gid, member, amount):
    group = _require_group(store, gid)
    member = (member or "").strip()
    if member.lower() not in (m.lower() for m in group["members"]):
        raise ValidationError("member is not in this group")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount <= 0:
        raise ValidationError("amount must be a positive number")
    canonical = next(m for m in group["members"] if m.lower() == member.lower())
    group["contributions"].append({"member": canonical, "amount": amount})
    return group


def summary(store, gid):
    group = _require_group(store, gid)
    balances = {m: 0 for m in group["members"]}
    for c in group["contributions"]:
        balances[c["member"]] += c["amount"]
    return {
        "id": group["id"],
        "name": group["name"],
        "balances": balances,
        "total": sum(balances.values()),
    }


def member_balance(store, gid, member):
    data = summary(store, gid)
    for m, bal in data["balances"].items():
        if m.lower() == (member or "").strip().lower():
            return {"member": m, "balance": bal}
    raise NotFoundError("member not found")
