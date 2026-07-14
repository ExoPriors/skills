# Access and runtime

Use `SCRY_API_KEY` from `~/.scry/.env`. Context and schema are readable
without a credential. If no account key is available, stop before querying
and direct the user to `https://scry.io/#console`.

```bash
set -a
[ -f "$HOME/.scry/.env" ] && . "$HOME/.scry/.env"
set +a
curl -s "https://api.scry.io/v1/scry/context?skill_generation=2026071401" \
  -H "Authorization: Bearer $SCRY_API_KEY"
curl -s https://api.scry.io/v1/scry/schema \
  -H "Authorization: Bearer $SCRY_API_KEY"
```

Raw SQL uses `POST /v1/scry/query` with `Content-Type: text/plain`. Use
`X-Scry-Max-Wait` when a synchronous wait needs a tighter bound. Consult
`/v1/scry/account`, `/v1/scry/pricing`, and `/v1/scry/estimate` before costly
work. Use receipts or shares when results must survive the current session.
