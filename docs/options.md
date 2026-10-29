# Options

You can configure the installation with options of the installer script or with environment variables of the FILiP container.

* With the **installer script**, pass options after `bash -s --`:

    ```bash
    curl -fsSL install.flecs.tech | bash -s -- --yes --http-port 8080
    ```

* With **Docker Compose** or **Docker**, set the environment variables of the `flecs` container. See [Install with Docker Compose](docker-compose.md) and [Install with Docker](docker.md).

The script passes its options to the container as these environment variables.

## Installer script options

| Option | Description |
|---|---|
| `-y`, `--yes` | Answer all prompts with yes. Use it for unattended installations. |
| `-v`, `--verbose` | Print the output of the commands the script runs, such as `apt-get` and `docker`. |
| `-d`, `--debug` | Like `--verbose`, plus internal debug messages. |
| `--no-banner` | Do not print the FILiP banner. |
| `--no-welcome` | Do not print the welcome message and do not wait for confirmation. |
| `--offline` | Skip the internet connection check, the version lookup and the Docker installation. Requires `--core-version` and `--webapp-version`. See [Offline Installation](offline.md). |
| `--help` | Print all options and exit. |

The remaining options are described in the sections below.

## Versions

| Script option | Container variable | Default | Description |
|---|---|---|---|
| `--core-version <version>` | `VERSION_CORE` | Script: latest release. Container: `latest` | Version of FLECS Core |
| `--webapp-version <version>` | `VERSION_WEBAPP` | Script: latest release. Container: `latest` | Version of the FLECS WebApp |
| `--webapp-version none` | `INSTALL_WEBAPP=0` | WebApp is installed | Do not install the WebApp, for example on devices managed only through the API or a fleet manager |

See [Versions](versions.md).

## Ports

| Script option | Container variable | Default | Description |
|---|---|---|---|
| `--http-port <port>` | `FLOXY_HTTP_PORT` | First free port of 80, 8080, 8000 | HTTP port of the reverse proxy |
| `--https-port <port>` | `FLOXY_HTTPS_PORT` | First free port of 443, 8443, 4443 | HTTPS port of the reverse proxy |

If you set a port, FILiP uses it even if another program already uses it.

## Environment variables for FLECS components

Pass additional environment variables to the FLECS containers, for example to configure FLECS Core.

| Script option | Container variable | Passed to |
|---|---|---|
| `--core-env <KEY=VALUE>` | `FILIP_CORE_ENV` | FLECS Core (`flecs-flecsd`) |
| `--floxy-env <KEY=VALUE>` | `FILIP_FLOXY_ENV` | Floxy (`flecs-floxy`) |
| `--webapp-env <KEY=VALUE>` | `FILIP_WEBAPP_ENV` | FLECS WebApp (`flecs-webapp`) |

Repeat a script option to pass several variables:

```bash
curl -fsSL install.flecs.tech | bash -s -- \
  --core-env KEY1=value1 \
  --core-env KEY2=value2
```

In a container variable, separate several variables with spaces. Write a space inside a value as `\ ` and a backslash as `\\`:

```
FILIP_CORE_ENV=KEY1=value1 KEY2=hello\ world
```

`--webapp-env` cannot be combined with `--webapp-version none`.

## OpenTelemetry Collector

FILiP can install an OpenTelemetry Collector that collects metrics and logs from your device, FLECS and your apps, and exports them to an OTLP receiver of your choice.

!!! info
    The collector requires Docker 25 or later (API version 1.44). With older Docker versions, it restarts repeatedly and exports nothing. This includes the `docker.io` package of Debian 12, which the installer script installs there. The installer script checks the version and stops if it is too old.

!!! info
    FLECS Core sends its data to the collector from version 5.5.0. With older versions, the collector provides only Docker and system metrics. Data from FLECS Core and your apps is missing.

| Script option | Container variable | Default | Description |
|---|---|---|---|
| `--install-otel-collector` | `INSTALL_OTEL_COLLECTOR=1` | Not installed | Install the collector |
| `--otel-export-destination <url>` | `OTEL_EXPORT_DESTINATION` | None. Required with `--install-otel-collector` | URL of the OTLP receiver the collector exports to |
| `--otel-collector-version <version>` | `VERSION_OTEL_COLLECTOR` | `0` | Version of the collector image |

Each installation guide shows how to add the collector for its method.

The collector:

* Receives OTLP data on ports 4317 (gRPC) and 4318 (HTTP) on the gateway address of the `flecs` network, for example `172.21.0.1`. Containers on the device can reach it, other devices cannot.
* Reads host metrics such as CPU, memory, disk and network usage. To do this, it mounts the root file system of the device read-only.
* Limits its own container log to about 60 MB.
