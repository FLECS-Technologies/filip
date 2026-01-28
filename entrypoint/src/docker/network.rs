use crate::info;
use bollard::Docker;
use bollard::config::{Ipam, IpamConfig, NetworkCreateRequest};
use std::borrow::Cow;
use std::net::Ipv4Addr;
use std::str::FromStr;

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

fn network_contains_ip(network: Network, ip: Ipv4Addr) -> bool {
    let subnet_mask = Ipv4Addr::from(0xffffffff << (32 - network.1));
    subnet_mask & ip == network.0
}

fn parse_ifconfig_output(output: Cow<str>) -> Vec<Ipv4Addr> {
    output
        .lines()
        .filter_map(|line| {
            if line.contains("inet6") || !line.contains("inet") {
                None
            } else {
                let mut tokens = line.split_ascii_whitespace();
                while let Some(token) = tokens.next() {
                    if token == "inet"
                        && let Some(ip_token) = tokens.next()
                        && let Ok(ip) = Ipv4Addr::from_str(ip_token)
                    {
                        return Some(ip);
                    }
                }
                None
            }
        })
        .collect()
}

async fn get_existing_ip_addresses() -> Vec<Ipv4Addr> {
    // TODO: Find portable way
    let result = tokio::process::Command::new("ifconfig")
        .arg("-a")
        .output()
        .await
        .unwrap();
    if !result.status.success() {
        panic!("Failed to execute ifconfig");
    }
    let output = String::from_utf8_lossy(&result.stdout);
    parse_ifconfig_output(output)
}

pub async fn create_network(docker_client: &Docker) -> Result<Ipv4Addr, bollard::errors::Error> {
    let existing_ip_addresses = get_existing_ip_addresses().await;
    info!("Found ip addresses: {existing_ip_addresses:#?}");
    match docker_client
        .inspect_network(FLECS_NETWORK_NAME, None)
        .await
    {
        Ok(network) => {
            info!("Reusing existing network {FLECS_NETWORK_NAME}");
            // TODO: Handle errors
            Ok(network
                .ipam
                .as_ref()
                .unwrap()
                .config
                .as_ref()
                .unwrap()
                .first()
                .as_ref()
                .unwrap()
                .gateway
                .as_ref()
                .unwrap()
                .parse()
                .unwrap())
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {
            let subnet = SUBNETS
                .iter()
                .find(|subnet| {
                    existing_ip_addresses.iter().all(|existing_ip_address| {
                        network_contains_ip(**subnet, *existing_ip_address)
                    })
                })
                // TODO: Handle error
                .unwrap();
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
        Err(e) => Err(e),
    }
}
