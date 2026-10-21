def coaching_engagements(me, allies, enemies, reach):
    """Ordered visible melee pairs; an ally hit must have healing utility."""
    pairs = []
    for ally in allies:
        if ally["shield"] or ally["hooked"] or ally["max_hp"] - ally["hp"] < 120:
            continue
        for enemy in enemies:
            if enemy["hooked"] or ally["layer"] != enemy["layer"] or distance(ally, enemy) > 5.5:
                continue
            aim = [(ally[k] + enemy[k]) / 2 for k in ("x", "y")]
            if math.dist([me["x"], me["y"]], aim) > reach:
                continue
            if segment_distance([me["x"], me["y"]], aim, [64, 64]) <= 3.5:
                continue
            pairs.append((ally["hp"] / ally["max_hp"], distance(me, ally),
                          ally["id"], enemy["id"], aim))
    return sorted(pairs)
