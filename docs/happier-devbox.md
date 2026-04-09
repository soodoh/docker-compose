# Happier Devbox

`happier-devbox` is included by default from `docker-compose.yml`. The only host-side setup is the root `.env` plus the SSH material mounted into the container.

## Required `.env` entries

Add these values to the root `.env` on the Docker host:

```dotenv
HAPPIER_SERVER_NAME=default
HAPPIER_SERVER_URL=https://api.happier.dev
HAPPIER_WEBAPP_URL=https://app.happier.dev
HAPPIER_SSH_KEY_PATH=/absolute/path/to/id_ed25519
HAPPIER_SSH_PUBLIC_KEY_PATH=/absolute/path/to/id_ed25519.pub
HAPPIER_SSH_KNOWN_HOSTS_PATH=/absolute/path/to/known_hosts
```

## First start

```bash
docker compose up -d --build happier-devbox
docker compose logs -f happier-devbox
```

If the container reports that Happier is not linked yet, authenticate from inside the devbox:

```bash
docker exec -it -u devbox happier-devbox bash
happier auth login
happier daemon start
happier daemon status
```

## GitHub verification

Check SSH auth, then clone a repository into `/workspace`:

```bash
docker exec -it -u devbox happier-devbox ssh -T git@github.com
docker exec -it -u devbox happier-devbox git clone git@github.com:OWNER/REPO.git /workspace/REPO
```

## Nested Docker smoke test

```bash
docker exec -it -u devbox happier-devbox docker run --rm hello-world
```

## Restart persistence check

Restart the service, then verify the workspace clone and nested Docker state are still present:

```bash
docker compose restart happier-devbox
docker exec -it -u devbox happier-devbox bash -lc "test -d /workspace/REPO/.git && docker image inspect hello-world >/dev/null"
```

## Cleanup

Prune nested Docker state from inside the devbox, without touching the host daemon:

```bash
docker exec -it -u devbox happier-devbox docker system prune -af --volumes
```

If you need to remove only the nested Docker storage volume, identify the single matching compose volume and delete it:

```bash
volume="$(docker volume ls --format '{{.Name}}' | rg '_happier-docker-data$' | head -n1)"
docker volume rm "$volume"
```
