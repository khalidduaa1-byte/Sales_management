#!/usr/bin/env bash
# Set a BA's password immediately (no reset email). Uses Supabase Admin API.
#
# 1. Supabase → Project Settings → API → copy "service_role" (secret — never commit it).
# 2. Run:
#      export SUPABASE_SERVICE_ROLE_KEY='your-service-role-key'
#      ./scripts/set_ba_password.sh beshernasr6@gmail.com 'PickAStrongTempPass1!'
#
# Besher (default if you only pass password):
#      ./scripts/set_ba_password.sh '' 'PickAStrongTempPass1!'
#   or with explicit user id:
#      ./scripts/set_ba_password.sh cc619b38-1ed0-4b3c-b774-23a4087cc9a2 'PickAStrongTempPass1!'
#
# Do NOT create a new Auth user — sales are linked to the existing account.

set -euo pipefail

PROJECT_URL="${SUPABASE_URL:-https://tnxkstouapfcjoboymnf.supabase.co}"
BESHER_USER_ID="cc619b38-1ed0-4b3c-b774-23a4087cc9a2"
BESHER_EMAIL="beshernasr6@gmail.com"

KEY="${SUPABASE_SERVICE_ROLE_KEY:?Export SUPABASE_SERVICE_ROLE_KEY first (service_role from Supabase → Settings → API).}"

ident="${1:-$BESHER_USER_ID}"
password="${2:-}"

if [[ -z "$password" ]]; then
  echo "Usage: SUPABASE_SERVICE_ROLE_KEY=... $0 [user_id_or_email] 'NewPassword'" >&2
  exit 1
fi

if [[ "$ident" == "$BESHER_EMAIL" || -z "$ident" ]]; then
  ident="$BESHER_USER_ID"
fi

payload=$(jq -n --arg p "$password" '{password: $p, email_confirm: true}')

resp=$(curl -sS -w "\n%{http_code}" -X PUT "${PROJECT_URL}/auth/v1/admin/users/${ident}" \
  -H "apikey: ${KEY}" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload")

body=$(echo "$resp" | sed '$d')
code=$(echo "$resp" | tail -n 1)

if [[ "$code" != "200" ]]; then
  echo "Failed (HTTP ${code}):" >&2
  echo "$body" >&2
  exit 1
fi

echo "OK — password updated for user ${ident}."
echo "They can sign in at: https://sales-management-phi-blue.vercel.app"
echo "Email: ${BESHER_EMAIL}"
echo "Tell them the password by phone; do not paste service_role or password in group chat."
