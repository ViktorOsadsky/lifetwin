# Build an Actor that can stand on its own

Choose a reusable job with a clear input/output boundary: a compatibility evidence extractor, policy-difference crawler, or product availability reconciler. The application should consume the resulting evidence rather than treating arbitrary web text as commands.

The included `assets/actor-template` is a local-first **snapshot normalizer**, not a crawler. It takes already captured page snapshots, extracts Product JSON-LD and writes provenance-bearing offer rows. This offers a useful transformation seam; add an authorized collection layer when the actual product needs one. A published wrapper with no differentiated work is weak evidence for a best-Actor prize.

For a fresh official Python scaffold, the documented command is:

```sh
apify create product-evidence --template python-start
```

Adapt the included normalizer core into that scaffold or copy the included template to the working project. `apify run` is local execution using local storage; `apify push` uploads/builds cloud code and requires account access plus user-authorized publication scope. Do not run publication or cloud jobs merely because this skill is invoked. [Official Python quick start](https://docs.apify.com/sdk/python/docs/quick-start).

Before publishing, provide:

- An input schema with meaningful defaults and bounded arrays/pages. An input schema is required for Store publication; `Actor.get_input()` reads the supplied input. [Input schemas](https://docs.apify.com/actors/development/actor-definition/input-schema).
- `.actor/actor.json`, executable entrypoint and dependency lock. The definition links input, Dockerfile, version and optional output/storage schemas. [Actor definition](https://docs.apify.com/actors/development/actor-definition/actor-json).
- A dataset contract documenting absent price/currency, multiple offers, capture time, source URL and content digest. Never silently treat unknown availability as available.
- Fixtures for malformed JSON-LD, multiple Product nodes, list/@graph layouts, unsupported offer shapes and missing prices; measure extraction recall and rejection quality on representative authorized pages.
- Source-specific request limits, robots/site permissions, safe URL handling, retries and caching when a real crawler is added. Keep local/private addresses and credentialed URLs outside a public ingestion Actor.
- A tested Store example, honest sample output, expected costs and limitations. Verify current event submission requirements; Actor publication and application submission are separate tasks.

Test the included core offline with `python3 assets/actor-template/extract.py --self-test`. Its SDK lifecycle and container build are provided as starter code but were not run against Apify in this package. Pin resolved dependencies after validating a real local SDK run; do not claim this template is deployed or cloud-tested.
