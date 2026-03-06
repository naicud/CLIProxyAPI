#!/usr/bin/env bash
set -euo pipefail

# Script per testare il gateway CLIProxyAPI con curl
# La chiave API deve essere una di quelle configurate in api-keys del config
# (default Homebrew: your-api-key-1 / your-api-key-2 / your-api-key-3)
#
# Uso:
#   export API_KEY="your-api-key-3"   # api-key per /v1/* endpoints
#   export MGMT_KEY="..."             # management key (se configurata in secret-key)
#   ./test-gateway-curls.sh
#
HOST="${HOST:-http://localhost:8317}"
KEY="${API_KEY:-your-api-key-3}"
MGMT_KEY="${MGMT_KEY:-}"

echo "Testing gateway at $HOST (API key: $KEY)"
echo ""

echo "=== GET / (health check) ==="
curl -v "$HOST/" 2>&1 | grep -E "< HTTP|^{"
echo ""

echo "=== GET /v1/models ==="
curl -v -H "Authorization: Bearer $KEY" "$HOST/v1/models" 2>&1 | grep -E "< HTTP|^\{"
echo ""

echo "=== GET /v1/models (X-Api-Key) ==="
curl -v -H "X-Api-Key: $KEY" "$HOST/v1/models" 2>&1 | grep -E "< HTTP|^\{"
echo ""

echo "=== POST /v1/chat/completions (modello gemini-3-flash-preview) ==="
curl -s "$HOST/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash-preview","messages":[{"role":"user","content":"Rispondi con ok"}]}'
echo ""

echo "=== POST /v1/embeddings ==="
curl -s "$HOST/v1/embeddings" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Why is the sky blue?"}' || echo "(endpoint non disponibile)"
echo ""

echo "=== POST :11434/api/embed (Ollama locale) ==="
curl -s http://localhost:11434/api/embed \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma","input":"Why is the sky blue?"}' | head -c 200 || echo "(Ollama non raggiungibile)"
echo ""

if [ -n "$MGMT_KEY" ]; then
  echo "=== POST /v0/management/api-call (management key) ==="
  curl -sS -X POST "$HOST/v0/management/api-call" \
    -H "Authorization: Bearer $MGMT_KEY" \
    -H "Content-Type: application/json" \
    -d '{"method":"GET","url":"http://127.0.0.1:8317/v1/models"}'
  echo ""
else
  echo "(MGMT_KEY non impostata: skip management api-call)"
fi

echo ""
echo "Pannello management: $HOST/management.html"
