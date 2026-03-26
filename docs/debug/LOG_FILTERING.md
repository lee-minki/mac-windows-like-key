# Log Filtering

## Goal

Reduce token usage and speed up debugging by filtering logs before sharing them.

## Required Script

- `scripts/filter-logs.sh`

Current status:

- baseline script scaffold added

## Required Modes

- `trigger`
- `verify`
- `buffer`
- `vdi`
- `term`

## Required Inputs

- file path or stdin
- optional `--since`
- optional `--contains`

## Example Interface

```bash
scripts/filter-logs.sh --mode term --since "09:50" app.log
scripts/filter-logs.sh --mode trigger --contains "Right Command" app.log
```

## Output Rule

Output must be concise and suitable for direct sharing in chat or issue reports.

## Reference

- `../design/06_DEBUGGING.md`
