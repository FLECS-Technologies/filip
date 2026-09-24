use super::{
    CORE_CONTAINER_NAME, CORE_VOLUME, FLOXY_CONTAINER_NAME, OTEL_CONTAINER_NAME,
    WEBAPP_CONTAINER_NAME,
};
use crate::docker::network::FLECS_NETWORK_NAME;
use crate::docker::volume::{
    FLOXY_CERT_VOLUME, FLOXY_DATA_VOLUME, OTEL_CERTS_VOLUME, OTEL_LOGS_VOLUME,
};
use bollard::config::{
    ContainerCreateBody, EndpointIpamConfig, EndpointSettings, HostConfig, Mount, MountTypeEnum,
    NetworkingConfig, RestartPolicy, RestartPolicyNameEnum,
};
use bollard::query_parameters::CreateContainerOptions;
use std::collections::HashMap;
use std::net::Ipv4Addr;

pub type ContainerConfig = (CreateContainerOptions, ContainerCreateBody);
const CONTAINER_REGISTRY: &str = "cr.flecs.tech";
const CORE_IMAGE: &str = "flecs/flecs-core";
const CORE_VERSION: &str = "latest";
const CORE_VERSION_ENV: &str = "VERSION_CORE";
const FLOXY_IMAGE: &str = "flecs/floxy";
const FLOXY_VERSION: &str = "0";
const WEBAPP_IMAGE: &str = "flecs/webapp";
const WEBAPP_VERSION: &str = "latest";
const WEBAPP_VERSION_ENV: &str = "VERSION_WEBAPP";
const WHITELABEL_ENV: &str = "WHITELABEL";
const CORE_ENV_VAR: &str = "FILIP_CORE_ENV";
const FLOXY_ENV_VAR: &str = "FILIP_FLOXY_ENV";
const WEBAPP_ENV_VAR: &str = "FILIP_WEBAPP_ENV";
const OTEL_IMAGE: &str = "flecs/otel-collector";
const OTEL_VERSION_DEFAULT: &str = "0";
pub const OTEL_INSTALL_ENV: &str = "INSTALL_OTEL_COLLECTOR";
pub const WEBAPP_INSTALL_ENV: &str = "INSTALL_WEBAPP";
const OTEL_VERSION_ENV: &str = "VERSION_OTEL_COLLECTOR";
const OTEL_EXPORT_DESTINATION_ENV: &str = "OTEL_EXPORT_DESTINATION";
const OTEL_UPSTREAM_ENDPOINT_ENV: &str = "OTLP_UPSTREAM_ENDPOINT";
const OTEL_HTTP_PORT: u16 = 4318;
/// Path inside the otel-collector container its exporter reads the device's
/// mTLS identity from (client.pem/client.key), matching its baked-in config.
const OTEL_CERTS_MOUNT_TARGET_COLLECTOR: &str = "/etc/otelcol/certs";
/// Where the collector's `file` log exporter writes its rotating backups
const OTEL_LOGS_MOUNT_TARGET: &str = "/var/log/otelcol";
/// Path inside the core container flecsd is told (via
/// `FLECS_CORE_SECRET_EXPORT_PATH`) to export its mTLS identity to, so it
/// ends up on the volume shared with the otel-collector.
const OTEL_CERTS_MOUNT_TARGET_CORE: &str = "/etc/flecs/otel-certs";
const CORE_SECRET_EXPORT_PATH_ENV: &str = "FLECS_CORE_SECRET_EXPORT_PATH";
const CORE_OTEL_HTTP_COLLECTOR_ENDPOINT_ENV: &str = "FLECS_CORE_OTEL_HTTP_COLLECTOR_ENDPOINT";

/// Whether otel-collector should be installed
/// `INSTALL_OTEL_COLLECTOR=1` => true else false.
pub fn otel_install_requested() -> bool {
    matches!(std::env::var(OTEL_INSTALL_ENV).as_deref(), Ok("1"))
}

/// Whether flecs-webapp should be installed. Installed by default;
/// `INSTALL_WEBAPP=0` disables it.
pub fn webapp_install_requested() -> bool {
    !matches!(std::env::var(WEBAPP_INSTALL_ENV).as_deref(), Ok("0"))
}

fn parse_env_pairs(s: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    let mut escaped = false;
    for c in s.chars() {
        if escaped {
            current.push(c);
            escaped = false;
        } else if c == '\\' {
            escaped = true;
        } else if c == ' ' {
            if !current.is_empty() {
                result.push(std::mem::take(&mut current));
            }
        } else {
            current.push(c);
        }
    }
    if escaped {
        current.push('\\');
    }
    if !current.is_empty() {
        result.push(current);
    }
    result
}

fn docker_socket_mount() -> Mount {
    Mount {
        typ: Some(MountTypeEnum::BIND),
        source: Some("/run/docker.sock".to_string()),
        target: Some("/run/docker.sock".to_string()),
        ..Mount::default()
    }
}

/// otel-collector's `docker_stats` receiver is enabled by default and hard
/// requires the docker socket at this exact path. Its runtime image is
/// built `FROM scratch`, so there's no `/var/run -> /run` symlink.
fn otel_docker_socket_mount() -> Mount {
    Mount {
        typ: Some(MountTypeEnum::BIND),
        source: Some("/run/docker.sock".to_string()),
        target: Some("/var/run/docker.sock".to_string()),
        ..Mount::default()
    }
}

/// otel-collector's `hostmetrics` receiver (cpu/memory/disk/filesystem/
/// network/load scrapers) is configured to use `root_path: /hostfs`.
/// To actually read host metrics it needs the host root mounted there.
fn otel_hostfs_mount() -> Mount {
    Mount {
        typ: Some(MountTypeEnum::BIND),
        source: Some("/".to_string()),
        target: Some("/hostfs".to_string()),
        read_only: Some(true),
        ..Mount::default()
    }
}

pub fn floxy_container_config(
    http_port: u16,
    https_port: u16,
    gateway: Ipv4Addr,
) -> ContainerConfig {
    let mut env = vec![
        format!("FLOXY_HTTP_PORT={http_port}"),
        format!("FLOXY_HTTPS_PORT={https_port}"),
        format!("FLOXY_FLECS_GATEWAY={gateway}"),
    ];
    if let Ok(pairs) = std::env::var(FLOXY_ENV_VAR) {
        env.extend(parse_env_pairs(&pairs));
    }
    (
        CreateContainerOptions {
            name: Some(FLOXY_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        },
        ContainerCreateBody {
            image: Some(format!(
                "{CONTAINER_REGISTRY}/{FLOXY_IMAGE}:{FLOXY_VERSION}"
            )),
            hostname: Some(FLOXY_CONTAINER_NAME.to_string()),
            host_config: Some(HostConfig {
                network_mode: Some("host".to_string()),
                mounts: Some(vec![
                    Mount {
                        typ: Some(MountTypeEnum::VOLUME),
                        source: Some(FLOXY_CERT_VOLUME.to_string()),
                        target: Some("/etc/nginx/certs".to_string()),
                        ..Mount::default()
                    },
                    Mount {
                        typ: Some(MountTypeEnum::VOLUME),
                        source: Some(FLOXY_DATA_VOLUME.to_string()),
                        target: Some("/tmp/floxy".to_string()),
                        ..Mount::default()
                    },
                ]),
                restart_policy: Some(RestartPolicy {
                    maximum_retry_count: Some(0),
                    name: Some(RestartPolicyNameEnum::ON_FAILURE),
                }),
                ..HostConfig::default()
            }),
            env: Some(env),
            ..ContainerCreateBody::default()
        },
    )
}

/// `otelcol_ip` is the otel-collector's static IP on the `flecs` bridge
/// network, or `None` if `--install-otel-collector` was not passed.
pub fn core_container_config(otelcol_ip: Option<Ipv4Addr>) -> ContainerConfig {
    let version = std::env::var(CORE_VERSION_ENV);
    let version = version.as_deref().unwrap_or(CORE_VERSION);
    let mut mounts = vec![
        docker_socket_mount(),
        Mount {
            typ: Some(MountTypeEnum::VOLUME),
            source: Some(FLOXY_DATA_VOLUME.to_string()),
            target: Some("/tmp/floxy".to_string()),
            ..Mount::default()
        },
        Mount {
            typ: Some(MountTypeEnum::VOLUME),
            source: Some(CORE_VOLUME.to_string()),
            target: Some("/var/lib/flecs".to_string()),
            ..Mount::default()
        },
    ];
    let mut env = Vec::new();
    if let Some(otelcol_ip) = otelcol_ip {
        mounts.push(Mount {
            typ: Some(MountTypeEnum::VOLUME),
            source: Some(OTEL_CERTS_VOLUME.to_string()),
            target: Some(OTEL_CERTS_MOUNT_TARGET_CORE.to_string()),
            ..Mount::default()
        });
        env.push(format!(
            "{CORE_SECRET_EXPORT_PATH_ENV}={OTEL_CERTS_MOUNT_TARGET_CORE}"
        ));
        env.push(format!(
            "{CORE_OTEL_HTTP_COLLECTOR_ENDPOINT_ENV}=http://{otelcol_ip}:{OTEL_HTTP_PORT}"
        ));
    }
    if let Ok(pairs) = std::env::var(CORE_ENV_VAR) {
        env.extend(parse_env_pairs(&pairs));
    }
    let env = if env.is_empty() { None } else { Some(env) };
    (
        CreateContainerOptions {
            name: Some(CORE_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        },
        ContainerCreateBody {
            image: Some(format!("{CONTAINER_REGISTRY}/{CORE_IMAGE}:{version}")),
            hostname: Some(CORE_CONTAINER_NAME.to_string()),
            host_config: Some(HostConfig {
                network_mode: Some("host".to_string()),
                mounts: Some(mounts),
                ..HostConfig::default()
            }),
            env,
            ..ContainerCreateBody::default()
        },
    )
}

/// `ip` is the static IP to assign the collector on the `flecs` bridge
/// network. The container joins that network only, so it's unreachable
/// from outside Docker's bridge network.
pub fn otel_container_config(ip: Ipv4Addr) -> ContainerConfig {
    let version = std::env::var(OTEL_VERSION_ENV);
    let version = version.as_deref().unwrap_or(OTEL_VERSION_DEFAULT);
    let export_destination = std::env::var(OTEL_EXPORT_DESTINATION_ENV).unwrap_or_default();
    (
        CreateContainerOptions {
            name: Some(OTEL_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        },
        ContainerCreateBody {
            image: Some(format!("{CONTAINER_REGISTRY}/{OTEL_IMAGE}:{version}")),
            hostname: Some(OTEL_CONTAINER_NAME.to_string()),
            host_config: Some(HostConfig {
                mounts: Some(vec![
                    Mount {
                        typ: Some(MountTypeEnum::VOLUME),
                        source: Some(OTEL_CERTS_VOLUME.to_string()),
                        target: Some(OTEL_CERTS_MOUNT_TARGET_COLLECTOR.to_string()),
                        ..Mount::default()
                    },
                    Mount {
                        typ: Some(MountTypeEnum::VOLUME),
                        source: Some(OTEL_LOGS_VOLUME.to_string()),
                        target: Some(OTEL_LOGS_MOUNT_TARGET.to_string()),
                        ..Mount::default()
                    },
                    otel_docker_socket_mount(),
                    otel_hostfs_mount(),
                ]),
                restart_policy: Some(RestartPolicy {
                    maximum_retry_count: Some(0),
                    name: Some(RestartPolicyNameEnum::ON_FAILURE),
                }),
                ..HostConfig::default()
            }),
            env: Some(vec![format!(
                "{OTEL_UPSTREAM_ENDPOINT_ENV}={export_destination}"
            )]),
            networking_config: Some(NetworkingConfig {
                endpoints_config: Some(HashMap::from([(
                    FLECS_NETWORK_NAME.to_string(),
                    EndpointSettings {
                        ipam_config: Some(EndpointIpamConfig {
                            ipv4_address: Some(ip.to_string()),
                            ..EndpointIpamConfig::default()
                        }),
                        ..EndpointSettings::default()
                    },
                )])),
            }),
            ..ContainerCreateBody::default()
        },
    )
}

pub fn webapp_container_config(ip: Ipv4Addr, gateway: Ipv4Addr) -> ContainerConfig {
    let version = std::env::var(WEBAPP_VERSION_ENV);
    let version = version.as_deref().unwrap_or(WEBAPP_VERSION);
    let env: Option<Vec<String>> = std::env::var(WEBAPP_ENV_VAR)
        .ok()
        .map(|pairs| parse_env_pairs(&pairs))
        .filter(|v: &Vec<String>| !v.is_empty());
    let tag = match std::env::var(WHITELABEL_ENV) {
        Ok(whitelabel) => format!("{version}-{whitelabel}"),
        _ => version.to_string(),
    };
    (
        CreateContainerOptions {
            name: Some(WEBAPP_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        },
        ContainerCreateBody {
            image: Some(format!("{CONTAINER_REGISTRY}/{WEBAPP_IMAGE}:{tag}")),
            host_config: Some(HostConfig {
                extra_hosts: Some(vec![format!("flecs-floxy:{gateway}")]),
                ..HostConfig::default()
            }),
            env,
            networking_config: Some(NetworkingConfig {
                endpoints_config: Some(HashMap::from([(
                    FLECS_NETWORK_NAME.to_string(),
                    EndpointSettings {
                        ipam_config: Some(EndpointIpamConfig {
                            ipv4_address: Some(ip.to_string()),
                            ..EndpointIpamConfig::default()
                        }),
                        ..EndpointSettings::default()
                    },
                )])),
            }),
            ..ContainerCreateBody::default()
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_pair_no_escaping() {
        assert_eq!(parse_env_pairs("KEY=value"), vec!["KEY=value"]);
    }

    #[test]
    fn multiple_pairs_no_escaping() {
        assert_eq!(
            parse_env_pairs("KEY1=foo KEY2=bar KEY3=baz"),
            vec!["KEY1=foo", "KEY2=bar", "KEY3=baz"]
        );
    }

    #[test]
    fn escaped_space_in_value() {
        assert_eq!(
            parse_env_pairs(r"KEY=hello\ world"),
            vec!["KEY=hello world"]
        );
    }

    #[test]
    fn escaped_backslash_in_value() {
        assert_eq!(
            parse_env_pairs(r"KEY=path\\to\\file"),
            vec![r"KEY=path\to\file"]
        );
    }

    #[test]
    fn multiple_pairs_with_spaces_in_values() {
        assert_eq!(
            parse_env_pairs(r"KEY1=hello\ world KEY2=foo\ bar"),
            vec!["KEY1=hello world", "KEY2=foo bar"]
        );
    }

    #[test]
    fn url_value() {
        assert_eq!(
            parse_env_pairs("FLECS_CORE_MARGO_WFM_URL=http://example.com:8080/path"),
            vec!["FLECS_CORE_MARGO_WFM_URL=http://example.com:8080/path"]
        );
    }

    #[test]
    fn empty_input() {
        assert_eq!(parse_env_pairs(""), Vec::<String>::new());
    }

    #[test]
    fn multiple_spaces_between_pairs() {
        assert_eq!(
            parse_env_pairs("KEY1=foo  KEY2=bar"),
            vec!["KEY1=foo", "KEY2=bar"]
        );
    }

    #[test]
    fn trailing_backslash_is_kept() {
        assert_eq!(parse_env_pairs(r"KEY=value\"), vec![r"KEY=value\"]);
    }

    fn mounts_of(config: &ContainerConfig) -> &[Mount] {
        config
            .1
            .host_config
            .as_ref()
            .unwrap()
            .mounts
            .as_deref()
            .unwrap()
    }

    #[test]
    fn otel_container_config_joins_flecs_network_with_static_ip_and_no_host_mode() {
        let ip = Ipv4Addr::new(172, 21, 255, 253);
        let config = otel_container_config(ip);
        assert_eq!(
            config.1.image.as_deref(),
            Some("cr.flecs.tech/flecs/otel-collector:0")
        );
        assert!(
            config
                .1
                .host_config
                .as_ref()
                .unwrap()
                .network_mode
                .is_none()
        );
        assert!(
            config
                .1
                .host_config
                .as_ref()
                .unwrap()
                .port_bindings
                .is_none()
        );
        assert!(config.1.exposed_ports.is_none());
        let endpoints = &config
            .1
            .networking_config
            .as_ref()
            .unwrap()
            .endpoints_config
            .as_ref()
            .unwrap();
        let endpoint = endpoints.get(FLECS_NETWORK_NAME).unwrap();
        assert_eq!(
            endpoint
                .ipam_config
                .as_ref()
                .unwrap()
                .ipv4_address
                .as_deref(),
            Some("172.21.255.253")
        );
    }

    #[test]
    fn otel_container_config_mounts_certs_volume_at_collector_path() {
        let config = otel_container_config(Ipv4Addr::new(172, 21, 255, 253));
        let mounts = mounts_of(&config);
        assert!(
            mounts
                .iter()
                .any(|m| m.source.as_deref() == Some(OTEL_CERTS_VOLUME)
                    && m.target.as_deref() == Some(OTEL_CERTS_MOUNT_TARGET_COLLECTOR))
        );
    }

    #[test]
    fn otel_container_config_mounts_docker_socket_at_var_run() {
        // The collector's docker_stats receiver is on by default and its
        // baked-in config hard-requires the socket at this exact path -
        // without it the whole collector process fails to start.
        let config = otel_container_config(Ipv4Addr::new(172, 21, 255, 253));
        let mounts = mounts_of(&config);
        assert!(
            mounts
                .iter()
                .any(|m| m.source.as_deref() == Some("/run/docker.sock")
                    && m.target.as_deref() == Some("/var/run/docker.sock"))
        );
    }

    #[test]
    fn otel_container_config_mounts_host_root_readonly_at_hostfs() {
        // The collector's baked-in config sets root_path: /hostfs for its
        // hostmetrics scrapers (cpu/memory/disk/filesystem/network/load) -
        // without this mounted, those scrapers report the collector's own
        // container view instead of the host's, and config validation fails
        // outright with nothing mounted there at all.
        let config = otel_container_config(Ipv4Addr::new(172, 21, 255, 253));
        let mounts = mounts_of(&config);
        assert!(mounts.iter().any(|m| m.source.as_deref() == Some("/")
            && m.target.as_deref() == Some("/hostfs")
            && m.read_only == Some(true)));
    }

    #[test]
    fn otel_container_config_mounts_logs_volume() {
        let config = otel_container_config(Ipv4Addr::new(172, 21, 255, 253));
        let mounts = mounts_of(&config);
        assert!(
            mounts
                .iter()
                .any(|m| m.source.as_deref() == Some(OTEL_LOGS_VOLUME)
                    && m.target.as_deref() == Some("/var/log/otelcol"))
        );
    }

    #[test]
    fn core_container_config_without_otel_has_no_otel_mount_or_env() {
        let config = core_container_config(None);
        let mounts = mounts_of(&config);
        assert!(
            !mounts
                .iter()
                .any(|m| m.source.as_deref() == Some(OTEL_CERTS_VOLUME))
        );
        assert!(config.1.env.is_none());
    }

    #[test]
    fn core_container_config_with_otel_adds_mount_and_env() {
        let ip = Ipv4Addr::new(172, 21, 255, 253);
        let config = core_container_config(Some(ip));
        let mounts = mounts_of(&config);
        assert!(
            mounts
                .iter()
                .any(|m| m.source.as_deref() == Some(OTEL_CERTS_VOLUME)
                    && m.target.as_deref() == Some(OTEL_CERTS_MOUNT_TARGET_CORE))
        );
        let env = config.1.env.unwrap();
        assert!(env.contains(&format!(
            "{CORE_SECRET_EXPORT_PATH_ENV}={OTEL_CERTS_MOUNT_TARGET_CORE}"
        )));
        assert!(env.contains(&format!(
            "{CORE_OTEL_HTTP_COLLECTOR_ENDPOINT_ENV}=http://{ip}:{OTEL_HTTP_PORT}"
        )));
    }

    #[test]
    fn core_container_config_still_host_network_mode() {
        let config = core_container_config(Some(Ipv4Addr::new(172, 21, 255, 253)));
        assert_eq!(
            config
                .1
                .host_config
                .as_ref()
                .unwrap()
                .network_mode
                .as_deref(),
            Some("host")
        );
    }
}
