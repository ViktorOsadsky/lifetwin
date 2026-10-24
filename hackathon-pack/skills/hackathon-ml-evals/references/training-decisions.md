# Training decisions and evidence

Checked 2026-10-23. Recheck installed versions when implementing.

[Hugging Face Transformers fine-tuning](https://huggingface.co/docs/transformers/training) is the maintained Trainer entry point. [PEFT quicktour](https://huggingface.co/docs/peft/en/quicktour) explains adapter-based training. [LoRA reference](https://huggingface.co/docs/peft/main/package_reference/lora) describes low-rank adapters; the `main` docs can differ from a stable installation. [GroupShuffleSplit](https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.GroupShuffleSplit.html) is a standard option for entity-grouped splits. These are technical references, not proof that training will help a particular hackathon project.

## Practical decision

| Bottleneck | Experiment | Avoid |
|---|---|---|
| Wrong arithmetic or threshold | Deterministic validators | Fine-tuning arithmetic behavior |
| Missing current facts | Retrieve primary facts and track provenance | Memorizing a changing catalog |
| Repeated small classification task | Heuristic / embedding / small supervised classifier | Assuming a generative LLM is required |
| Consistent extraction failure with sufficient labels | Structured prompting, then small adapter experiment | Unmeasured GPU work |
| UI waits on long model calls | Measure streaming, caching and smaller models | Training before latency profiling |
| Product identity uncertain | Abstain and request exact model evidence | Invented compatibility confidence |

## Local scoring contract

Gold JSON: `[{"id":"a","label":"compatible","group":"model-1"}, ...]`.
Predictions JSON: `[{"id":"a","label":"compatible"}, ...]`; `null` label means abstain. Every gold ID needs one prediction. Missing IDs are reported and count as abstentions, never silently dropped. Extra or duplicate IDs are errors. Class labels must be nonempty strings; gold groups are required for split audits. Metrics are exact-label micro results on this fixture, not calibrated probabilities.

For a split audit supply train and test arrays to `audit_groups(train, test)`. Passing this test prevents explicit group overlap; it does not discover semantic duplicates under different IDs. Audit source documents and near-duplicates separately. Avoid a changing label taxonomy between model runs.

## Honest finish

An evaluation table should say: baseline / candidate version; data source; N test examples; group split; task success; severe errors; coverage; accepted-prediction accuracy; latency; actual spend; and which part is synthetic. Real demand, commercial viability and live provider integration are separate claims.
