# flecs

## Usage

### Quickstart

```bash
docker create --name flecs --restart=always --network host --volume /var/run/docker.sock:/var/run/docker.sock flecspublic.azurecr.io/flecs/flecs:latest
docker container start flecs
```

### Explanation

`--network host` \
The container needs host networking to find a free subnet for the `flecs` network and to check for an available http and
https port.

`/var/run/docker.sock:/var/run/docker.sock`ß
The container needs access to the docker daemon in order to manage the other containers.

`--restart=always`\
This restarts flecs on errors and automatically when the docker daemon is started. This is meant to also start flecs on
system boot which requires the docker daemon to automatically start on boot as well.
