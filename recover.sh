#!/usr/bin/env bash
# What you can get back after an AI assistant breaks working code — measured,
# by actually destroying things in a throwaway repository and trying to recover.
#
#   ./recover.sh
#
# Every scenario runs in its own fresh repo under a temporary directory, which is
# removed at the end. Nothing here touches anything you care about.
set -u

LAB="$(mktemp -d "${TMPDIR:-/tmp}/recover-lab.XXXXXX")"
trap 'rm -rf "$LAB"' EXIT
PASS=0; FAIL=0
RESULTS=()

say()  { printf '%s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

# record one scenario: name, what we did, whether the content came back
record() {
  local name="$1" got="$2" how="$3"
  if [ "$got" = "yes" ]; then
    RESULTS+=("RECOVERED|$name|$how"); PASS=$((PASS+1))
  else
    RESULTS+=("GONE|$name|$how"); FAIL=$((FAIL+1))
  fi
}

# a fresh repo with one committed file containing a line worth losing
new_repo() {
  local d="$LAB/$1"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q
  git config user.name "Lab"; git config user.email "lab@example.com"
  git config gc.auto 0                      # never garbage-collect mid-test
  printf 'the working version\n' > app.txt
  git add app.txt; git commit -q -m "working"
}

TREASURE='the line we must not lose'

say ""
say "  what survives, and what does not — git $(git --version | awk '{print $3}')"
say ""

# ---------------------------------------------------------------- 1
# Committed, then thrown away with a hard reset.
new_repo committed-reset
printf '%s\n' "$TREASURE" >> app.txt
git add app.txt; git commit -q -m "the AI's change"
git reset -q --hard HEAD~1
if git reflog --all | grep -q "the AI's change" && \
   git show "$(git rev-parse HEAD@{1})":app.txt 2>/dev/null | grep -qF "$TREASURE"; then
  record "committed, then reset --hard" yes "git reflog → git reset --hard HEAD@{1}"
else
  record "committed, then reset --hard" no "-"
fi

# ---------------------------------------------------------------- 2
# Never committed, never staged, thrown away with a hard reset.
new_repo uncommitted-reset
printf '%s\n' "$TREASURE" >> app.txt
git reset -q --hard HEAD
if grep -qF "$TREASURE" app.txt 2>/dev/null; then
  record "edited only, then reset --hard" yes "still in the file"
else
  found=$(git fsck --lost-found --no-progress 2>/dev/null | grep -c dangling || true)
  record "edited only, then reset --hard" no "git fsck found no copy (dangling objects: ${found:-0})"
fi

# ---------------------------------------------------------------- 3
# Staged with `git add` but never committed, then thrown away.
# This is the one almost nobody knows: `git add` writes a real object.
new_repo staged-reset
printf '%s\n' "$TREASURE" >> app.txt
git add app.txt
git reset -q --hard HEAD
blob=$(git fsck --lost-found --no-progress 2>/dev/null | awk '/dangling blob/ {print $3}' | head -1)
if [ -n "${blob:-}" ] && git cat-file -p "$blob" 2>/dev/null | grep -qF "$TREASURE"; then
  record "git add, then reset --hard" yes "git fsck --lost-found → git cat-file -p <blob>"
else
  record "git add, then reset --hard" no "-"
fi

# ---------------------------------------------------------------- 4
# Discarded with checkout -- file, the "undo my edits" command.
new_repo checkout-discard
printf '%s\n' "$TREASURE" >> app.txt
git checkout -q -- app.txt
if grep -qF "$TREASURE" app.txt 2>/dev/null; then
  record "git checkout -- file" yes "still in the file"
else
  record "git checkout -- file" no "nothing was ever written to the object store"
fi

# ---------------------------------------------------------------- 5
# A branch deleted outright.
new_repo deleted-branch
git checkout -q -b feature
printf '%s\n' "$TREASURE" >> app.txt
git add app.txt; git commit -q -m "feature work"
sha=$(git rev-parse HEAD)
git checkout -q master 2>/dev/null || git checkout -q main
git branch -q -D feature
if git cat-file -p "$sha":app.txt 2>/dev/null | grep -qF "$TREASURE"; then
  record "branch deleted with -D" yes "git reflog → the commit is still there"
else
  record "branch deleted with -D" no "-"
fi

# ---------------------------------------------------------------- 6
# Stashed, then the stash dropped.
new_repo dropped-stash
printf '%s\n' "$TREASURE" >> app.txt
git stash -q
git stash drop -q 2>/dev/null
found_stash=no
for sha in $(git fsck --unreachable --no-progress 2>/dev/null | awk '/unreachable commit/ {print $3}'); do
  if git show "$sha" 2>/dev/null | grep -qF "$TREASURE"; then found_stash=yes; break; fi
done
if [ "$found_stash" = yes ]; then
  record "stash created, then dropped" yes "git fsck --unreachable → git stash apply <sha>"
else
  record "stash created, then dropped" no "-"
fi

# ---------------------------------------------------------------- report
say "  SCENARIO                              OUTCOME      HOW"
say "  ------------------------------------- ------------ ----------------------------------------------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r outcome name how <<< "$r"
  printf '  %-37s %-12s %s\n' "$name" "$outcome" "$how"
done
say ""
say "  recovered: $PASS   gone: $FAIL"
say ""
say "  The dividing line is not how careful you were. It is whether the content ever"
say "  reached git's object store — which 'git add' does and editing a file does not."
say ""

# ---------------------------------------------------------------- 7
# The other half of the problem: one commit per session versus one per prompt.
say "  reverting one bad change out of a session"
say ""

new_repo one-big-commit
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf 'edit %s\n' "$i" >> "file$(( (i % 5) + 1 )).txt"
done
printf 'THE BAD ONE\n' >> file3.txt
git add -A; git commit -q -m "AI session"
files=$(git show --name-only --format= HEAD | grep -c '^file')
say "  one commit for the session:"
note "git revert HEAD  undoes $files files and 13 edits — including the 12 that were fine"

new_repo one-commit-per-prompt
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf 'edit %s\n' "$i" >> "file$(( (i % 5) + 1 )).txt"
  git add -A; git commit -q -m "prompt $i"
done
printf 'THE BAD ONE\n' >> file3.txt
git add -A; git commit -q -m "prompt 13 — the bad one"
bad=$(git rev-parse HEAD)
git revert --no-edit "$bad" >/dev/null 2>&1
if ! grep -qF 'THE BAD ONE' file3.txt && grep -qF 'edit 2' file3.txt && [ "$(git log --oneline | wc -l | tr -d ' ')" = "15" ]; then
  say "  one commit per prompt:"
  note "git revert $(git rev-parse --short "$bad")  undid exactly that change — the other 12 are untouched"
else
  say "  one commit per prompt: revert did not isolate the change"
fi
say ""
