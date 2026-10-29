# Install with the Installer Script

The installer script is the recommended way to install FLECS Core. It installs Docker if needed and starts FLECS with the latest versions.

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Prerequisites

* A device with an AMD64 or ARM64 processor: a PC, an industrial device or a virtual machine.
* Terminal access, through SSH or a connected keyboard and display.
* Root privileges. If you run the script as a regular user, it offers to restart itself with `sudo`.
* `bash`, and `curl` or `wget`.
* Internet access. To install without internet access, see [Offline Installation](offline.md).

## Supported platforms

| Operating system | Versions | Docker |
|---|---|---|
| Debian, Raspberry Pi OS | 12 (bookworm), 13 (trixie) | Installed automatically |
| Debian, Raspberry Pi OS | 11 (bullseye), end of life | Install Docker before running the script |
| Ubuntu | 20.04, 22.04, 24.04, 25.04, 26.04 | Installed automatically |
| Ubuntu | 23.04, end of life | Install Docker before running the script |
| Fedora | 37, 38 | Install Docker CE before running the script |
| Red Hat Enterprise Linux | 8.8, 9.2 | Install Docker before running the script |
| Arch Linux | Rolling release | Install Docker before running the script |

* If your version is newer than the listed ones, the script shows a warning and continues.
* If your version is older, the script stops.
* On other Linux distributions, such as Yocto-based systems, the script asks for confirmation and then attempts the installation. Docker must be installed beforehand.

FLECS requires Docker 20.10.10 or later with API version 1.41 or later. Podman is not supported.

When the script installs Docker, it uses the `docker.io` package of your distribution.

On Fedora, install Docker CE following the [Docker installation guide](https://docs.docker.com/engine/install/fedora/). Fedora's own `moby-engine` package does not work with FLECS while SELinux is enabled: SELinux blocks FILiP's access to the Docker socket, and FILiP restarts repeatedly. The installer script detects this and stops.

## Install FLECS

Open a terminal and run:

```bash
curl -fsSL install.flecs.tech | bash
```

To skip the confirmation prompts, for example in automated setups, add `--yes`:

```bash
curl -fsSL install.flecs.tech | bash -s -- --yes
```

For all options, see [Options](options.md). To install a specific version, see [Versions](versions.md).

### With the OpenTelemetry Collector

Add `--install-otel-collector` and the URL of your OTLP receiver:

```bash
curl -fsSL install.flecs.tech | bash -s -- \
  --install-otel-collector \
  --otel-export-destination https://otlp.example.com
```

For what the collector collects and which FLECS Core version it needs, see [OpenTelemetry Collector](options.md#opentelemetry-collector).

### What the script does

1. Checks your operating system and architecture.
2. Checks the internet connection.
3. Installs and starts Docker, if it is missing or not running.
4. Looks up the latest versions of FLECS Core and the FLECS WebApp.
5. Removes FLECS installations from versions before 5.2.0, which used Debian packages.
6. Starts the FILiP container `flecs`, which then starts all FLECS components.

The script does not reboot your device.

## Access FLECS

Open a browser and enter your device's IP address or hostname, for example `https://192.168.1.10`.

If port 443 was already in use during installation, FLECS uses port 8443 or 4443 instead, for example `https://192.168.1.10:8443`. See [Ports](index.md#ports).

The WebApp uses a self-signed certificate. Accept the security warning of your browser to continue.

Continue with the [Initial Setup](https://docs.flecs.tech/flecs-core/initial-setup/).

## Update FLECS

Run the installer script again:

```bash
curl -fsSL install.flecs.tech | bash
```

The script installs the latest versions and keeps your data and apps. Use the same options as for the original installation, for example `--http-port`.

!!! warning
    If you installed the OpenTelemetry Collector, pass `--install-otel-collector` and `--otel-export-destination` again. Without them, the update removes the collector.

Restarting the device or the `flecs` container does not update FLECS. The script installs fixed versions, which stay the same until you run the script again.

## Uninstall FLECS

!!! info
    Uninstalling FLECS stops and removes the containers of your apps, but keeps their data. If you install FLECS again, your apps are back with their data. To remove your apps completely, uninstall them in the FLECS WebApp first.

1. Stop and remove the FILiP container. FILiP stops and removes all other FLECS containers before it exits:

    ```bash
    docker stop --time 600 flecs
    docker rm flecs
    ```

    The `--time` option gives FILiP enough time to stop all containers.

2. Optionally, remove the FLECS data. This deletes your FLECS configuration, users and app data:

    ```bash
    docker volume rm flecsd flecs-floxy_certs flecs-floxy_data
    docker network rm flecs
    ```

    Depending on the FLECS version and your setup, more FLECS volumes exist:

    * `flecs-otelcol_certs` and `flecs-otelcol_logs`, if you installed the OpenTelemetry Collector.
    * `flecs-fence`, which holds your users, with FLECS Core 5.6.0 and later.
    * One volume per volume of each app, named `flecs-<instance ID>-<name>`. With FLECS Core 5.5.0, this includes the volume `flecs-<instance ID>-fence`, which holds your users.

    To remove them as well, list all remaining volumes whose names start with `flecs`. Check the list, then remove them:

    ```bash
    docker volume ls --filter name=^flecs
    docker volume ls --quiet --filter name=^flecs | xargs -r docker volume rm
    ```

3. Optionally, remove the Docker images of FLECS and your apps. List them with:

    ```bash
    docker image ls
    ```

    Then remove each image you no longer need with `docker image rm <image>`.

Docker itself stays installed.
