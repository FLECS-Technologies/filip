# 💾 Installing FLECS Core

FLECS Core runs on any Linux device with Docker. You can install it yourself, or choose a device that comes with FLECS pre-installed from [flecs.tech/marketplace/category/systems/](https://flecs.tech/marketplace/category/systems/).

To install FLECS yourself, use FILiP, the FLECS Installer for Linux Platforms. It is a script that prepares your device and a container that keeps FLECS running.

## Choose an installation method

| Method | Use it when | Guide |
|---|---|---|
| **Installer script** | You install on Debian, Ubuntu or another Linux system with `bash`. Recommended for most users. | [Install with the installer script](install.md) |
| **Docker Compose** | Docker is already set up and you manage your containers with Compose, or your system has no `bash`. | [Install with Docker Compose](docker-compose.md) |
| **Docker** | Docker is already set up and the installer script does not support your system, for example because it has no `bash`. | [Install with Docker](docker.md) |
| **Manual** | You need full control over every container, network and volume, or FLECS must trust custom CA certificates, for example behind a TLS-inspecting proxy. | [Install manually](manual.md) |

All methods except the manual one install the same components in the same way. Each guide also describes how to add the optional OpenTelemetry Collector.

## How FILiP works

FILiP works in two stages:

1. **The installer script** prepares the host. It checks your operating system, installs Docker if needed, looks up the latest FLECS versions and starts the FILiP container.
2. **The FILiP container** (`flecs`) sets up FLECS. Every time it starts, including after each reboot, it pulls the FLECS images and recreates the FLECS containers. When it stops, it stops and removes them.

The Docker Compose and Docker methods skip the script and start the FILiP container directly.

## What gets installed

| Component | Container | Description |
|---|---|---|
| FILiP | `flecs` | Starts, stops and recreates all other FLECS containers |
| Floxy | `flecs-floxy` | Reverse proxy for the WebApp and the FLECS Core API |
| FLECS Core | `flecs-flecsd` | The FLECS daemon. Manages your apps |
| FLECS WebApp | `flecs-webapp` | The web interface of FLECS. Optional |
| OpenTelemetry Collector | `flecs-otelcol` | Collects metrics and logs. Optional, see [Options](options.md#opentelemetry-collector) |

FILiP also creates:

* A Docker bridge network called `flecs`. It uses the first `/16` subnet from `172.21.0.0` to `172.31.0.0` that is not already used on your device.
* The volume `flecsd`, which holds all FLECS Core data, and the volumes `flecs-floxy_certs` and `flecs-floxy_data` for the reverse proxy.

## Ports

The WebApp is reachable through Floxy. FILiP uses the first free port of each list:

* **HTTP:** 80, 8080, 8000
* **HTTPS:** 443, 8443, 4443

HTTP connections are redirected to HTTPS. To choose the ports yourself, see [Options](options.md#ports).

Your device needs outbound access to a few FLECS endpoints. See [Required DNS Entries](https://docs.flecs.tech/engineering/network-requirements/required-dns-entries/).
