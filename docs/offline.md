# Offline Installation

This guide shows how to install or update FLECS on a device that has no internet access. On a second machine that is online, you download the installer and the container images into a folder, the *bundle*. You then copy the bundle to the offline device and run the installer there.

The steps are the same for every setup. Only **step 4, copying the bundle**, depends on how you can reach the device:

- **Option A: USB drive.** You have direct access to the device (keyboard and screen, or a serial console) and copy the bundle with a USB drive.
- **Option B: SSH and scp.** The device is not on the internet, but the online machine can reach it over a local network, for example a laptop connected to the device's LAN port. You copy the bundle with `scp` and run the commands over `ssh`.

```
 online machine                  transfer                       offline device
 ──────────────                  ────────                       ──────────────
 download filip.sh      ──────►  USB drive (A)       ──────►    docker load
 docker pull + save     ──────►  or scp (B)                     bash filip.sh ...
```

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Requirements

### Online machine

- Docker (any recent version)
- `curl`
- Option B only: an SSH client (`ssh`, `scp`) and a network route to the device

### Offline device

- Docker 20.10.5 or newer, already installed and running. In offline mode the installer does not install Docker. It stops if Docker is missing.
- `bash`, `sort` and `head` (these ship with every standard Linux distribution). `curl` and `wget` are not needed in offline mode.
- root access (`sudo`)
- enough free disk space for the loaded images, about the size of the bundle. With option B, the bundle itself is also copied to the device, so you need about twice the bundle size (check with `df -h ~`).
- Option B only: a running SSH server and a user account you can log in with

### USB drive (option A only)

- enough free space for the bundle (check with `du -sh flecs` after step 3)

## Part 1: Prepare the bundle (on the online machine)

### 1. Choose target architecture, whitelabel and versions

The images must match the CPU architecture of the **offline device**, not the machine you download on. Run `dpkg --print-architecture` or `uname -m` on the offline device to check it:

| Offline device reports | Use          |
|------------------------|--------------|
| `amd64` / `x86_64`     | `linux/amd64`|
| `arm64` / `aarch64`    | `linux/arm64`|

If you use a **whitelabel** (a customized FLECS web interface), you received a whitelabel name from FLECS. Every webapp release is also published with that name attached to its tag:

| | Standard webapp | Webapp with whitelabel `acme` |
|---|---|---|
| Image tag | `cr.flecs.tech/flecs/webapp:v5.4.0` | `cr.flecs.tech/flecs/webapp:v5.4.0-acme` |
| Installer options | `--webapp-version v5.4.0` | `--webapp-version v5.4.0 --whitelabel acme` |

The installer adds the `-acme` suffix itself. `--webapp-version` is therefore always the plain version, **without** the whitelabel suffix. There is no `latest-acme` or `acme` tag, so you always need an exact version.

Set these variables. They are used in all following steps:

```bash
PLATFORM=linux/arm64                  # or linux/amd64, see the table above
WHITELABEL=                           # your whitelabel name, e.g. WHITELABEL=acme
                                      # leave empty if you don't use a whitelabel

CORE_VERSION=$(curl -fsSL https://latest.flecs.tech/core)
WEBAPP_VERSION=$(curl -fsSL https://latest.flecs.tech/webapp)   # plain version, no suffix
WEBAPP_TAG=${WEBAPP_VERSION}${WHITELABEL:+-${WHITELABEL}}        # image tag, with suffix

echo "core: ${CORE_VERSION}  webapp: ${WEBAPP_VERSION}  whitelabel: ${WHITELABEL:-none}"
echo "webapp image tag: ${WEBAPP_TAG}"
```

With `WHITELABEL=acme`, the last line prints `webapp image tag: v5.4.0-acme` (the version depends on the current release).

To install specific versions instead of the latest ones, set `CORE_VERSION` and `WEBAPP_VERSION` to those versions (again without the whitelabel suffix) and run the `WEBAPP_TAG=` line again. See [Versions](versions.md) for where to find available versions.

### 2. Pull the images

```bash
IMAGES=(
  cr.flecs.tech/flecs/filip:latest
  cr.flecs.tech/flecs/flecs-core:${CORE_VERSION}
  cr.flecs.tech/flecs/floxy:0
  cr.flecs.tech/flecs/webapp:${WEBAPP_TAG}
)
# Optional, only if you use --install-otel-collector:
# IMAGES+=(cr.flecs.tech/flecs/otel-collector:0)

for IMAGE in "${IMAGES[@]}"; do
  docker pull --platform "${PLATFORM}" "${IMAGE}"
done
```

If a pull fails with `not found`, check the spelling of `WHITELABEL` and that `WEBAPP_VERSION` has no suffix.

!!! note "No webapp"
    If you install with `--webapp-version none`, leave out the webapp image.

### 3. Export the images and the installer into the bundle

This creates the bundle in a folder `flecs` in the current directory:

```bash
mkdir -p flecs

docker save --platform "${PLATFORM}" -o flecs/flecs-images.tar "${IMAGES[@]}"
curl -fsSL https://install.flecs.tech -o flecs/filip.sh

# Write versions and whitelabel down so the offline side installs exactly these
printf 'CORE_VERSION=%s\nWEBAPP_VERSION=%s\nWHITELABEL=%s\n' \
  "${CORE_VERSION}" "${WEBAPP_VERSION}" "${WHITELABEL}" > flecs/versions.env
cat flecs/versions.env
```

!!! info
    `--platform` makes sure the bundle contains only the images for your device. Without it, Docker's containerd image store saves every platform that is present locally, which can double the size of the bundle. The option needs Docker 28 or newer. With older Docker, leave it out.

### 4. Bring the bundle to the offline device

#### Option A: USB drive

Copy the bundle to the drive. Replace `/media/usb` with the path where your USB drive is mounted:

```bash
cp -r flecs /media/usb/
sync
```

Unmount the drive safely, remove it and plug it into the offline device. Find its mount point there (for example with `lsblk`; mount it with `sudo mount /dev/sdX1 /media/usb` if it is not mounted automatically). Then, **on the offline device**:

```bash
BUNDLE=/media/usb/flecs       # adjust to your mount point
```

#### Option B: SSH + scp

Replace `user@192.168.1.50` with the user and IP address of the offline device:

```bash
DEVICE=user@192.168.1.50
scp -r flecs "${DEVICE}:"
ssh "${DEVICE}"
```

The bundle is now in `~/flecs` on the device, and you are logged in to it. Run the following steps in this SSH session:

```bash
BUNDLE=~/flecs
```

!!! tip
    If the SSH connection is unstable, run the remaining steps inside `tmux` or `screen` (if installed), so a dropped connection does not interrupt the installer.

## Part 2: Install or update (on the offline device)

### 5. Load the images

```bash
docker load -i "${BUNDLE}/flecs-images.tar"
```

Check that the images are there:

```bash
docker image ls 'cr.flecs.tech/flecs/*'
```

### 6. Run the installer

```bash
source "${BUNDLE}/versions.env"

sudo bash "${BUNDLE}/filip.sh" --offline \
  --core-version "${CORE_VERSION}" \
  --webapp-version "${WEBAPP_VERSION}" \
  ${WHITELABEL:+--whitelabel "${WHITELABEL}"}
```

What the parts of this command do:

- **`--offline`** skips the internet connectivity check and the online lookup of the latest versions. It also stops the installer from trying to install Docker: if Docker is missing or not running, the installer stops with an error.
- **`--core-version` / `--webapp-version`** are required with `--offline`, because the installer cannot look up the latest versions. Use the versions you exported in step 3.
- **`${WHITELABEL:+--whitelabel …}`** adds `--whitelabel <name>` if `versions.env` contains a whitelabel, and nothing otherwise. With `WHITELABEL=acme`, the installer starts `cr.flecs.tech/flecs/webapp:v5.4.0-acme`.
- **`bash …`** runs the script without needing it to be executable, so it also works when the bundle is on a USB drive mounted `noexec`.

You can add any other installer option you normally use, for example `-y` for unattended mode or `--http-port`/`--https-port`. See [Options](options.md) for all options, and [With the OpenTelemetry Collector](#with-the-opentelemetry-collector) for the collector. Run `bash filip.sh --help` to see which options your copy of the installer supports.

### With the OpenTelemetry Collector

1. In step 2, add the collector image to the bundle by removing the `#` in front of the `IMAGES+=` line.
2. In step 6, add both collector options. Set `--otel-export-destination` to the URL of your OTLP receiver:

    ```bash
    sudo bash "${BUNDLE}/filip.sh" --offline \
      --core-version "${CORE_VERSION}" \
      --webapp-version "${WEBAPP_VERSION}" \
      ${WHITELABEL:+--whitelabel "${WHITELABEL}"} \
      --install-otel-collector \
      --otel-export-destination https://otlp.example.com
    ```

The collector needs a network connection to the OTLP receiver to export its data. For what the collector collects and which FLECS Core version it needs, see [OpenTelemetry Collector](options.md#opentelemetry-collector).

### 7. What you will see

The installer tries to pull the newest images, which fails offline. It reports this as a warning and continues with the images you loaded:

```
  Internet connectivity... skipped (--offline)
  Docker... ✅ 28.x.x (API 1.xx)
  Pulling latest image... ⚠
  Starting FLECS... ✅
```

The `flecs` container runs into the same thing when it starts the other FLECS containers. Its log shows lines like the following, which are expected:

```bash
docker logs flecs
# WARN  Reusing local copy of cr.flecs.tech/flecs/flecs-core:v5.x.x, failed to pull: ...
```

Check that everything is running:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

You should see `flecs`, `flecs-flecsd`, `flecs-floxy` and `flecs-webapp`, and `flecs-otelcol` if you installed the collector. With a whitelabel, `flecs-webapp` shows the whitelabel tag, for example `cr.flecs.tech/flecs/webapp:v5.4.0-acme`. After about 30 seconds, `flecs-flecsd` and `flecs-webapp` should report `(healthy)`.

## Updating an existing installation

An update uses exactly the same steps: prepare a bundle with the newer versions, bring it to the device, load the images, and run the installer again. The installer replaces the `flecs` container. The new one recreates the FLECS containers with the new images. Your data is stored in Docker volumes, so it is kept.

!!! warning
    If you installed the OpenTelemetry Collector, include its image in the new bundle and pass `--install-otel-collector` and `--otel-export-destination` again. Without them, the update removes the collector.

The switch happens a few seconds *after* the installer finishes, so for a short time `docker ps` still shows the old versions. Wait until `flecs-flecsd` shows the new version and `(healthy)`:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

After that, you can remove the old image versions to free disk space. Removing an image before the switch has finished fails with `conflict: ... container ... is using its referenced image`.

```bash
docker image ls 'cr.flecs.tech/flecs/*'
docker image rm cr.flecs.tech/flecs/flecs-core:<old-version>
```

## Uninstalling

Uninstalling works the same way as for an online installation. See [Uninstall FLECS](install.md#uninstall-flecs).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Unknown option: --offline` | The installer in the bundle is too old. Download it again in step 3. |
| `arguments --core-version and --webapp-version are required with --offline` | One of the two options is missing from the command. |
| `argument --core-version requires a value` (or `--webapp-version`) | `versions.env` was not sourced, so the variable is empty. Run the `source` line from step 6 first. |
| `argument --otel-export-destination is required with --install-otel-collector` | Add `--otel-export-destination` with the URL of your OTLP receiver. See [With the OpenTelemetry Collector](#with-the-opentelemetry-collector). |
| `permission denied while trying to connect to the Docker daemon socket` | Your user is not allowed to run Docker. Put `sudo` in front of the `docker` command. See [Docker command errors](troubleshooting.md#docker-command-errors). |
| `Docker is not installed or not running` | Install Docker on the device (for example from offline `.deb` packages) and start it, then run the installer again. |
| `flecs` stays in `Restarting`, and `docker logs flecs` shows `Failed to pull image … and no local copy exists` | An image is missing or has the wrong tag. Compare `docker image ls` with the list in step 2. The version tags must match exactly, including a leading `v`. |
| `flecs` stays in `Restarting`, and the log names a webapp tag with the whitelabel twice (e.g. `v5.4.0-acme-acme`) | `WEBAPP_VERSION` contains the whitelabel suffix. Set it to the plain version (`v5.4.0`) in `versions.env`. |
| `flecs` stays in `Restarting`, and the log names the plain webapp tag (e.g. `webapp:v5.4.0`) although you use a whitelabel | `--whitelabel` was not passed. Check that `versions.env` contains `WHITELABEL=<name>` and that you ran the `source` line from step 6. |
| `exec format error` | The images were pulled for the wrong architecture. Repeat step 1 with the correct `PLATFORM`. |
