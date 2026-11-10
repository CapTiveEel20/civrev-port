"""Cross-check a game's firmware imports against ps3recomp's HLE implementations.

usage: python import_coverage.py <ps3recomp root> <imports_named.json> <out.md>
"""
import glob, json, os, re, sys, collections

root, imports_path, out_path = sys.argv[1:4]
sys.path.insert(0, os.path.join(root, "tools"))
from nid_database import compute_nid  # noqa: E402
import gen_hle_nids  # noqa: E402  (reuse its definition regex)

impl_by_nid = {}   # nid -> (name, file)
stub_like = set()  # names whose body looks like a bare "return CELL_OK" stub

src_files = [p for p in glob.glob(os.path.join(root, "libs", "**", "*.c*"), recursive=True)
             + glob.glob(os.path.join(root, "runtime", "**", "*.c*"), recursive=True)
             if os.sep + "tests" + os.sep not in p]

reg_re = re.compile(r'ps3_hle_register\w*\s*\(\s*(0x[0-9A-Fa-f]+)u?\s*,\s*"(\w+)"')
table_re = re.compile(r'\{\s*"(\w+)"\s*,\s*(\w+)\s*\}')
reg_nid_re = re.compile(r'ps3_hle_register\w*\s*\(\s*ps3_compute_nid\(\s*"(\w+)"\s*\)')
for p in src_files:
    txt = open(p, encoding="latin1").read()
    rel = os.path.relpath(p, root).replace("\\", "/")
    for m in gen_hle_nids.DEF_RE.finditer(txt):
        name = m.group(1)
        impl_by_nid.setdefault(compute_nid(name), (name, rel))
        body = txt[m.end():m.end() + 160]
        if re.match(r"\s*(\(void\)\w+;\s*)*return\s+(CELL_OK|0)\s*;\s*\}", body):
            stub_like.add(name)
    for m in reg_re.finditer(txt):
        impl_by_nid.setdefault(int(m.group(1), 16), (m.group(2), rel))
    for m in reg_nid_re.finditer(txt):
        impl_by_nid.setdefault(compute_nid(m.group(1)), (m.group(1), rel))
    # name tables such as sysNet.c's { "connect", h_connect }; h_ok means "just succeed"
    for m in table_re.finditer(txt):
        name, handler = m.group(1), m.group(2)
        impl_by_nid.setdefault(compute_nid(name), (name, rel))
        if handler in ("h_ok", "hle_ok", "stub_ok"):
            stub_like.add(name)

imports = json.load(open(imports_path))
by_lib = collections.defaultdict(list)
for imp in imports:
    nid = int(imp["nid"], 16)
    name = imp.get("name") or f"<unknown {imp['nid']}>"
    hit = impl_by_nid.get(nid)
    status = "missing" if not hit else ("stub" if hit[0] in stub_like else "implemented")
    by_lib[imp["lib"]].append((name, imp["nid"], status, hit[1] if hit else ""))

totals = collections.Counter(s for v in by_lib.values() for _, _, s, _ in v)
lines = ["# Civ Rev (BLES00238) import coverage", "",
         f"{len(imports)} imports: {totals['implemented']} implemented, "
         f"{totals['stub']} trivial stubs (return CELL_OK), {totals['missing']} missing.", "",
         "| Library | Imports | Implemented | Stub | Missing |", "|---|---|---|---|---|"]
for lib, rows in sorted(by_lib.items(), key=lambda kv: -len(kv[1])):
    c = collections.Counter(s for _, _, s, _ in rows)
    lines.append(f"| {lib} | {len(rows)} | {c['implemented']} | {c['stub']} | {c['missing']} |")
lines += ["", "## Missing or stubbed", ""]
for lib, rows in sorted(by_lib.items()):
    for name, nid, status, f in rows:
        if status != "implemented":
            lines.append(f"- `{lib}` {name} ({nid}): **{status}** {f}")
lines += ["", "## All imports", ""]
for lib, rows in sorted(by_lib.items()):
    lines.append(f"### {lib}")
    lines += [f"- {name} ({nid}): {status} {('— ' + f) if f else ''}" for name, nid, status, f in rows]
open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines[:40]))
