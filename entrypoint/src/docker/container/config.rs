use super::{CORE_CONTAINER_NAME, CORE_VOLUME, FLOXY_CONTAINER_NAME, WEBAPP_CONTAINER_NAME};
use crate::docker::network::FLECS_NETWORK_NAME;
use crate::docker::volume::{FLOXY_CERT_VOLUME, FLOXY_DATA_VOLUME};
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

pub fn core_container_config() -> ContainerConfig {
    let version = std::env::var(CORE_VERSION_ENV);
    let version = version.as_deref().unwrap_or(CORE_VERSION);
    let env: Option<Vec<String>> = std::env::var(CORE_ENV_VAR)
        .ok()
        .map(|pairs| parse_env_pairs(&pairs))
        .filter(|v: &Vec<String>| !v.is_empty());
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
                mounts: Some(vec![
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
                ]),
                ..HostConfig::default()
            }),
            env,
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
    use super::parse_env_pairs;

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
        assert_eq!(parse_env_pairs(r"KEY=hello\ world"), vec!["KEY=hello world"]);
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
}
