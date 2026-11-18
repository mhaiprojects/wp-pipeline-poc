# Production rollback record

Production rollback in this proof of concept is a **code-only redeploy of an
earlier annotated tag**. It does not move or rewrite tags, and it does not
rewind the database.

The existing release tags are left exactly as they were created:

| Tag | Points at | Meaning |
|---|---|---|
| `v0.1.0` | `033baf2` (merge of `feature/add-pipeline-demo`) | First release |
| `v0.2.0` | `376e954` (merge of `feature/v0.2.0-marker`) | Second release, "wave 2 banner" |

## Sequence that was verified (19 November 2026, AEDT)

1. `scripts/deploy-prod.sh v0.1.0` — production showed `PIPELINE_DEMO v0.1.0`.
2. `v0.2.0` was merged to `main`. Staging updated automatically via the
   post-receive hook. **Production stayed on `v0.1.0`** because production
   does not follow `main`.
3. `scripts/deploy-prod.sh v0.2.0` — production showed
   `PIPELINE_DEMO v0.2.0 ... — wave 2 banner`. Promoted page content was
   still present.
4. Rollback: `scripts/deploy-prod.sh v0.1.0`.

## Rollback verification (10:01 AEDT, Australia/Sydney)

- Production home and `/pipeline-poc-page/` showed
  `PIPELINE_DEMO v0.1.0 (plugin 0.1.0) on https://wp-prod.ddev.site`.
- No `v0.2.0` and no `wave 2 banner` text remained on production.
- Unique content `PIPELINE_POC_PAGE_DEV_2026-11-19` was still on the
  production page (the database was not rolled back).
- No leftover `wp-dev` or `wp-staging` hosts appeared on the production page.
- Staging remained on `v0.2.0`.
- The on-disk production tag file returned to `v0.1.0`.

After the demonstration, production was left on the rolled-back tag `v0.1.0`
so the rollback stayed visible. To move production forward again:

```bash
scripts/deploy-prod.sh v0.2.0
scripts/verify.sh prod v0.2.0
```

## How to roll back any later release

```bash
# Deploy the previous known-good tag (must already exist in origin.git):
scripts/deploy-prod.sh v0.1.0
scripts/verify.sh prod v0.1.0
```

Do not delete, move, or retarget `v0.1.0` / `v0.2.0`. A rollback is always a
fresh deploy of an existing tag.
