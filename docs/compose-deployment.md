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
9. validates with explicit project name, immutable staging project directory, environment file, and `docker compose config --quiet`;
10. writes root-owned secret-free desired and runtime inventories;
11. runs `docker compose --dry-run create --no-build --pull never`; and
12. requires a zero-change staging post-check and complete read-only audit.

This workflow does not run Compose pull, build, create, up, restart, removal, orphan removal, or volume operations. The normal staging execution is separately confirmation-gated even after entering the protected apply environment.

### Completed staging evidence

Manual run [`30850160213`](https://github.com/soodoh/docker-compose/actions/runs/30850160213) staged and reviewed artifact `533ed4a14fce8a811a41ff0a3fe5e6b182fe485f965499d80d8f0c27cf79b357`. Its post-stage check reported `ok=5 changed=0 unreachable=0 failed=0`, the guarded model review reported `ok=7 changed=0 unreachable=0 failed=0`, and the complete audit reported `ok=45 changed=0 unreachable=0 failed=0` with all 41 containers still running.

The normalized model has identical service names, images, ports, volumes, devices, network modes, and network memberships. Five intentional bind-source changes remain for the stable-root migration: Caddy, Gluetun, LiteLLM, and the two backup services. The backup SSH source was explicitly preserved as `/home/docker/.ssh`; the two backup environment mounts change from the untouched checkout `.env` to the byte-verified root-only production environment file.

The exact no-pull/no-build dry run schedules recreation of those five services plus the eleven services sharing Gluetun's network namespace. It schedules no creates, removals, or volume operations. Ten health-check identity differences remain visible as hashed diagnostics; nine do not schedule any Compose action, while Gluetun is already accounted for by its bind-source migration. Nothing in this evidence authorizes the cutover.

## Secret-free model evidence

`scripts/compose-model-inventory.py` captures resolved Compose JSON and Docker inspection data only in process memory, then emits a restricted model containing:

- project name and service/volume counts;
- image references and current image IDs;
- published ports;
- bind and named-volume sources and targets;
- devices;
- network modes and network names; and
- SHA-256 identities of health-check definitions.

It never emits environment values, resolved commands, labels, or the complete Compose model. Compose resolves and dry-runs the immutable staged tree so every include and helper exists; the sanitized desired inventory then translates artifact-relative bind sources to `/srv/docker-compose/current`, never a temporary staging or GitHub checkout.

## Backup environment mount

The backup services now declare `/etc/docker-compose/production.env:/backup/.env:ro`. Existing containers continue using the old bind until the separately controlled cutover; no staging operation recreates them.

## Cutover boundary

Phase 3 may populate staging, the empty stable directories, and the inactive root-only environment file. It must not synchronize an artifact into `current`, change runtime Compose labels, pull images, or converge containers. Those actions remain Phase 4 maintenance-window work.
