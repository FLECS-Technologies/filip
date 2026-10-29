# Versions

By default, the installer script installs the latest releases of FLECS Core and the FLECS WebApp. You can install specific versions instead, for example to test compatibility or to replicate an existing setup.

## Install a specific version

Pass the versions to the installer script:

```bash
curl -fsSL install.flecs.tech | bash -s -- --core-version 5.5.0 --webapp-version 5.4.1
```

You can write versions with or without a leading `v`, for example `5.5.0` or `v5.5.0`.

If you set only one of the two options, the script installs the latest release of the other component.

To find available versions:

* Latest releases: `curl -fsSL https://latest.flecs.tech/core` and `curl -fsSL https://latest.flecs.tech/webapp`
* All FLECS Core versions: [codeberg.org/flecs-tech/flecs-core/tags](https://codeberg.org/flecs-tech/flecs-core/tags)
* All FLECS WebApp versions: [github.com/FLECS-Technologies/flecs-webapp/releases](https://github.com/FLECS-Technologies/flecs-webapp/releases)

With Docker Compose or Docker, set the `VERSION_CORE` and `VERSION_WEBAPP` environment variables of the FILiP container instead. See [Options](options.md#versions).

## Versions before 5.2.0

This installer supports FLECS Core 5.2.0 and later. To install an older version, use the previous installer and always set both versions. Without them, the previous installer fails, because it can no longer look up the latest versions:

```bash
curl -fsSL install-old.flecs.tech | bash -s -- --core-version 3.6.2-hedgehog --webapp-version 3.6.0-hedgehog
```

## Fixed and moving versions

The installer script always installs fixed versions. FLECS stays at these versions until you run the script again.

When you start the FILiP container yourself without `VERSION_CORE` and `VERSION_WEBAPP`, it uses the `latest` images. FILiP pulls images every time it starts, so FLECS updates itself on every restart of the container or the device. To avoid unplanned updates, always set both versions.

## FILiP versions

The FILiP container image `cr.flecs.tech/flecs/filip` is available with these tags:

| Tag | Description |
|---|---|
| `latest` | Latest release. Used by the installer script |
| `4`, `4.2`, `4.2.0` | Specific major, minor or patch version. Also available with a leading `v` |
| `rc` | Latest release candidate |

All images support AMD64 and ARM64.
