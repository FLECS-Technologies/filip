use crate::docker::network::ifaddr::ReadNetworkAdaptersError;
use crate::info;
use bollard::Docker;
use bollard::config::{Ipam, IpamConfig, NetworkCreateRequest};
use procfs::ProcError;
use procfs::net::TcpState;
use std::collections::HashSet;
use std::net::{AddrParseError, IpAddr, Ipv4Addr};

mod ifaddr;

#[derive(thiserror::Error, Debug)]
pub enum NetworkSetupError {
    #[error(transparent)]
    Bollard(#[from] bollard::errors::Error),
    #[error("Logic error during network creation: {message}")]
    Logic { message: String },
    #[error("Encountered invalid ip during network creation: {0}")]
    InvalidIpv4(#[from] AddrParseError),
    #[error(transparent)]
    ReadNetworkAdapters(#[from] ReadNetworkAdaptersError),
    #[error("No free port for {0}")]
    PortBusy(&'static str),
    #[error(transparent)]
    Procfs(#[from] ProcError),
}

type Network = (Ipv4Addr, u8);
pub const FLECS_NETWORK_NAME: &str = "flecs";
const SUBNETS: [Network; 11] = [
    (Ipv4Addr::new(172, 21, 0, 0), 16),
    (Ipv4Addr::new(172, 22, 0, 0), 16),
    (Ipv4Addr::new(172, 23, 0, 0), 16),
    (Ipv4Addr::new(172, 24, 0, 0), 16),
    (Ipv4Addr::new(172, 25, 0, 0), 16),
    (Ipv4Addr::new(172, 26, 0, 0), 16),
    (Ipv4Addr::new(172, 27, 0, 0), 16),
    (Ipv4Addr::new(172, 28, 0, 0), 16),
    (Ipv4Addr::new(172, 29, 0, 0), 16),
    (Ipv4Addr::new(172, 30, 0, 0), 16),
    (Ipv4Addr::new(172, 31, 0, 0), 16),
];
const HTTP_PORTS: [u16; 3] = [80, 8080, 8000];
const HTTPS_PORTS: [u16; 3] = [443, 8443, 4443];

fn network_contains_ip(network: Network, ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let subnet_mask = Ipv4Addr::from(0xffffffff << (32 - network.1));
            subnet_mask & ip == network.0
        }
        IpAddr::V6(_) => false,
    }
}

pub struct NetworkInfo {
    pub free_http_port: u16,
    pub free_https_port: u16,
    pub gateway: Ipv4Addr,
}

pub async fn network_setup(docker_client: &Docker) -> Result<NetworkInfo, NetworkSetupError> {
    let busy_ports = get_busy_ports().await?;
    let free_http_port = HTTP_PORTS
        .iter()
        .find(|port| !busy_ports.contains(port))
        .copied()
        .ok_or_else(|| NetworkSetupError::PortBusy("http"))?;
    let free_https_port = HTTPS_PORTS
        .iter()
        .find(|port| !busy_ports.contains(port))
        .copied()
        .ok_or_else(|| NetworkSetupError::PortBusy("https"))?;
    let gateway = flecs_network_setup(docker_client).await?;
    Ok(NetworkInfo {
        free_https_port,
        free_http_port,
        gateway,
    })
}

async fn get_busy_ports() -> Result<HashSet<u16>, ProcError> {
    Ok(procfs::net::tcp()?
        .into_iter()
        .chain(procfs::net::tcp6()?)
        .filter_map(|entry| {
            if entry.state == TcpState::Listen {
                Some(entry.local_address.port())
            } else {
                None
            }
        })
        .collect())
}

async fn flecs_network_setup(docker_client: &Docker) -> Result<Ipv4Addr, NetworkSetupError> {
    match docker_client
        .inspect_network(FLECS_NETWORK_NAME, None)
        .await
    {
        Ok(network) => {
            info!("Reusing existing network {FLECS_NETWORK_NAME}");
            Ok(network
                .ipam
                .as_ref()
                .ok_or_else(|| NetworkSetupError::Logic {
                    message: format!("Network {FLECS_NETWORK_NAME} has no ipam"),
                })?
                .config
                .as_ref()
                .ok_or_else(|| NetworkSetupError::Logic {
                    message: format!("Network {FLECS_NETWORK_NAME} has no ipam config"),
                })?
                .first()
                .as_ref()
                .ok_or_else(|| NetworkSetupError::Logic {
                    message: format!("Network {FLECS_NETWORK_NAME} has no ipam config"),
                })?
                .gateway
                .as_ref()
                .ok_or_else(|| NetworkSetupError::Logic {
                    message: format!("Network {FLECS_NETWORK_NAME} has no gateway"),
                })?
                .parse()
                .map_err(NetworkSetupError::InvalidIpv4)?)
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {
            let adapters = ifaddr::try_read_network_adapters()?;
            let existing_ip_addresses: Vec<IpAddr> = adapters
                .into_values()
                .flat_map(|adapter| adapter.ip_addresses.into_iter())
                .collect();
            let subnet = SUBNETS
                .iter()
                .find(|subnet| {
                    existing_ip_addresses.iter().all(|existing_ip_address| {
                        network_contains_ip(**subnet, *existing_ip_address)
                    })
                })
                .ok_or_else(|| NetworkSetupError::Logic {
                    message: format!("No free subnet found for network {FLECS_NETWORK_NAME}"),
                })?;
            let gateway = subnet.0 | Ipv4Addr::new(0, 0, 0, 1);
            let subnet = format!("{}/{}", subnet.0, subnet.1);
            docker_client
                .create_network(NetworkCreateRequest {
                    name: FLECS_NETWORK_NAME.to_string(),
                    driver: Some("bridge".to_string()),
                    ipam: Some(Ipam {
                        config: Some(vec![IpamConfig {
                            gateway: Some(gateway.to_string()),
                            subnet: Some(subnet),
                            ..IpamConfig::default()
                        }]),
                        ..Ipam::default()
                    }),
                    ..NetworkCreateRequest::default()
                })
                .await?;
            Ok(gateway)
        }
        Err(e) => Err(NetworkSetupError::from(e)),
    }
}
