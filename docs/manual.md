# Install Manually

If you need full control over every container, network and volume, or FLECS must trust [custom CA certificates](#with-custom-ca-certificates), you can install the FLECS components with your own Docker Compose file, without FILiP. You then create the same setup that FILiP creates, and you are responsible for updating it.

For most users, the [installer script](install.md), [Docker Compose](docker-compose.md) or [Docker](docker.md) method is easier.

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Prerequisites

* Docker 20.10.5 or later, with API version 1.41 or later.
* Docker Compose 2.0.0 or later.
* Internet access to pull the images.

## Install FLECS

Create a `docker-compose.yml` file:

```yaml
services:
  flecsd:
    image: cr.flecs.tech/flecs/flecs-core:5.5.0
    container_name: flecs-flecsd
    hostname: flecs-flecsd
    restart: always
    network_mode: host
    volumes:
      - flecsd:/var/lib/flecs
      - flecs-floxy_data:/tmp/floxy
      - /run/docker.sock:/run/docker.sock

  webapp:
    image: cr.flecs.tech/flecs/webapp:5.4.1
    container_name: flecs-webapp
    restart: always
    networks:
      flecs:
        ipv4_address: 172.21.255.254
    extra_hosts:
      - "flecs-floxy:172.21.0.1"

  floxy:
    image: cr.flecs.tech/flecs/floxy:0
    container_name: flecs-floxy
    hostname: flecs-floxy
    restart: always
    network_mode: host
    volumes:
      - flecs-floxy_data:/tmp/floxy
      - flecs-floxy_certs:/etc/nginx/certs
    environment:
      FLOXY_HTTP_PORT: 80
      FLOXY_HTTPS_PORT: 443
      FLOXY_FLECS_GATEWAY: 172.21.0.1

networks:
  flecs:
    name: flecs
    ipam:
      driver: default
      config:
        - subnet: 172.21.0.0/16
          gateway: 172.21.0.1

volumes:
  flecsd:
    name: flecsd
  flecs-floxy_certs:
    name: flecs-floxy_certs
  flecs-floxy_data:
    name: flecs-floxy_data
    driver: local
    driver_opts:
      device: tmpfs
      type: tmpfs
      o: size=4m
```

Adjust the versions and ports to your needs. Floxy serves the WebApp and the FLECS Core API on these ports and redirects HTTP to HTTPS.

You can also change the subnet of the `flecs` network. Then also change the WebApp address, the `flecs-floxy` host entry and `FLOXY_FLECS_GATEWAY`. The WebApp must use the address ending in `.255.254`, and the gateway the address ending in `.0.1`.

Start FLECS:

```bash
docker compose up -d
```

## With the OpenTelemetry Collector

To add the collector, create a second file, `docker-compose.otel.yml`, next to `docker-compose.yml`. It adds the collector and connects FLECS Core to it:

```yaml
services:
  flecsd:
    environment:
      FLECS_CORE_SECRET_EXPORT_PATH: /etc/flecs/otel-certs
      FLECS_CORE_OTEL_GRPC_COLLECTOR_ENDPOINT: http://172.21.0.1:4317
      FLECS_CORE_OTEL_HTTP_COLLECTOR_ENDPOINT: http://172.21.0.1:4318
    volumes:
      - flecs-otelcol_certs:/etc/flecs/otel-certs

  otelcol:
    image: cr.flecs.tech/flecs/otel-collector:0
    container_name: flecs-otelcol
    hostname: flecs-otelcol
    restart: always
    network_mode: host
    volumes:
      - flecs-otelcol_certs:/etc/otelcol/certs
      - flecs-otelcol_logs:/var/log/otelcol
      - /run/docker.sock:/var/run/docker.sock
      - /:/hostfs:ro
    environment:
      OTLP_UPSTREAM_ENDPOINT: https://otlp.example.com
      OTEL_BIND_ADDRESS: 172.21.0.1
    logging:
      driver: json-file
      options:
        max-size: 20m
        max-file: "3"

volumes:
  flecs-otelcol_certs:
    name: flecs-otelcol_certs
    driver: local
    driver_opts:
      device: tmpfs
      type: tmpfs
      o: size=1m
  flecs-otelcol_logs:
    name: flecs-otelcol_logs
```

Set `OTLP_UPSTREAM_ENDPOINT` to the URL of your OTLP receiver. If you changed the subnet of the `flecs` network, use its gateway address in `OTEL_BIND_ADDRESS` and in both endpoints of FLECS Core.

Start FLECS with both files:

```bash
docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d
```

Pass both files to every `docker compose` command, including updates and uninstalling. For what the collector collects and which FLECS Core version it needs, see [OpenTelemetry Collector](options.md#opentelemetry-collector).

## With custom CA certificates

If your network uses its own certificate authority, for example a proxy that inspects TLS traffic, FLECS Core and the OpenTelemetry Collector must trust its certificates. Add them to the certificate store of your device and pass the store to the containers with additional override files.

1. Add your CA certificates to the certificate store of the device. On Debian and Ubuntu, copy each certificate as a `.crt` file to `/usr/local/share/ca-certificates/` and run:

    ```bash
    sudo update-ca-certificates
    ```

    This updates `/etc/ssl/certs/ca-certificates.crt`, which contains all trusted certificates of the device.

2. Create `docker-compose.ca.yml` next to `docker-compose.yml`. It passes the certificates to FLECS Core:

    ```yaml
    services:
      flecsd:
        volumes:
          - /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro
    ```

3. If you use the [OpenTelemetry Collector](#with-the-opentelemetry-collector), also create `docker-compose.otel-ca.yml`. It passes the certificates to the collector:

    ```yaml
    services:
      otelcol:
        volumes:
          - /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro
    ```

    Use this file only together with `docker-compose.otel.yml`.

On other distributions, the certificate store may be at a different path, for example `/etc/pki/tls/certs/ca-bundle.crt` on Fedora and Red Hat Enterprise Linux. Change only the part before the first `:` in both files.

Start FLECS with the override files:

```bash
docker compose -f docker-compose.yml -f docker-compose.ca.yml up -d
```

With the OpenTelemetry Collector:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.otel.yml \
  -f docker-compose.ca.yml \
  -f docker-compose.otel-ca.yml \
  up -d
```

Pass the same files to every `docker compose` command, including updates and uninstalling.

!!! tip
    Instead of passing the files to every command, set the `COMPOSE_FILE` variable once in your shell, for example `export COMPOSE_FILE=docker-compose.yml:docker-compose.ca.yml`. Then run `docker compose` without `-f`.

When you change the CA certificates of the device later, recreate the containers so that they read the new certificates:

```bash
docker compose -f docker-compose.yml -f docker-compose.ca.yml up -d --force-recreate
```

## Access FLECS

Open a browser and enter your device's IP address or hostname, for example `https://192.168.1.10`. If you changed `FLOXY_HTTPS_PORT`, add the port, for example `https://192.168.1.10:8443`.

The WebApp uses a self-signed certificate. Accept the security warning of your browser to continue. When you use `curl`, pass `-k`.

## Update FLECS

Change the versions of FLECS Core and the WebApp in `docker-compose.yml`. Then run:

```bash
docker compose pull
docker compose up -d
```

Your data is kept in the `flecsd` volume.

## Uninstall FLECS

!!! info
    Uninstalling FLECS does not remove the apps you installed with FLECS. Uninstall your apps in the FLECS WebApp first.

1. Stop and remove the FLECS containers. In the directory of your `docker-compose.yml`, run:

    ```bash
    docker compose down
    ```

2. Optionally, remove the FLECS data. This deletes your FLECS configuration, users and app data:

    ```bash
    docker volume rm flecsd flecs-floxy_certs flecs-floxy_data
    ```

    If you installed the OpenTelemetry Collector, also remove `flecs-otelcol_certs` and `flecs-otelcol_logs`.

3. Optionally, remove the Docker images of FLECS and your apps with `docker image ls` and `docker image rm <image>`.
