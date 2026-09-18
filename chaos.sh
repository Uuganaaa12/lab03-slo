#!/bin/bash
# Chaos туршилт: k6 2 минут явж байхад 40 дахь секундэд серверийг зогсоож
# (Ctrl+C-тэй ижил SIGINT), 10 секундийн дараа дахин асаана.
# Гараар хийхэд цаг нь яг гардаггүй тул скрипт болгосон.
# Эхлээд өөр терминалд: node server.js
set -u
cd "$(dirname "$0")"

KILL_AT=40
DOWN=10

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
up()  { [ "$(curl -s -o /dev/null -w '%{http_code}' -m 0.5 -X POST localhost:3000/cart/add)" = 200 ]; }

pid=$(lsof -ti tcp:3000 -sTCP:LISTEN)
if [ -z "$pid" ]; then echo "Server ajillahgui baina. Ehleed: node server.js"; exit 1; fi

t0=$(now)
k6 run --no-color --duration 2m slo-test.js > results/chaos.txt 2>&1 &
k6pid=$!
echo "k6 ehellee (2 min). ${KILL_AT} s-iin daraa serveriig zogsoono..."
sleep "$KILL_AT"

t_kill=$(now)
kill -INT "$pid"
while up; do sleep 0.02; done
t_down=$(now)
echo "Server zogsow. ${DOWN} s huleej baina..."

sleep "$DOWN"
t_start=$(now)
node server.js > /tmp/lab03-server.log 2>&1 &
until up; do sleep 0.02; done
t_ok=$(now)
echo "Server sergew. k6 duusahiig huleej baina..."

wait "$k6pid"; k6exit=$?
t_end=$(now)

python3 - "$t0" "$t_kill" "$t_down" "$t_start" "$t_ok" "$t_end" "$k6exit" > results/chaos-timeline.txt <<'PY'
import sys, datetime as dt
t0, kill, down, start, ok, end = map(float, sys.argv[1:7]); code = sys.argv[7]
f = lambda t: dt.datetime.fromtimestamp(t).strftime('%H:%M:%S.%f')[:-3]
rows = [
  ("k6 ehelsen",                         t0),
  ("SIGINT ilgeesen (= Ctrl+C)",         kill),
  ("server hariulahgui bolson",          down),
  ("node server.js dahin ajilluulsan",   start),
  ("anhny amjilttai hariu (HTTP 200)",   ok),
  ("k6 duussan",                         end),
]
print("Lab03 chaos turshiltiin tsagiin shugam")
print("=" * 62)
print(f"{'Uil yavdal':<36} {'Tsag':>12} {'k6-ees hoish':>12}")
for name, t in rows:
    print(f"{name:<36} {f(t):>12} {t - t0:>10.3f} s")
print("=" * 62)
print(f"Sergeh hugatsaa (SIGINT -> anhny 200):  {ok - kill:.3f} s")
print(f"Dahin asahad zartsuulsan (start -> 200): {ok - start:.3f} s")
print(f"k6 exit code: {code}")
PY
cat results/chaos-timeline.txt
exit 0
