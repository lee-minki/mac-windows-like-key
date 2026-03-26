# Workflow Rules

## Summary

- Trigger model: Right Command only
- Hook system: tracked `.githooks/`, not Husky by default
- Implementation style: TDD where feasible, explicit reproduction harness where not
- Docs: mandatory update in the same change for any user-visible or workflow-visible change

## References

- `../design/05_DEVELOPMENT_RULES.md`
- `../design/04_TASK_SYSTEM.md`

## Local Hook Setup Target

```bash
scripts/setup-hooks.sh
```

Equivalent manual command:

```bash
git config --local core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
```

## Minimum Workflow Gates

Tracked scripts in the repo:

- `.githooks/pre-commit`
- `.githooks/pre-push`
- `scripts/setup-hooks.sh`

### Before commit

- required docs updated if behavior/workflow changed
- fast checks pass
- stale Right Option / F19 relay text must not remain in user docs

### Before push

- build passes
- tests pass
- lint/format checks pass if those tools exist
- if no test target exists yet, the hook may skip tests but must still run build

Current baseline test command:

```bash
scripts/run-tests.sh
```

## TDD Rule

1. write scenario
2. write failing test or reproduction
3. implement minimal change
4. verify
5. update docs

## Disallowed Shortcuts

- do not skip docs
- do not add Right Option back implicitly
- do not claim F19/Caps Lock relay without proof
