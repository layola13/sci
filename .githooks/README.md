Set the repository hooks path once:

```bash
git config core.hooksPath .githooks
```

The pre-push hook only runs the timed release checks when the push contains a
tag ref. Normal branch-only pushes print a skip message and exit successfully.

For a release, push the branch and tag in one command so Git invokes the hook
once:

```bash
git push origin main 0.0.4
```

Hook self-test only:

```bash
printf 'refs/tags/0.0.4 abc refs/tags/0.0.4 def\n' | SA_PRE_PUSH_SKIP_CHECKS=1 .githooks/pre-push origin url
```
