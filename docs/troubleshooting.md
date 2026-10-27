# Troubleshooting

!!! info "Running Docker commands"
    The Docker commands in this guide assume that your user can run Docker, for example as a member of the `docker` group. Otherwise, put `sudo` in front of each `docker` command.

## Get more information

* Run the installer script with `--verbose` to see the output of every command, or `--debug` for internal messages as well:

    ```bash
    curl -fsSL install.flecs.tech | bash -s -- --verbose
    ```

* Show the log of the FILiP container, which starts and stops all FLECS containers:

    ```bash
    docker logs flecs
    ```

* Show the log of FLECS Core:

    ```bash
    docker logs flecs-flecsd
    ```

## Docker command errors

### "permission denied while trying to connect to the Docker daemon socket"

Your user is not allowed to run Docker. Put `sudo` in front of the `docker` command.

## Installer script errors

### "User input required but no tty allocated"

The script asks for confirmation but has no terminal to read from, for example in an automated setup. Add `--yes` to answer all prompts with yes.

### "You are running an outdated version of your OS"

Your operating system version is older than the supported versions. Update your operating system. See [Supported platforms](install.md#supported-platforms).

### "Your operating system is not officially supported by the installer"

The script does not know your Linux distribution. It can still attempt the installation. Docker must be installed beforehand. If the installation fails, use the [Docker](docker.md) method.

### "Automatic Docker installation is only supported on Debian/Ubuntu-based systems"

Install Docker yourself, following the [Docker installation guide](https://docs.docker.com/engine/install/) for your distribution. Then run the script again.

### "FLECS requires at least Docker client version 20.10.5"

Your Docker version is too old. Update Docker, then run the script again.

### "Podman is currently unsupported"

FLECS requires Docker. Install Docker instead of Podman, or contact [info@flecs.tech](mailto:info@flecs.tech) if you require Podman support.

### "FILiP cannot install FLECS core"

You requested a version older than 5.2.0. Use the previous installer. See [Versions before 5.2.0](versions.md#versions-before-520).

### "Please make sure your device is online"

The script cannot reach `https://flecs.tech`. Check the internet connection and the firewall of your device. See [Required DNS Entries](https://docs.flecs.tech/engineering/network-requirements/required-dns-entries/). To install without internet access, see [Offline Installation](offline.md).

## FILiP container errors

These errors appear in the log of the FILiP container.

### "No free port for http" or "No free port for https"

All default ports are in use by other programs. Choose free ports with `--http-port` and `--https-port`. See [Ports](options.md#ports).

### "No free subnet found for network flecs"

All subnets from `172.21.0.0/16` to `172.31.0.0/16` overlap with networks on your device. Free one of these subnets, or create the `flecs` network yourself with a free `/16` subnet before you start FLECS. FILiP reuses an existing `flecs` network:

```bash
docker network create --driver bridge --subnet 10.200.0.0/16 --gateway 10.200.0.1 flecs
```

## Docker installed with Snap

On Ubuntu, Docker installed as a Snap package can cause problems with FLECS. Check whether Docker is installed with Snap:

```bash
snap list
```

If `docker` is in the list, remove it:

```bash
sudo snap remove docker
```

Then run the installer script again. It installs Docker from the Ubuntu package sources.
