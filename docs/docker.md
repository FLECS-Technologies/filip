# Install with Docker

If the installer script does not support your system, you can start the FILiP container with Docker directly. FILiP then installs FLECS the same way as the script does.

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Prerequisites

* Docker 20.10.10 or later, with API version 1.41 or later, configured to start on boot.
* Internet access to pull the images.

## Install FLECS

Run:

```bash
docker run --detach \
  --name flecs \
  --restart always \
  --network host \
  --stop-timeout 600 \
  --volume /run/docker.sock:/run/docker.sock \
  --env VERSION_CORE=5.5.0 \
  --env VERSION_WEBAPP=5.4.1 \
  cr.flecs.tech/flecs/filip:latest
```

Set `VERSION_CORE` and `VERSION_WEBAPP` to the versions you want to install. See [Versions](versions.md). For more settings, such as ports, add `--env` options from [Options](options.md).

!!! warning
    Always set both versions. Without them, FLECS updates itself to the latest version every time the container or the device restarts.

### With the OpenTelemetry Collector

Add two `--env` options and set `OTEL_EXPORT_DESTINATION` to the URL of your OTLP receiver. Both are required. Without `OTEL_EXPORT_DESTINATION`, the collector restarts repeatedly and exports nothing:

```bash
docker run --detach \
  --name flecs \
  --restart always \
  --network host \
  --stop-timeout 600 \
  --volume /run/docker.sock:/run/docker.sock \
  --env VERSION_CORE=5.5.0 \
  --env VERSION_WEBAPP=5.4.1 \
  --env INSTALL_OTEL_COLLECTOR=1 \
  --env OTEL_EXPORT_DESTINATION=https://otlp.example.com \
  cr.flecs.tech/flecs/filip:latest
```

For what the collector collects and which FLECS Core version it needs, see [OpenTelemetry Collector](options.md#opentelemetry-collector).

### Why these settings are needed

* `--network host` lets FILiP find free ports and a free subnet for the `flecs` network.
* The Docker socket lets FILiP manage the other FLECS containers.
* `--restart always` starts FLECS when the Docker daemon starts, for example after a reboot.
* `--stop-timeout 600` gives FILiP enough time to stop all FLECS containers.

## Access FLECS

Open a browser and enter your device's IP address or hostname. See [Access FLECS](install.md#access-flecs).

## Update FLECS

Remove the FILiP container and start it again with the new versions:

```bash
docker stop flecs
docker rm flecs
docker pull cr.flecs.tech/flecs/filip:latest
```

Then run the `docker run` command from [Install FLECS](#install-flecs) with the new versions. If you installed the OpenTelemetry Collector, include its two `--env` options again. Your data and apps are kept.

## Uninstall FLECS

!!! info
    Uninstalling FLECS stops and removes the containers of your apps, but keeps their data. If you install FLECS again, your apps are back with their data. To remove your apps completely, uninstall them in the FLECS WebApp first.

1. Stop and remove the FILiP container. FILiP stops and removes all other FLECS containers before it exits:

    ```bash
    docker stop flecs
    docker rm flecs
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
