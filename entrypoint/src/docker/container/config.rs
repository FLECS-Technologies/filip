use super::{CORE_CONTAINER_NAME, CORE_VOLUME, FLOXY_CONTAINER_NAME, WEBAPP_CONTAINER_NAME};
use crate::docker::network::FLECS_NETWORK_NAME;
use crate::docker::volume::{FLOXY_CERT_VOLUME, FLOXY_DATA_VOLUME};
use bollard::config::{
    ContainerCreateBody, EndpointIpamConfig, EndpointSettings, HostConfig, Mount, MountTypeEnum,
    NetworkingConfig,
};
use bollard::query_parameters::CreateContainerOptions;
use std::collections::HashMap;
use std::net::Ipv4Addr;

pub type ContainerConfig = (Option<CreateContainerOptions>, ContainerCreateBody);
const CONTAINER_REGISTRY: &str = "flecspublic.azurecr.io";
const CORE_IMAGE: &str = "flecs-slim";
const CORE_VERSION: &str = "5.1.0-red-deer";
const FLOXY_IMAGE: &str = "flecs/floxy";
const FLOXY_VERSION: &str = "0.2.1";
const WEBAPP_IMAGE: &str = "webapp";
const WEBAPP_VERSION: &str = "5.1.0-red-deer";
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
    (
        Some(CreateContainerOptions {
            name: Some(FLOXY_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        }),
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
                ..HostConfig::default()
            }),
            env: Some(vec![
                format!("FLOXY_HTTP_PORT={http_port}"),
                format!("FLOXY_HTTPS_PORT={https_port}"),
                format!("FLOXY_FLECS_GATEWAY={gateway}"),
            ]),
            ..ContainerCreateBody::default()
        },
    )
}

pub fn core_container_config() -> ContainerConfig {
    (
        Some(CreateContainerOptions {
            name: Some(CORE_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        }),
        ContainerCreateBody {
            image: Some(format!("{CONTAINER_REGISTRY}/{CORE_IMAGE}:{CORE_VERSION}")),
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
            ..ContainerCreateBody::default()
        },
    )
}

pub fn webapp_container_config(ip: Ipv4Addr, gateway: Ipv4Addr) -> ContainerConfig {
    (
        Some(CreateContainerOptions {
            name: Some(WEBAPP_CONTAINER_NAME.to_string()),
            ..CreateContainerOptions::default()
        }),
        ContainerCreateBody {
            image: Some(format!(
                "{CONTAINER_REGISTRY}/{WEBAPP_IMAGE}:{WEBAPP_VERSION}"
            )),
            host_config: Some(HostConfig {
                extra_hosts: Some(vec![format!("flecs-floxy:{gateway}")]),
                ..HostConfig::default()
            }),
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
