---
name: hackathon-ml-evals
description: Decide whether ML training is worthwhile for a hackathon task, build leakage-resistant evaluations, and run a small training experiment only when it improves a measured baseline. Use for model choice, fine-tuning, retrieval quality and agent reliability.
---

# Hackathon ML and evaluations

Turn “AI works” into a falsifiable claim. Define a task with observable labels or outcomes before selecting a model. For finance, deterministic money calculations and policy checks belong in code; the model handles uncertain extraction, interpretation and planning with evidence. For shopping, separate product identity, constraint matching, ranking and action correctness. A confident explanation cannot substitute for a correct match.

## Pick the cheapest informative baseline

Measure a deterministic heuristic, a pretrained model with a short prompt, and retrieval/structured output if relevant. Use the same examples and success criteria. Reach for training only when a repeatable failure remains and enough appropriate labeled examples, compute and evaluation time are available. Training is not a substitute for unavailable source data or sponsor credentials.

Choose metrics by failure cost. For exact-model compatibility, prioritize false-compatible errors and abstention quality. For finance extraction, score exact currency/amount/entity plus source agreement. For an agent, score complete task success, unauthorized action attempts, unnecessary actions, cost and latency. Report coverage alongside precision so an agent that always abstains cannot appear successful. Show the denominators. Evidence-ID overlap is only a citation selection check; entailment and source correctness need separate review.

## Keep the test independent

Split by underlying entity/document family/customer/product model, not by rows when variants share an identity. For forecasting use forward time splits; do not randomly mix future observations into training. Deduplicate before splitting and preserve a locked held-out set. Tune prompts, thresholds, retrieval or hyperparameters on development examples only. Never train on judge test cases and then report those cases as generalization.

Use [score_predictions.py](scripts/score_predictions.py) to compute local classification/abstention metrics and audit train/test group overlap. It validates an intentionally small JSON contract; it is not a model, a training run or a semantic truth oracle. Run `python3 scripts/test_metrics.py` to verify edge cases. For training setup and source links, read [training-decisions.md](references/training-decisions.md).

## If training earns its place

Specify base model revision and license, task/data provenance, split IDs, label policy, hardware and wall-clock/compute cap, seed, batch/context lengths, optimizer and checkpoint/artifact location. For a small label task try a simple classifier or embedding model before adapting a large generative model. For LoRA use the target model's actual module names and the pinned installed PEFT / Transformers versions; do not assume every model has the same attention projections. Check a tiny batch's loss and checkpoint reload before committing the time budget. Stop if the held-out improvement is absent, the failure shifts to data availability or the experiment threatens the working demo.

Keep the original baseline callable. Compare the final checkpoint and baseline on the same untouched test IDs, include task-specific severe errors, and report actual sample size, cost, latency and uncertainty. A lower training loss is not product improvement. Treat synthetic examples as synthetic; do not call synthetic-fixture accuracy evidence of field reliability. Deliver a reproducible evaluation command and results, including negative results.

## Iteration test

Exercise a correct model that omits hard examples, an always-abstaining model, duplicate predictions, an unseen group, and a group leaking across train/test. Inspect results, repair the data/metric/instruction causing the failure, and rerun the relevant fixtures. For a new skill or prompt, keep prior held-out failures as regressions while adding fresh blind cases. Record whether the evaluation was deterministic, human-reviewed, agent-reviewed or a real model run.
