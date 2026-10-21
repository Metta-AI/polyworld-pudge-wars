"""Execution of the s-rune-owner interface; no persistent state."""


def owned_visible_runes(me, allies, runes):
    if not allies:
        return []
    eligible = [p for p in [me, *allies] if p['alive'] and p['layer'] == me['team']
                and not p['hooked'] and not p['rot'] and p['hp'] >= p['max_hp'] * .4]
    owned = []
    for rune in runes:
        owner = min(eligible, key=lambda p: ((p['x']-rune['x'])**2 + (p['y']-rune['y'])**2, p['id']), default=None)
        if owner is not None and owner['id'] == me['id']:
            owned.append(rune)
    return owned
