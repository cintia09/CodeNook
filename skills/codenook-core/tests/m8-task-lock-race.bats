#!/usr/bin/env bats
# M8.4 Unit 3 - regression tests for the unlink-recreate race in
# task_lock.acquire().
#
# Bug: a contender that opens the lockfile while the holder has
# flocked the inode but not yet written the JSON payload would read
# 0 bytes, classify the empty payload as "stale", unlink the
# holder's file, and then succeed on a fresh inode -> two processes
# concurrently _HELD.
#
# Fix: empty/unparseable payload is now treated as "writer mid-init,
# retry without unlink"; only POSITIVELY stale payloads (dead pid or
# parseable+expired started_at) are unlinked.

load helpers/load
load helpers/assertions

LIB_DIR="$CORE_ROOT/skills/builtin/_lib"
HOLDER="$CORE_ROOT/tests/helpers/m8_lock_holder.py"

py_helper() {
  local script="$1"
  PYTHONPATH="$LIB_DIR" python3 -c "$script"
}

mk_taskdir() {
  local d
  d=$(make_scratch)
  mkdir -p "$d/T-001"
  echo "$d/T-001"
}

@test "M8.4 race: contender never acquires while gated holder is alive" {
  td=$(mk_taskdir)
  run py_helper "
import multiprocessing as mp, os, sys, time
mp.set_start_method('fork', force=True)
sys.path.insert(0, '$LIB_DIR')
import task_lock as tl

def holder(td, ready, done):
    with tl.acquire(td, timeout=5.0):
        ready.set()
        done.wait(timeout=5.0)

def contender(td, hold_pid_box, results):
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        try:
            with tl.acquire(td, timeout=0.05, poll_interval=0.01):
                try:
                    os.kill(hold_pid_box.value, 0)
                    alive = True
                except ProcessLookupError:
                    alive = False
                results.put('SUCCESS_WHILE_ALIVE' if alive else 'SUCCESS_AFTER_DEATH')
                return
        except tl.LockTimeout:
            pass
    results.put('NO_ACQUIRE')

ready = mp.Event()
done = mp.Event()
pid_box = mp.Value('i', 0)
results = mp.Queue()

h = mp.Process(target=holder, args=('$td', ready, done))
h.start()
pid_box.value = h.pid

contenders = [mp.Process(target=contender, args=('$td', pid_box, results))
              for _ in range(8)]
for c in contenders:
    c.start()

assert ready.wait(timeout=3.0), 'holder failed to acquire'
for c in contenders:
    c.join(timeout=4.0)
done.set()
h.join(timeout=3.0)

outcomes = []
while not results.empty():
    outcomes.append(results.get())
bad = [o for o in outcomes if o == 'SUCCESS_WHILE_ALIVE']
assert not bad, f'race: contender(s) acquired while holder alive: {bad}'
print('OK', len(outcomes), 'contenders, 0 races')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "OK"
}

@test "M8.4 race: 20 parallel contenders never steal lock from live holder" {
  td=$(mk_taskdir)
  out_file="$BATS_TEST_TMPDIR/holder.out"
  LIB_DIR="$LIB_DIR" python3 "$HOLDER" "$td" 4 >"$out_file" 2>&1 &
  holder_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -s "$out_file" ] && break
    sleep 0.2
  done
  [ -s "$out_file" ] || { kill "$holder_pid" 2>/dev/null; cat "$out_file"; return 1; }

  run py_helper "
import multiprocessing as mp, sys
mp.set_start_method('fork', force=True)
sys.path.insert(0, '$LIB_DIR')
import task_lock as tl

def contender(td, q):
    try:
        with tl.acquire(td, timeout=1.5, poll_interval=0.01):
            q.put('STOLE')
    except tl.LockTimeout:
        q.put('TIMEOUT')

q = mp.Queue()
ps = [mp.Process(target=contender, args=('$td', q)) for _ in range(20)]
for p in ps:
    p.start()
for p in ps:
    p.join(timeout=5.0)

results = []
while not q.empty():
    results.append(q.get())
stole = [r for r in results if r == 'STOLE']
assert not stole, f'race: {len(stole)}/20 contenders stole the lock'
assert len(results) == 20, f'lost workers: {len(results)}/20'
print('OK', len(results), 'contenders, 0 stole')
"
  status_main=$status
  output_main=$output
  kill "$holder_pid" 2>/dev/null
  wait "$holder_pid" 2>/dev/null || true
  [ "$status_main" -eq 0 ] || { echo "$output_main"; return 1; }
  assert_contains "$output_main" "OK"
}

@test "M8.4 race: fake holder with empty payload is NOT unlinked (regression)" {
  # Direct regression for the reported bug. A process flocks the
  # lockfile but never writes the JSON payload (0-byte file). The
  # contender must classify this as "writer mid-init", keep
  # retrying, and NEVER unlink the holder's inode.
  td=$(mk_taskdir)
  out_file="$BATS_TEST_TMPDIR/fake.out"
  python3 - "$td" >"$out_file" 2>&1 <<'PY' &
import os, sys, time, fcntl
td = sys.argv[1]
lock_path = os.path.join(td, "router.lock")
fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
st = os.fstat(fd)
print(os.getpid(), st.st_ino, flush=True)
time.sleep(4)
PY
  fake_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -s "$out_file" ] && break
    sleep 0.2
  done
  [ -s "$out_file" ] || { kill "$fake_pid" 2>/dev/null; cat "$out_file"; return 1; }

  read -r holder_pid orig_inode <"$out_file"

  run py_helper "
import os, sys, time
sys.path.insert(0, '$LIB_DIR')
import task_lock as tl
lock_path = '$td/router.lock'
ino_before = os.stat(lock_path).st_ino
t0 = time.monotonic()
try:
    with tl.acquire('$td', timeout=0.8, poll_interval=0.05):
        print('STOLE')
        sys.exit(1)
except tl.LockTimeout:
    pass
dt = time.monotonic() - t0
ino_after = os.stat(lock_path).st_ino
assert ino_before == ino_after == $orig_inode, \
    f'lockfile was unlinked-and-recreated: before={ino_before} after={ino_after} orig=$orig_inode'
assert 0.6 <= dt < 2.0, f'unexpected timeout duration: {dt}'
print('OK inode_preserved', ino_after)
"
  status_main=$status
  output_main=$output
  kill "$fake_pid" 2>/dev/null
  wait "$fake_pid" 2>/dev/null || true
  [ "$status_main" -eq 0 ] || { echo "$output_main"; return 1; }
  assert_contains "$output_main" "OK inode_preserved"
}
