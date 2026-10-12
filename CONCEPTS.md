# Concepts

Each row: the tool, the abstract concept it teaches, and where that
concept appears elsewhere.

| Tool | Concept | Also appears in |
| --- | --- | --- |
| Docker | Layered filesystems; content-addressable storage | Git, Nix, OverlayFS, container registries |
| Git | Merkle trees; immutable append-only history | IPFS, blockchain, Cassandra's commit log |
| Kubernetes | Declarative reconciliation loops | Terraform, Ansible, operators, controllers |
| Terraform | Dependency DAGs; state reconciliation | Make, Airflow, Bazel, `systemd` |
| Kafka | Log-structured storage; replayable append-only log | PostgreSQL WAL, etcd raft log, Ethereum |
| Airflow | DAG scheduling; topological execution | Spark DAG, Bazel, `make -j` |
| PostgreSQL | Relational algebra; constraints as invariants | SQL, Datalog, query optimizers |
| Prometheus | Time-series as a first-class data model | InfluxDB, TimescaleDB, metrics in general |
| Spark | Distributed lazy evaluation | pandas, polars, TensorFlow graph mode |
| NumPy | Strided memory views | TensorFlow tensors, PyTorch tensors, BLAS |
| pandas | Labeled columnar data; index alignment | R data.frames, polars, Arrow |
| scikit-learn | Uniform estimator protocol (`fit`/`predict`/`transform`) | PyTorch, Keras, XGBoost |
| SQLAlchemy | Identity map + unit of work | Hibernate, Django ORM, ActiveRecord |
| FastAPI | Type-driven validation + dependency injection | Pydantic, Flask with marshmallow, Django REST |
| PyTorch | Computation graphs with autograd | TensorFlow, JAX, Theano |
| Pydantic | Runtime type enforcement at the boundary | TypeScript, Zod (JS), Cerberus |
| asyncio | Cooperative scheduling via event loop | Node.js, Go's goroutines (different model) |
| polars | Columnar lazy query execution | DuckDB, Spark, Dask |
| LangGraph | State machines as graphs | Airflow, Kubernetes operators, Temporal |

## Note on completeness

This map grows as phases are completed. Rows for tools not yet covered are
here for planning; they'll be expanded when the corresponding phase is written.
