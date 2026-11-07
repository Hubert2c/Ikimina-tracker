"""Business logic, kept separate from HTTP concerns (separation of concerns)."""

import math

# Input limits (security: stop oversized or nonsense data from being stored).
MAX_NAME_LENGTH = 100            # longest allowed group or member name
MAX_AMOUNT = 1_000_000_000       # largest single contribution (fits NUMERIC(14, 2))


class ValidationError(ValueError):
    pass


class NotFoundError(LookupError):
    pass


def _clean_name(value, field):
    """Strip spaces and check a name is present and not too long."""
    if value is not None and not isinstance(value, str):
        raise ValidationError(f"{field} must be text")
    value = (value or "").strip()
    if not value:
        raise ValidationError(f"{field} is required")
    if len(value) > MAX_NAME_LENGTH:
        raise ValidationError(f"{field} must be at most {MAX_NAME_LENGTH} characters")
    return value


def _check_amount(amount):
    """Accept only real, positive, finite numbers up to MAX_AMOUNT.

    bool is rejected because True/False are ints in Python.
    math.isfinite rejects NaN and Infinity, which JSON parsing in Python allows
    and which would otherwise corrupt every balance in the group.
    """
    if isinstance(amount, bool) or not isinstance(amount, (int, float)):
        raise ValidationError("amount must be a positive number")
    if not math.isfinite(amount) or amount <= 0:
        raise ValidationError("amount must be a positive number")
    if amount > MAX_AMOUNT:
        raise ValidationError(f"amount must be at most {MAX_AMOUNT}")


def _require_group(store, gid):
    group = store.get_group(gid)
    if group is None:
        raise NotFoundError("group not found")
    return group


def create_group(store, name):
    name = _clean_name(name, "name")
    return store.create_group(name)


def add_member(store, gid, member):
    group = _require_group(store, gid)
    member = _clean_name(member, "member name")
    if member.lower() in (m.lower() for m in group["members"]):
        raise ValidationError("member already exists")
    # Saving goes through the store so it works for memory AND PostgreSQL
    return store.add_member(gid, member)


def add_contribution(store, gid, member, amount):
    group = _require_group(store, gid)
    member = (member or "").strip() if isinstance(member, str) else ""
    if member.lower() not in (m.lower() for m in group["members"]):
        raise ValidationError("member is not in this group")
    _check_amount(amount)
    canonical = next(m for m in group["members"] if m.lower() == member.lower())
    return store.add_contribution(gid, canonical, amount)


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
