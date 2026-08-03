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
/etc/docker-compose/staging/<artifact-sha256>.env
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
8. atomically installs an inactive `/etc/docker-compose/staging/<artifact-sha256>.env` as `root:root 0600` with `no_log: true`;
9. validates with explicit project name, immutable staging project directory, candidate environment file, and `docker compose config --quiet`;
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

Staging may populate hash-addressed artifacts and inactive root-only candidate environment files. It never overwrites the active `/etc/docker-compose/production.env`, synchronizes an artifact into `current`, changes runtime Compose labels, pulls images, or converges containers.

The Phase 4 implementation is fail-closed and inactive by default. `.github/workflows/compose-cutover.yml` requires all of the following before its job can run:

- repository variable `COMPOSE_CUTOVER_ENABLED=true`;
- the protected `infrastructure-apply` environment;
- `main` at the exact reviewed artifact commit;
- the exact 64-character staged artifact hash;
- typed confirmation `cutover:<artifact-sha256>`; and
- a zero-change full audit plus a check-mode plan that proposes exactly the 16 reviewed recreations and no creates or removals.

The role copies the already immutable artifact into the previously empty `current` directory, recomputes its hash, and runs only `docker compose up --detach --no-build --pull never` with explicit project name, project directory, environment file, and Compose file. It never passes `--remove-orphans`. A successful run requires an idempotent post-cutover dry run, all 41 services running, healthy Gluetun and Seerr, and a zero-change full audit before recording the deployed hash.

There is no automatic rollback. A failure intentionally leaves the persistent production lock in place for inspection. The untouched `/home/docker/Projects/docker-compose` checkout and `.env` remain the initial rollback inputs. `.github/workflows/compose-rollback.yml` is separately disabled behind `COMPOSE_ROLLBACK_ENABLED=true`, requires typed `rollback:<deployed-artifact-sha256>` confirmation and another protected-environment approval, and applies the same no-pull/no-build/no-removal constraints. Lock removal after a failed operation is always a separate reviewed action.

## Completed initial cutover

The first authorized attempt, run [`30853421473`](https://github.com/soodoh/docker-compose/actions/runs/30853421473), stopped immediately after creating the production lock because its owner metadata referenced an unavailable Ansible variable. It executed no Docker command. Independent audit [`30853571318`](https://github.com/soodoh/docker-compose/actions/runs/30853571318) then reported `ok=45 changed=0 unreachable=0 failed=0`. The empty lock remained fail-closed until separately authorized clearance run [`30853977059`](https://github.com/soodoh/docker-compose/actions/runs/30853977059) inspected and removed only that directory.

Authorized retry [`30854028095`](https://github.com/soodoh/docker-compose/actions/runs/30854028095) deployed artifact `533ed4a14fce8a811a41ff0a3fe5e6b182fe485f965499d80d8f0c27cf79b357`:

- pre-cutover audit: `ok=45 changed=0 unreachable=0 failed=0`;
- exact plan: `ok=22 changed=1 unreachable=0 failed=0`, with the expected 16 recreations and zero forbidden create/remove actions;
- cutover and health verification: `ok=35 changed=3 unreachable=0 failed=0`;
- post-cutover action plan: no further convergence proposed;
- post-cutover audit: `ok=45 changed=0 unreachable=0 failed=0`.

All temporary enable variables were removed after use. Cutover, failed-lock clearance, and rollback are disabled. `/srv/docker-compose/current` and `/etc/docker-compose/production.env` are now active, while the legacy checkout and `.env` remain untouched rollback inputs.

## Protected ongoing deployment

`.github/workflows/compose-deploy.yml` is the post-cutover deployment path. Pull requests remain secret-free and unprivileged: `compose-artifact.yml` validates and hashes the exact candidate without contacting the host. After a reviewed merge, the trusted `main` workflow may use the protected apply identity to stage the exact artifact and its isolated candidate environment, display the restricted model differences, and produce a hash-locked check-mode deployment plan.

The apply job is independently disabled unless `COMPOSE_AUTO_APPLY_ENABLED=true`. A changed merged plan must still match the current `main` tip and reproduce the complete plan hash. Deployment refuses service additions/removals, Docker create/remove actions, and `services/data/**` changes that lack an explicit restart decision. It pulls only services whose reviewed image reference changed, preserves current as `previous` plus a root-only previous environment, rotates the hash-verified artifact before Docker convergence, and runs Compose without builds or orphan removal. No image or volume pruning occurs.

Every apply attempt retains the production lock on failure. Success requires an idempotent post-deployment Compose action plan, all 41 services running, healthy Gluetun and Seerr, a zero-change deployment post-check, and a zero-change complete audit. There is no automatic stateful rollback; the tracked previous artifact and environment are recovery inputs for a separately reviewed rollback.

### Renovate canary lane

The automatic apply lane is initially restricted to `flaresolverr`, a stateless service without a Compose-managed volume. A candidate is canary-eligible only when all checks agree that:

- the candidate changes exactly `services/servarr.yml`;
- `flaresolverr` is the only image-reference difference;
- `flaresolverr` is the only proposed recreation;
- no stateful service, service-set change, create/remove action, secret file, or `services/data/**` path is involved; and
- the candidate and active artifact identities are exact.

All other Compose changes still produce a protected plan but report zero effective automatic changes, so the apply job cannot start. Renovate Docker updates are ungrouped, have a minimum release age, and default to `automerge: false`; the Flaresolverr package receives the `compose-canary` label and a seven-day release age.

The canary lane was explicitly authorized. Flaresolverr alone may use platform PR automerge, including pinning its readable tag to an immutable digest, but the default-branch ruleset requires the repository's `Hash and copy exact Compose artifact` status first. That unprivileged check now runs on every pull request, so path filtering cannot leave the required status absent. `COMPOSE_AUTO_PLAN_ENABLED=true` stages and plans trusted merged commits; `COMPOSE_AUTO_APPLY_ENABLED=true` permits only candidates that pass the hard-coded canary policy above. No other Renovate or human Compose change can enter the automatic apply block.
