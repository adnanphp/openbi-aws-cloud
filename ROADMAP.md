# Roadmap

Ten phases, one per focused session. Each phase pairs an infrastructure
tool with a Python library and investigates one shared concept.

| # | Infra tool | Python library | Concept | Status |
| --- | --- | --- | --- | --- |
| 1 | Docker | NumPy | Layering: image layers ↔ array strides/views | 🚧 |
| 2 | Git | pandas | Content-addressing ↔ indexed views | 📋 |
| 3 | Kubernetes | scikit-learn | Declarative specs ↔ estimator protocol | 📋 |
| 4 | Terraform | SQLAlchemy | Dependency graphs ↔ identity maps | 📋 |
| 5 | Kafka | FastAPI | Event streams ↔ request/response | 📋 |
| 6 | Airflow | PyTorch | DAG scheduling ↔ autograd graphs | 📋 |
| 7 | PostgreSQL | Pydantic | Relational constraints ↔ type validation | 📋 |
| 8 | Prometheus | asyncio | Time-series observation ↔ cooperative scheduling | 📋 |
| 9 | Spark | polars | Distributed lazy eval ↔ local lazy eval | 📋 |
| 10 | K8s Operators | LangGraph | Reconciliation loops ↔ state machine workflows | 📋 |

**Status legend:**

- 📋 planned
- 🚧 in progress
- ✅ complete

## What "complete" means

A phase is complete when:

1. The two experiments under `<infra>/` and `<python>/` are runnable from a clean checkout.
2. The `experiments/` directory records what was observed (measurements, screenshots, build logs) — not just what the docs say.
3. `reflection.md` is written in my own words and explicitly states **where the analogy holds and where it breaks down**.
4. The phase is committed with a clear message.

## Why the analogies are labelled as analogies

Some pairings compare genuinely similar mechanisms. Others compare different
mechanisms that share a shape. Each phase's reflection should make that
distinction explicitly, so the repo never overclaims.

## Pace

Roughly one phase per session. If a phase needs two sessions, that's fine.
The point is depth of understanding, not speed of completion.
