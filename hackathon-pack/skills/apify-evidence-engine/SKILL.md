---
name: apify-evidence-engine
description: Discover, inspect, and integrate Apify Actors for source-backed web evidence; plan bounded runs, retrieve paginated results, or package a custom Actor. Use for Apify data extraction and automation, including hackathon prototypes.
---

Use Apify to turn a chosen data source into evidence the product can consume. It is a web extraction and automation platform; select an actual Actor rather than attributing finance or payment capabilities to Apify itself.

Start with the smallest useful evidence contract: source URL, observed timestamp, extracted fact, uncertainty, and the downstream decision it changes. Search for a suitable existing Actor unless the user names one. Compare its input fit, recent maintenance, documented output, pricing and permission model before choosing it. Popularity is a signal, not proof of fit.

Read [the operation guide](references/operations.md) for connection, discovery, bounded execution, results, and failure handling. Read [the starter-pack routes](references/starter-pack.md) when selecting Console, plugins, API/client, recurring collection, or a Cal Hacks submission path. Read [the Actor build guide](references/actor-build.md) when creating a reusable Actor rather than only consuming an existing one. Confirm current prize requirements separately before treating a published Actor as an eligible submission.

Use the bundled helpers from this skill's directory:

```sh
python3 scripts/apify_mcp.py
python3 scripts/apify_mcp.py --tool search-actors --arguments '{"keywords":"Amazon products","limit":2}'
python3 scripts/bounded_run.py --actor owner/actor --input /absolute/path/input.json --budget-usd 0.20 --max-items 5
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

The first helper permits only account-free discovery/docs tools. The second command family prints a plan by default; `--execute` starts an authenticated, potentially billable Actor run. Use execution only when the current task authorizes the data source and the explicit budget. A token is not spending authorization. Keep `APIFY_TOKEN` in the environment or secret store.

Keep Actor-specific input and platform run limits separate. Identical field names may validly exist in both namespaces: derive Actor fields from its fetched schema and send platform limits in `callOptions` for MCP or query options for REST. Never infer an Actor's schema from a similarly named Actor.

Carry run ID, dataset ID, build ID, input digest, fetch time, and original source links into provenance. A completed run can contain zero items. A dataset is evidence captured at a time, not a guarantee of present inventory or checkout price. Display cached and simulated data explicitly; revalidate material purchase facts through the merchant path.

Live validation of this package covered unauthenticated MCP discovery, search, and Actor details. Lifecycle and failure tests use offline doubles; authenticated Actor execution, cloud deployment, and production collection remain unverified until credentials and authorization are supplied.
