#!/usr/bin/env bats
# M8.4 Unit 2 - edge cases for task_lock.py.

load helpers/load
load helpers/assertions

LIB_DIR="$CORE_ROOT/skills/builtin/_lib"

py_helper() {
  local script="$1"
  PYTHONPATH="$LIB_DIR" python3 -c "$script"
}

@test "M8.4 invalid task_dir name raises ValueError on acquire" {
  d=$(make_scratch)
  mkdir -p "$d/not-a-task"
  run py_helper "
import task_lock as tl
try:
    with tl.acquire('$d/not-a-task'):
        print('NO_RAISE')
except ValueError as e:
    print('OK', 'task_dir' in str(e) or 'T-' in str(e))
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "OK True"
}

@test "M8.4 path traversal style task_dir name rejected" {
  d=$(make_scratch)
  mkdir -p "$d/.."
  run py_helper "
import task_lock as tl
for bad in ('..', '.', 'foo', 't-001', 'T-/etc', ''):
    try:
        tl.acquire('$d/' + bad).__enter__()
        print('LEAK', bad)
        break
    except ValueError:
        pass
else:
    print('OK')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "OK"
}

@test "M8.4 corrupted lockfile is treated as stale and force-released" {
  d=$(make_scratch)
  mkdir -p "$d/T-001"
  printf 'this is not json {{{' > "$d/T-001/router.lock"
  run py_helper "
import task_lock as tl
assert tl.inspect('$d/T-001') is None
with tl.acquire('$d/T-001', timeout=2.0) as p:
    assert p['task_id'] == 'T-001'
print('OK')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "OK"
}

@test "M8.4 reentrant acquire from same process is forbidden" {
  d=$(make_scratch)
  mkdir -p "$d/T-001"
  run py_helper "
import task_lock as tl, time
t0 = time.monotonic()
with tl.acquire('$d/T-001'):
    try:
        with tl.acquire('$d/T-001', timeout=2.0):
            print('NO_RAISE')
    except tl.LockTimeout as e:
        # must fail FAST, not after waiting timeout
        assert (time.monotonic() - t0) < 0.5
        print('OK', 'reentrant' in str(e) or 'already held' in str(e))
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" "OK True"
}
