# Repository-driven Compose deployment

## Phase 3 staging design

The deployment artifact is selected by `scripts/compose-artifact.py` from the exact Git checkout. It includes only:

- `docker-compose.yml`;
- the eight `services/*.yml` stack files;
- tracked `services/data/**` files;
- `.sops.yaml` and the encrypted production environment manifests; and
- the deployment-only validation and layout helpers required on the host.

Git metadata, documentation, worktrees, plaintext environment files, recovery keys, and unrelated repository files are excluded. A plaintext `*.env` path or private-key candidate inside the selection is a hard failure.

The canonical artifact hash is SHA-256 over a version marker followed by each sorted UTF-8 filename and its raw bytes, both length-delimited. File timestamps, checkout paths, archive metadata, and runner-specific state do not affect the hash. CI proves that the source, copied artifact, and no-Git staged tree produce the same hash.

## Stable host paths

```text
/srv/docker-compose/current
/srv/docker-compose/staging/<artifact-sha256>
/srv/docker-compose/previous
/etc/docker-compose/production.env
/var/lib/docker-compose/deployed.sha256
```

`current` is the only future live project directory. Staging directories are immutable and hash-addressed. A GitHub Actions checkout is only a controller source; no live bind mount may reference it.

The existing `/home/docker/Projects/docker-compose` checkout and `.env` remain untouched rollback inputs until rollback confidence is documented.

## Staging workflow

`.github/workflows/compose-stage.yml` is manual, main-only, serialized with other production Ansible work, and uses the existing environment-bound `tag:ci-apply` identity. It:

1. checks out the exact `main` commit;
2. computes and copies the deterministic artifact on the controller;
3. reviews `stage-compose.yml --check --diff`;
4. copies only that artifact into a root-owned incoming host directory;
5. recomputes the hash before atomically publishing `staging/<hash>`;
6. decrypts SOPS only on the host through `/etc/sops/age/keys.txt`;
7. restores the non-secret dotenv layout in a root-only temporary directory;
8. atomically installs `/etc/docker-compose/production.env` as `root:root 0600` with `no_log: true`;
9. validates with explicit project name, project directory, environment file, and `docker compose config --quiet`;
10. writes root-owned secret-free desired and runtime inventories;
11. runs `docker compose --dry-run create --no-build --pull never`; and
12. requires a zero-change staging post-check and complete read-only audit.

This workflow does not run Compose pull, build, create, up, restart, removal, orphan removal, or volume operations. The normal staging execution is separately confirmation-gated even after entering the protected apply environment.

## Secret-free model evidence

`scripts/compose-model-inventory.py` captures resolved Compose JSON and Docker inspection data only in process memory, then emits a restricted model containing:

- project name and service/volume counts;
- image references and current image IDs;
- published ports;
- bind and named-volume sources and targets;
- devices;
- network modes and network names; and
- SHA-256 identities of health-check definitions.

It never emits environment values, resolved commands, labels, or the complete Compose model. The desired inventory resolves relative bind sources against `/srv/docker-compose/current`, not a temporary staging or GitHub checkout.

## Backup environment mount

The backup services now declare `/etc/docker-compose/production.env:/backup/.env:ro`. Existing containers continue using the old bind until the separately controlled cutover; no staging operation recreates them.

## Cutover boundary

Phase 3 may populate staging, the empty stable directories, and the inactive root-only environment file. It must not synchronize an artifact into `current`, change runtime Compose labels, pull images, or converge containers. Those actions remain Phase 4 maintenance-window work.
