#!/bin/bash
# Kompilerer og kører de lokale logiktests (kræver kun Apples Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -O -swift-version 5 \
  MinApp/Catalog.swift MinApp/Catalog+Builtin.swift MinApp/Values.swift MinApp/Logic.swift MinApp/Backup.swift \
  tools/logic-tests/main.swift -o "$OUT/logic-tests"
"$OUT/logic-tests" "$OUT"

# Webappens egen migrate() skal kunne læse en v4-backup (Louis' data).
osascript -l JavaScript - "$OUT/v4-sample.json" <<'JS'
ObjC.import("Foundation");
function run(argv) {
  var read = function (p) { return $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js; };
  var html = read("docs/webapp.html");
  var start = html.indexOf("var BUILTIN_EX=");
  var end = html.indexOf("/* ---------- toast / ark ---------- */");
  var store = { get: function () { return null; }, set: function () {} };
  eval(html.substring(start, end));
  var parsed = JSON.parse(read(argv[0]));
  if (!parsed || !parsed.ex || !(parsed.prog || parsed.groups)) return "FEJL: webappen afviser v4-backuppen";
  var d = migrate(parsed);
  if (d.log.length !== 5) return "FEJL: webappen læste " + d.log.length + " træninger (forventede 5)";
  if (d.v !== 3) return "FEJL: webappen satte v=" + d.v;
  return "Webappen kan læse v4-backuppen (Louis: " + d.log.length + " træninger).";
}
JS
