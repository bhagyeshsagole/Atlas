#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUNC="openai-proxy"

if ! command -v supabase >/dev/null 2>&1; then
  echo "supabase CLI not found. Install from https://supabase.com/docs/reference/cli" >&2
  exit 1
fi

echo "Deploying Supabase Edge Function: ${FUNC}"
cd "$ROOT"

if ! supabase status >/dev/null 2>&1; then
  echo "Supabase project not linked in this repo. Link with:" >&2
  echo "  supabase link --project-ref <PROJECT_REF>" >&2
  exit 1
fi

supabase functions deploy "$FUNC"

SUPABASE_URL="$(supabase status | awk '/Supabase URL/ {print $3}')"
if [[ -n "${SUPABASE_URL:-}" ]]; then
  echo "Health check:" >&2
  echo "  curl -i ${SUPABASE_URL}/functions/v1/${FUNC}/health" >&2
fi
