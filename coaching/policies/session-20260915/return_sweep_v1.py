def coaching_return_sweep(obs):
    """Execution for the versioned k-return-sweep interface; no action emission."""
    me = obs['self']
    units = obs['visible']['pudges']
    if not me['alive'] or me['layer'] != me['team'] or not any(p['alive'] and p['team'] == me['team'] and p['id'] != me['id'] for p in units):
        return None
    hook = next((h for h in obs['visible']['hooks'] if h['owner_id'] == me['id'] and not h['flying'] and not h['victim']), None)
    if hook is None or abs(me['x'] - hook['x']) < 2:
        return None
    # Only an outward head returning from the direction of the enemy bank.
    if (hook['x'] - me['x']) * (1 if me['team'] == 0 else -1) <= 0:
        return None
    candidates = []
    for target in units:
        if not target['alive'] or target['shield'] or target['team'] == me['team']:
            continue
        fraction = (target['x'] - hook['x']) / (me['x'] - hook['x'])
        if not .2-1e-9 <= fraction <= .85+1e-9:
            continue
        y = hook['y'] + (target['y'] - hook['y']) / fraction
        if 16-1e-9 <= y <= 111+1e-9 and abs(y - me['y']) <= 8+1e-9:
            candidates.append((abs(y - me['y']), target['id'], max(16.,min(111.,y))))
    if not candidates:
        return None
    return [me['x'], min(candidates)[2]]
