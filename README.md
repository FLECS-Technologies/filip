# flecs

## Usage

### Quickstart

```bash
docker create --name flecs --restart=always --network host --volume /var/run/docker.sock:/var/run/docker.sock flecspublic.azurecr.io/flecs/flecs:latest
docker container start flecs
```
