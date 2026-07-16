# Server setup

## Cronjobs

```sh
sudo pacman -Syu cronie
sudo systemctl enable --now cronie.service
sudo crontab -e
```

Then, add this to the root's crontab (it will clean up old docker images, running every Sunday at 4AM machine local time).

```cron
0 4 * * 0 { date; /usr/bin/docker system df; /usr/bin/docker system prune --all --force --filter "until=168h"; /usr/bin/docker system df; } >> /var/log/docker-prune.log 2>&1
```
