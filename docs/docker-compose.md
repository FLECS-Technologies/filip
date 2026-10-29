# Install with Docker Compose

If you manage your containers with Docker Compose, you can start the FILiP container from a Compose file instead of using the installer script. FILiP then installs FLECS the same way as the script does.

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Prerequisites

* Docker 20.10.10 or later, with API version 1.41 or later.
* Docker Compose 2.0.0 or later.
* Internet access to pull the images.

## Install FLECS

Create a `docker-compose.yml` file:

```yaml
services:
  flecs:
    image: cr.flecs.tech/flecs/filip:latest
    container_name: flecs
    restart: always
    network_mode: host
    stop_grace_period: 10m
    volumes:
      - /run/docker.sock:/run/docker.sock
    environment:
      VERSION_CORE: 5.5.0
      VERSION_WEBAPP: 5.4.1
```

Set `VERSION_CORE` and `VERSION_WEBAPP` to the versions you want to install. See [Versions](versions.md). For more settings, such as ports, see [Options](options.md).

!!! warning
    Always set both versions. Without them, FLECS updates itself to the latest version every time the container or the device restarts.

Start FLECS:

```bash
docker compose up -d
```

### With the OpenTelemetry Collector

Add two variables to `environment:` and set `OTEL_EXPORT_DESTINATION` to the URL of your OTLP receiver. Both are required. Without `OTEL_EXPORT_DESTINATION`, the collector restarts repeatedly and exports nothing:

```yaml
    environment:
      VERSION_CORE: 5.5.0
      VERSION_WEBAPP: 5.4.1
      INSTALL_OTEL_COLLECTOR: 1
      OTEL_EXPORT_DESTINATION: https://otlp.example.com
```

Then run `docker compose up -d` again. For what the collector collects and which FLECS Core version it needs, see [OpenTelemetry Collector](options.md#opentelemetry-collector).

### Why these settings are needed

* `network_mode: host` lets FILiP find free ports and a free subnet for the `flecs` network.
* The Docker socket lets FILiP manage the other FLECS containers.
* `restart: always` starts FLECS when the Docker daemon starts, for example after a reboot. Make sure Docker itself starts on boot.
* `stop_grace_period: 10m` gives FILiP enough time to stop all FLECS containers.

## Access FLECS

Open a browser and enter your device's IP address or hostname. See [Access FLECS](install.md#access-flecs).

## Update FLECS

Change `VERSION_CORE` and `VERSION_WEBAPP` in `docker-compose.yml`, then run:

```bash
docker compose pull
docker compose up -d
```

Your data and apps are kept.

## Uninstall FLECS

!!! info
    Uninstalling FLECS stops and removes the containers of your apps, but keeps their data. If you install FLECS again, your apps are back with their data. To remove your apps completely, uninstall them in the FLECS WebApp first.

1. Stop and remove the FILiP container. FILiP stops and removes all other FLECS containers before it exits. In the directory of your `docker-compose.yml`, run:

    ```bash
    docker compose down
    ```

2. Optionally, remove the FLECS data. This deletes your FLECS configuration, users and app data:

    ```bash
    docker volume rm flecsd flecs-floxy_certs flecs-floxy_data
    docker network rm flecs
    ```

    Depending on the FLECS version and your setup, more FLECS volumes exist:

    * `flecs-otelcol_certs` and `flecs-otelcol_logs`, if you installed the OpenTelemetry Collector.
    * One volume per volume of each app, named `flecs-<instance ID>-<name>`. With FLECS Core 5.5.0, this includes the volume `flecs-<instance ID>-fence`, which holds your users.

    To remove them as well, list all remaining volumes whose names start with `flecs`. Check the list, then remove them:

    ```bash
    docker volume ls --filter name=^flecs
    docker volume ls --quiet --filter name=^flecs | xargs -r docker volume rm
    ```

3. Optionally, remove the Docker images of FLECS and your apps with `docker image ls` and `docker image rm <image>`.
