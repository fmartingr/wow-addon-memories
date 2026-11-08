# Self-host the website

One Docker image runs the server. `deploy/` has a compose file that runs it behind Caddy, which gets the HTTPS
certificate. The same image runs `wowjourney.xyz` or your own site. A player points the WoW Journey app at your
address in the Website settings.

## Requirements

- A VPS or any host that runs Docker Engine 28 or newer with the Compose plugin. Older engines let a machine on the
  same network reach the ports of a container directly, the admin port too.
- 2 GB of memory is a safe minimum: a full-size upload takes about 800 MB while the server handles it, and the server
  handles 2 at a time by default.
- A disk with room for the data. One player's screenshots are about 1 MB each, and a key may hold 5 GiB of them by default.
- A domain name with a DNS record that points to the host.
- The ports 80 and 443 open to the internet. Caddy needs both to get and renew the certificate.
- A copy of this repository on the host. The image is built from it.

## First start

1. Go to the `deploy/` folder and copy the settings file:

   ```sh
   cd deploy
   cp .env.example .env
   ```

2. Edit `.env`. Set `MEMORIES_DOMAIN` to your domain and `MEMORIES_SITE_URL` to `https://` plus the same domain.
   Set `MEMORIES_GITHUB_URL` if your repository has another address.
3. Start it:

   ```sh
   docker compose up -d --build
   ```

4. Open `https://<your domain>/`. The home page shows. The first start takes a minute, because Caddy asks for the
   certificate. If the page does not show, run `docker compose logs caddy server`.

To try the setup on your own computer, set `MEMORIES_DOMAIN=localhost` and `MEMORIES_SITE_URL=https://localhost`.
Caddy then uses a certificate of its own, and your browser asks you to trust it.

## The admin page

**The admin page has no login. Anybody who reaches its port can approve keys, make invite codes and delete characters.
Publish the port on `127.0.0.1` only. `deploy/compose.yaml` does this with `"127.0.0.1:8081:8081"`. Never change it to
`"8081:8081"` or `"0.0.0.0:8081:8081"`, and never open the port in a firewall or a cloud security group.** The server
checks the `Host` header, but a remote client can send any `Host` header, so the check does not protect a port that
is open to the internet. The server logs a warning at start because inside Docker it listens on `0.0.0.0:8081`;
that is expected. Only the host mapping keeps it private.

Reach the page with an SSH tunnel from your computer:

```sh
ssh -L 8081:127.0.0.1:8081 <user>@<host>
```

Leave that session open and open `http://127.0.0.1:8081/` in your browser. Use the local port 8081: the server accepts
only `localhost:8081` and `127.0.0.1:8081` as the address of the page, and a tunnel on another local port gets a
403 error.

On the admin page you can:

- **Invites:** make and revoke invite codes.
- **Requests:** approve or deny the screenshot requests of keys.
- **Keys:** revoke a key, revoke a key and delete its characters, or revoke only its screenshots.
- **Characters:** search by path or GUID, delete a character, or move its claim to another key.

## Make the first invite

1. Open the admin page through the tunnel.
2. Go to Invites, write a note (for example the name of the player) and choose the days it stays valid. The default is 30.
3. Select Create. The code shows once, on the page after you create it. Copy it then.
4. Give the code to the player. The player enters it in the app, in Settings, Website, when registering. A code works
   once.

## Open registration

To let any player register with no code, set this in `.env` and restart the server:

```sh
MEMORIES_REGISTRATION=open
```

Registering still gives a key with no screenshot approval. Open registration is for a small site among friends. On a
public site keep `invite`.

## Settings

Put each setting in `deploy/.env`. An unset or empty one takes its default, and a bad value stops the server with a
message that names the variable. After a change run `docker compose up -d`.

The image sets `MEMORIES_WEB_DIR`, `MEMORIES_DATA_DIR` and `MEMORIES_ADMIN_ADDR` itself, and the compose file sets
`MEMORIES_TRUSTED_PROXIES`. Do not set them in `.env`.

| Variable | Default | Meaning |
|---|---|---|
| `MEMORIES_DOMAIN` | `localhost` (compose) | The domain Caddy serves. Read by Caddy, not by the server. |
| `MEMORIES_PUBLIC_ADDR` | `:8080` | Public listener. Caddy sends requests to port 8080 of the server, so keep it. |
| `MEMORIES_ADMIN_ADDR` | `0.0.0.0:8081` (image) | Admin listener. Outside Docker the default is `127.0.0.1:8081`. |
| `MEMORIES_DATA_DIR` | `/data` (image) | Data folder: `memories.db` and `characters/`. It is the volume `data`. |
| `MEMORIES_WEB_DIR` | `/app/web` (image) | Folder with the viewer files. |
| `MEMORIES_SITE_URL` | `http://localhost:8080` | Public address of the site: `http` or `https`, no path. |
| `MEMORIES_SITE_NAME` | `WoW Journey` | Name of the site. |
| `MEMORIES_GITHUB_URL` | `https://github.com/fmartingr/wow-addon-memories` | Repository. The home page links to it and to its `/releases/latest`. |
| `MEMORIES_REGISTRATION` | `invite` | `invite` or `open`. |
| `MEMORIES_TRUSTED_PROXIES` | `172.30.60.0/24,fd00:30:60::/64` (compose) | Proxies whose `X-Forwarded-For` the server trusts: the IPv4 and IPv6 subnets of the compose network, which has Caddy as its only proxy. Without it, every player has the address of Caddy and shares one rate limit. |
| `MEMORIES_MAX_UPLOAD_BYTES` | 16 MiB | Largest upload request. |
| `MEMORIES_MAX_SHOT_BYTES` | 15 MiB | Largest screenshot request. |
| `MEMORIES_MAX_PIXELS` | 50,000,000 | Largest screenshot, in pixels. |
| `MEMORIES_MAX_DECODED_BYTES` | 64 MiB | Largest upload after gzip is undone. |
| `MEMORIES_MAX_TEXT` | 512 | Longest text value in an upload, in bytes. |
| `MEMORIES_MAX_RECORDS` | 500,000 | Journey records in one upload. |
| `MEMORIES_MAX_CHUNKS` | 50,000 | Trail chunks in one upload. |
| `MEMORIES_MAX_POINTS` | 20,000 | Points in one trail chunk. |
| `MEMORIES_MAX_CHARACTERS_PER_KEY` | 50 | Characters of one key. |
| `MEMORIES_MAX_DATA_BYTES_PER_KEY` | 512 MiB | Journey data of one key. |
| `MEMORIES_MAX_SHOT_BYTES_PER_KEY` | 5 GiB | Screenshots of one key. |
| `MEMORIES_MAX_CONCURRENT_UPLOADS` | 2 | Uploads handled at the same time. A full-size upload takes about 800 MB of memory. |
| `MEMORIES_RATE_SIGNED_PER_MINUTE` | 120 | Signed requests a minute for one key. |
| `MEMORIES_RATE_REGISTER_PER_HOUR` | 10 | Registrations an hour from one IP. |
| `MEMORIES_RATE_PUBLIC_PER_MINUTE` | 600 | Requests a minute from one IP to the public listener. |

## The data volume

The server keeps everything in the Docker volume `data`, mounted at `/data`: the database `memories.db` and the
folder `characters/`. The image runs as the user `nonroot` (user ID 65532) and has no shell. A new named volume
takes its owner from the image, so the server can write to it with no extra step.

If you replace the volume with a folder of the host (a bind mount), give the folder to that user first, or the server
stops at start with `could not open the database /data/memories.db: ... permission denied`:

```sh
sudo chown -R 65532:65532 /srv/memories-data
sudo chmod 700 /srv/memories-data
```

## Backup

The backup runs while the server runs. It writes `memories.db` as a consistent copy, then copies the `characters/`
folder. It refuses a folder that exists and a folder inside `characters/`.

```sh
docker compose exec server /app/memories-server backup /data/backup-$(date +%F)
```

The folder is inside the volume, so it is not safe from a disk failure yet. **Copy it off the host.** `docker compose cp`
reads the files through Docker, and the copy on the host belongs to the user who runs it. Run it as root, so that only
root can read the copy of the keys and the characters:

```sh
sudo mkdir -p /var/backups/memories
sudo docker compose cp server:/data/backup-2026-11-08 /var/backups/memories/backup-2026-11-08
```

Then move that folder to another machine or to cloud storage. Delete the copy in the volume when you no longer need it.
The image has no shell, so use a short-lived container:

```sh
docker run --rm -v deploy_data:/data alpine rm -rf /data/backup-2026-11-08
```

The volume name is the name of the folder that holds `compose.yaml`, plus `_data`. Run `docker volume ls` to check it.

### Daily backup with cron

Save this as `/usr/local/bin/memories-backup`, make it executable, and run it from the cron of root, for example
`0 3 * * * /usr/local/bin/memories-backup`:

```sh
#!/bin/sh
set -eu
cd /opt/wow-addon-memories/deploy
name="backup-$(date +%F)"
mkdir -p /var/backups/memories
docker compose exec -T server /app/memories-server backup "/data/$name"
docker compose cp "server:/data/$name" "/var/backups/memories/$name"
docker run --rm -v deploy_data:/data alpine rm -rf "/data/$name"
# Then copy /var/backups/memories off the host, for example with rsync or rclone.
```

The database is a snapshot of one moment. The character files are copied right after it, so they can be a little newer.
That is safe: the next upload of each player merges into them. A character first uploaded after the snapshot is left
out; its next upload after a restore sends it again.

## Restore

1. Stop the server and Caddy. This keeps the volumes:

   ```sh
   cd deploy
   docker compose down
   ```

2. Remove the old data volume, or skip this step on a new host:

   ```sh
   docker volume rm deploy_data
   ```

3. Fill a new data volume with the backup. Change the path of the backup to yours:

   ```sh
   docker volume create deploy_data
   docker run --rm -v deploy_data:/data -v /var/backups/memories/backup-2026-11-08:/backup:ro alpine \
     sh -c 'cp -a /backup/. /data/ && chown -R 65532:65532 /data && chmod 700 /data'
   ```

4. Start again with `docker compose up -d`. Open a character page to check it.

The keys, the claims and the characters are back as they were at the backup. Invite codes that you made after the
backup are gone.

## If the data is lost

A backup is not the only copy. Each player's `latest/` folder is the source of truth. When the data is gone and there
is no backup, start an empty server, make invites, and ask the players to register again and use Upload now in the app. Each
upload sends the whole `latest/` of a character, so the character pages come back. Screenshots come back after you
approve the new key again. Each player's key is new, so each player needs an invite.

## Update

1. Pull the new version of the repository.
2. Run `docker compose up -d --build` in `deploy/`.

**Deploy the server before you release an addon version that adds kinds.** The server accepts an unknown kind with a
strict generic check, but only an updated server checks the new kind by its fields.

## A player lost their key

A player who reinstalls or changes computer loses the private key, and cannot upload their characters any more. To fix it:

1. The player registers a new key in the app. In invite mode, make a new invite for it.
2. On the admin page, go to Keys and find the new key. Note its fingerprint (the first 16 characters of the key hash).
3. Go to Characters, search the character path, and use Move claim with the new fingerprint. Do this for each character.
4. Revoke the old key if the player cannot find it again.

The player can then upload each character with the new key.
