import os, re, sys, collections

root = 'scripts'
files = []
for base, d, fs in os.walk(root):
    for f in fs:
        if f.endswith('.gd'):
            files.append(os.path.join(base, f))

src = {p: open(p, encoding='utf-8').read() for p in files}

# class_name -> file
owner = {}
for p, s in src.items():
    m = re.search(r'^class_name\s+(\w+)', s, re.M)
    if m:
        if m.group(1) in owner:
            print('DUPLICATE class_name %s in %s and %s' % (m.group(1), owner[m.group(1)], p))
        owner[m.group(1)] = p

# members each class declares (funcs, consts, vars, enums, signals, inner classes)
members = {}
for name, p in owner.items():
    s = src[p]
    got = set()
    got |= set(re.findall(r'^\s*(?:static\s+)?func\s+(\w+)', s, re.M))
    got |= set(re.findall(r'^\s*(?:static\s+)?(?:@\w+(?:\([^)]*\))?\s+)?var\s+(\w+)', s, re.M))
    got |= set(re.findall(r'^\s*const\s+(\w+)', s, re.M))
    got |= set(re.findall(r'^\s*enum\s+(\w+)', s, re.M))
    got |= set(re.findall(r'^\s*signal\s+(\w+)', s, re.M))
    got |= set(re.findall(r'^\s*class\s+(\w+)', s, re.M))
    members[name] = got

# duplicate top-level func names inside one file — Godot refuses these
for p, s in src.items():
    seen = collections.Counter(re.findall(r'^(?:static\s+)?func\s+(\w+)', s, re.M))
    for name, c in seen.items():
        if c > 1:
            print('DUPLICATE func %s (%d times) in %s' % (name, c, p))

def strip(s):
    s = re.sub(r'"""[\s\S]*?"""', '""', s)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", s)
    s = re.sub(r'^\s*#.*$', '', s, flags=re.M)
    s = re.sub(r'#.*$', '', s, flags=re.M)
    return s

BUILT_IN = {
    'new', 'instantiate', 'call', 'callv', 'call_deferred', 'connect',
    'disconnect', 'emit', 'emit_signal', 'free', 'queue_free', 'get',
    'set', 'has_method', 'has_signal', 'get_class', 'is_class', 'duplicate',
    'to_string', 'resource_path', 'reference', 'unreference', 'notification',
    'get_script', 'set_script', 'get_instance_id', 'is_queued_for_deletion',
    'bind', 'unbind', 'is_valid', 'get_signal_connection_list', 'add_user_signal',
}

bad = 0
for p, s in src.items():
    body = strip(s)
    for cls, attr in re.findall(r'\b([A-Z]\w+)\.(\w+)\b', body):
        if cls not in owner:
            continue
        if attr in members[cls]:
            continue
        # Inherited from Object, RefCounted, Node and friends. Not declared in
        # the file and not missing either.
        if attr in BUILT_IN:
            continue
        # Inner classes bring their own members; anything a class inherits is
        # not listed here either, so only report when nothing in the whole
        # file offers the name.
        if re.search(r'^\s*(?:static\s+)?func\s+%s\b' % re.escape(attr), src[owner[cls]], re.M):
            continue
        print('%s: %s.%s — %s declares no such member' % (p, cls, attr, owner[cls]))
        bad += 1
print('--- %d unresolved references' % bad)
