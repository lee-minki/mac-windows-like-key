#!/bin/bash
set -euo pipefail

mode=""
since=""
contains=""
input=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      mode="$2"
      shift 2
      ;;
    --since)
      since="$2"
      shift 2
      ;;
    --contains)
      contains="$2"
      shift 2
      ;;
    -h|--help)
      printf '%s\n' 'usage: scripts/filter-logs.sh --mode <trigger|verify|buffer|vdi|term> [--since HH:MM] [--contains TEXT] [file]'
      exit 0
      ;;
    *)
      input="$1"
      shift
      ;;
  esac
done

if [ -z "$mode" ]; then
  printf '%s\n' 'filter-logs: --mode is required' >&2
  exit 1
fi

case "$mode" in
  trigger)
    pattern='Trigger|right_command|Right Command|F16|toggle'
    ;;
  verify)
    pattern='verify|verification|input-source|retry|timeout|changed'
    ;;
  buffer)
    pattern='buffer|replay|hold|commitWindow|commit window|flush'
    ;;
  vdi)
    pattern='VDI|Horizon|Right Alt|F16|virtualization'
    ;;
  term)
    pattern='TERM|Claude|claude|terminal|tty|prompt|escape'
    ;;
  *)
    printf '%s\n' "filter-logs: unknown mode '$mode'" >&2
    exit 1
    ;;
esac

if [ -n "$contains" ]; then
  pattern="$pattern|$contains"
fi

if [ -n "$input" ]; then
  source_cmd=(cat "$input")
else
  source_cmd=(cat)
fi

"${source_cmd[@]}" |
  {
    if [ -n "$since" ]; then
      grep -F "$since" || true
    else
      cat
    fi
  } |
  grep -E "$pattern" || true
