# recover-lab

[![Deploy on Back4app](https://img.shields.io/badge/Deploy%20on-Back4app-1568B8?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJMMiA3djEwbDEwIDUgMTAtNVY3eiIvPjwvc3ZnPg==)](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=recover-lab)

**Six ways to lose work, each one actually destroyed and then recovered.** One shell script, no dependencies. Every scenario runs in its own throwaway repository under a temporary directory — nothing you own is touched.

Measured on 27 October 2026 with git 2.54.0: **four of six came back, two were gone**, and the dividing line is a single command.

> **Read the article:** [How to Undo What an AI Assistant Broke, and What Back4app Rolls Back for You](https://www.back4app.com/blog/undo-what-an-ai-assistant-broke?utm_source=github&utm_medium=repo&utm_campaign=recover-lab)

## Run it

```bash
./recover.sh
```

## What it finds

```
  SCENARIO                              OUTCOME      HOW
  ------------------------------------- ------------ ----------------------------------------------
  committed, then reset --hard          RECOVERED    git reflog → git reset --hard HEAD@{1}
  edited only, then reset --hard        GONE         git fsck found no copy (dangling objects: 0)
  git add, then reset --hard            RECOVERED    git fsck --lost-found → git cat-file -p <blob>
  git checkout -- file                  GONE         nothing was ever written to the object store
  branch deleted with -D                RECOVERED    git reflog → the commit is still there
  stash created, then dropped           RECOVERED    git fsck --unreachable → git stash apply <sha>

  recovered: 4   gone: 2
```

Deterministic across three consecutive runs.

## The two findings

**1. `git add` is the safety net, not `git commit`.** Staging writes your file into the object store as a real object straight away. That object survives `reset --hard`, and `git fsck --lost-found` finds it. A change that only ever lived in the working file leaves nothing behind — we confirmed zero dangling objects.

Note which cases are which. A force-deleted branch and a dropped stash both come back; a quiet `git checkout -- file`, the gentlest command on the list, destroys work permanently.

**2. Where your commits fall decides what a revert costs.** The same thirteen edits, committed two ways:

| How it was committed | `git revert` undoes |
| --- | --- |
| one commit for the session | 5 files, 13 edits — 12 of which were fine |
| one commit per prompt | exactly the one change that broke it |

The boundaries have to be drawn before you know which change is the bad one, which is why "commit before each prompt" beats "commit after each feature".

## Deploy your own

1. **Create a free account.** Sign up at [https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=recover-lab](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=recover-lab).
2. **Keep your deploys versioned too.** Git protects your source; it does nothing for the build your users are hitting. A platform that keeps every deploy turns a bad release into a selection rather than a rebuild.
3. **Remember that rolling back code does not roll back data.** A reverted build leaves whatever the bad release wrote.

Documentation: [https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=recover-lab](https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=recover-lab).

## License

MIT.
