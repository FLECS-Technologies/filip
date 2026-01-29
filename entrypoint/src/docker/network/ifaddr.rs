use crate::warn;
use libc::{
    AF_INET, AF_INET6, AF_PACKET, freeifaddrs, getifaddrs, ifaddrs, sockaddr_in, sockaddr_in6,
    sockaddr_ll,
};
use procfs::ProcError;
use procfs::net::RouteEntry;
use std::collections::HashMap;
use std::ffi::CStr;
use std::fmt::{Display, Formatter};
use std::mem::MaybeUninit;
use std::net::{AddrParseError, IpAddr, Ipv4Addr, Ipv6Addr};
use std::num::ParseIntError;
use std::str::FromStr;
type Result<T> = std::result::Result<T, ReadNetworkAdaptersError>;

#[derive(thiserror::Error, Debug)]
pub enum ReadNetworkAdaptersError {
    #[error(transparent)]
    IO(#[from] std::io::Error),
    #[error(transparent)]
    InvalidAddress(#[from] AddrParseError),
    #[error(transparent)]
    InvalidInt(#[from] ParseIntError),
    #[error(transparent)]
    Procfs(#[from] ProcError),
    #[error("Property {0} is null")]
    PropertyNull(&'static str),
    #[error("SaFamily '{0}' unsupported")]
    UnsupportedSaFamily(u16),
    #[error("{0}")]
    Other(String),
}

pub fn try_read_network_adapters() -> Result<HashMap<String, NetworkAdapter>> {
    NetworkAdapter::try_read_from_system(IfAddrs::new()?)
}

#[derive(Debug, Default, Clone, PartialEq)]
pub enum NetType {
    #[default]
    Unknown,
    Wired,
    Wireless,
    Local,
    Bridge,
    Virtual,
}

impl From<&str> for NetType {
    fn from(value: &str) -> Self {
        match value {
            v if v.starts_with("en") || v.starts_with("eth") => Self::Wired,
            v if v.starts_with("wl") => Self::Wireless,
            v if v.starts_with("lo") => Self::Local,
            v if v.starts_with("veth") => Self::Virtual,
            v if v.starts_with("br") || v.starts_with("docker") => Self::Bridge,
            _ => Self::Unknown,
        }
    }
}

#[derive(Copy, Clone, Eq, PartialEq, Debug)]
pub struct Ipv4Network {
    address: Ipv4Addr,
    size: u8,
}

impl Ipv4Network {
    pub const fn default() -> Self {
        Self {
            address: Ipv4Addr::new(172, 21, 0, 0),
            size: 16,
        }
    }

    pub fn try_new(address: Ipv4Addr, size: u8) -> Result<Self> {
        if size > 32 {
            return Err(ReadNetworkAdaptersError::Other(format!(
                "Network size has to be 32 or less, not {size}"
            )));
        }
        let mask = Ipv4Addr::from(0xffffffff_u32.checked_shr(size as u32).unwrap_or_default());
        if (address & mask) != Ipv4Addr::UNSPECIFIED {
            return Err(ReadNetworkAdaptersError::Other(format!(
                "Address part of network {address}/{size} is not 0"
            )));
        }
        Ok(Self { address, size })
    }

    pub fn new_from_address_and_subnet_mask(
        address: Ipv4Addr,
        subnet_mask: Ipv4Addr,
    ) -> Result<Self> {
        let size = u32::from(subnet_mask).count_ones();
        Self::try_new(address & subnet_mask, size as u8)
    }
}

impl Default for Ipv4Network {
    fn default() -> Self {
        Ipv4Network::default()
    }
}

impl FromStr for Ipv4Network {
    type Err = ReadNetworkAdaptersError;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        let (address, size) = s
            .split_once('/')
            .ok_or_else(|| ReadNetworkAdaptersError::Other("No '/' found".to_string()))?;
        Ipv4Network::try_new(Ipv4Addr::from_str(address)?, u8::from_str(size)?)
    }
}

impl Display for Ipv4Network {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}/{}", self.address, self.size)
    }
}
#[derive(Copy, Clone, Eq, PartialEq, Debug)]
pub struct Ipv6Network {
    pub address: Ipv6Addr,
    prefix_len: u8,
}

impl Ipv6Network {
    pub fn new(address: Ipv6Addr, prefix_len: u8) -> Self {
        Self {
            address,
            prefix_len,
        }
    }

    pub fn new_from_address_and_subnet_mask(address: Ipv6Addr, subnet_mask: Ipv6Addr) -> Self {
        let suffix = subnet_mask
            .octets()
            .iter()
            .fold(0, |acc, x| acc + x.count_ones());
        Self::new(address & subnet_mask, suffix as u8)
    }
}

impl FromStr for Ipv6Network {
    type Err = ReadNetworkAdaptersError;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        let (address, size) = s
            .split_once('/')
            .ok_or_else(|| ReadNetworkAdaptersError::Other("No '/' found".to_string()))?;
        Ok(Ipv6Network::new(
            Ipv6Addr::from_str(address)?,
            u8::from_str(size)?,
        ))
    }
}

impl Display for Ipv6Network {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}/{}", self.address, self.prefix_len)
    }
}
#[derive(Debug, Clone, PartialEq)]
pub struct NetworkAdapter {
    pub name: String,
    pub mac: Option<String>,
    pub net_type: NetType,
    pub ipv4_networks: Vec<Ipv4Network>,
    pub ipv6_networks: Vec<Ipv6Network>,
    pub ip_addresses: Vec<IpAddr>,
    pub gateway: Option<Ipv4Addr>,
}

enum SaFamily {
    Unsupported(u16),
    Packet,
    Inet4,
    Inet6,
}

impl From<u16> for SaFamily {
    fn from(value: u16) -> Self {
        match value {
            x if x as i32 == AF_INET => SaFamily::Inet4,
            x if x as i32 == AF_INET6 => SaFamily::Inet6,
            x if x as i32 == AF_PACKET => SaFamily::Packet,
            x => SaFamily::Unsupported(x),
        }
    }
}

pub struct IfAddrs {
    inner: *mut ifaddrs,
}

#[derive(Debug, PartialEq, Clone)]
struct IfAddrsReadResult {
    name: String,
    address: IfAddrsReadResultAddress,
}

#[derive(Debug, PartialEq, Clone)]
enum IfAddrsReadResultAddress {
    Mac(String),
    Ipv4 {
        address: Ipv4Addr,
        subnet_mask: Ipv4Addr,
    },
    Ipv6 {
        address: Ipv6Addr,
        subnet_mask: Ipv6Addr,
    },
}

impl TryFrom<ifaddrs> for IfAddrsReadResult {
    type Error = ReadNetworkAdaptersError;

    fn try_from(value: ifaddrs) -> Result<Self> {
        if value.ifa_addr.is_null() {
            return Err(ReadNetworkAdaptersError::PropertyNull("ifa_addr"));
        }
        let sa_family: SaFamily = unsafe { *value.ifa_addr }.sa_family.into();
        let name = unsafe { CStr::from_ptr(value.ifa_name as *const _) }
            .to_string_lossy()
            .into_owned();
        match sa_family {
            SaFamily::Unsupported(val) => Err(Self::Error::UnsupportedSaFamily(val)),
            SaFamily::Packet => {
                let s = unsafe { *(value.ifa_addr as *const sockaddr_ll) };
                let mac = format!(
                    "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
                    s.sll_addr[0],
                    s.sll_addr[1],
                    s.sll_addr[2],
                    s.sll_addr[3],
                    s.sll_addr[4],
                    s.sll_addr[5]
                );

                Ok(IfAddrsReadResult {
                    name,
                    address: IfAddrsReadResultAddress::Mac(mac),
                })
            }
            SaFamily::Inet4 => {
                let s = unsafe { *(value.ifa_addr as *const sockaddr_in) };
                let address: Ipv4Addr = u32::from_be(s.sin_addr.s_addr).into();
                let s = unsafe { *(value.ifa_netmask as *const sockaddr_in) };
                let subnet_mask: Ipv4Addr = u32::from_be(s.sin_addr.s_addr).into();
                Ok(IfAddrsReadResult {
                    name,
                    address: IfAddrsReadResultAddress::Ipv4 {
                        address,
                        subnet_mask,
                    },
                })
            }
            SaFamily::Inet6 => {
                let s = unsafe { *(value.ifa_addr as *const sockaddr_in6) };
                let address: Ipv6Addr = s.sin6_addr.s6_addr.into();
                let s = unsafe { *(value.ifa_netmask as *const sockaddr_in6) };
                let subnet_mask: Ipv6Addr = s.sin6_addr.s6_addr.into();
                Ok(IfAddrsReadResult {
                    name,
                    address: IfAddrsReadResultAddress::Ipv6 {
                        address,
                        subnet_mask,
                    },
                })
            }
        }
    }
}

impl IfAddrs {
    #[allow(unsafe_code, clippy::new_ret_no_self)]
    pub fn new() -> std::io::Result<Self> {
        let mut ifaddrs: MaybeUninit<*mut ifaddrs> = MaybeUninit::uninit();

        let ifaddrs = unsafe {
            if -1 == getifaddrs(ifaddrs.as_mut_ptr()) {
                return Err(std::io::Error::last_os_error());
            }
            ifaddrs.assume_init()
        };

        Ok(Self { inner: ifaddrs })
    }
}

impl IntoIterator for IfAddrs {
    type Item = ifaddrs;
    type IntoIter = IfAddrsIterator;

    fn into_iter(self) -> Self::IntoIter {
        IfAddrsIterator {
            next: self.inner,
            _source: self,
        }
    }
}

impl Drop for IfAddrs {
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        if !self.inner.is_null() {
            unsafe {
                freeifaddrs(self.inner);
            }
        }
    }
}

pub struct IfAddrsIterator {
    _source: IfAddrs,
    next: *mut ifaddrs,
}

impl Iterator for IfAddrsIterator {
    type Item = ifaddrs;

    #[allow(unsafe_code)]
    fn next(&mut self) -> Option<Self::Item> {
        if self.next.is_null() {
            return None;
        };

        Some(unsafe {
            let result = *self.next;
            self.next = (*self.next).ifa_next;

            result
        })
    }
}

impl NetworkAdapter {
    fn try_read_from_system(if_addrs: IfAddrs) -> Result<HashMap<String, Self>> {
        let mut adapters: HashMap<String, Self> = HashMap::new();
        let addresses = if_addrs
            .into_iter()
            .filter_map(|if_addrs| IfAddrsReadResult::try_from(if_addrs).ok());
        let route_entries = procfs::net::route()?
            .into_iter()
            .filter(|route_entry| route_entry.destination.is_unspecified());
        for result in addresses {
            let entry = adapters
                .entry(result.name.clone())
                .or_insert(Self::new(result.name.clone()));
            match result {
                IfAddrsReadResult {
                    address: IfAddrsReadResultAddress::Mac(mac),
                    ..
                } => entry.mac = Some(mac),
                IfAddrsReadResult {
                    address:
                        IfAddrsReadResultAddress::Ipv4 {
                            address,
                            subnet_mask,
                        },
                    ..
                } => {
                    match Ipv4Network::new_from_address_and_subnet_mask(address, subnet_mask) {
                        Ok(network) => entry.ipv4_networks.push(network),
                        Err(e) => warn!(
                            "Invalid ipv4 network with address {address} and subnet mask {subnet_mask}: {e}"
                        ),
                    }
                    entry.ip_addresses.push(address.into());
                }
                IfAddrsReadResult {
                    address:
                        IfAddrsReadResultAddress::Ipv6 {
                            address,
                            subnet_mask,
                        },
                    ..
                } => {
                    entry
                        .ipv6_networks
                        .push(Ipv6Network::new_from_address_and_subnet_mask(
                            address,
                            subnet_mask,
                        ));
                    entry.ip_addresses.push(address.into());
                }
            }
        }
        for RouteEntry { iface, gateway, .. } in route_entries {
            let entry = adapters.entry(iface.clone()).or_insert(Self::new(iface));
            entry.gateway = Some(gateway);
        }
        Ok(adapters)
    }

    fn new(name: String) -> Self {
        Self {
            net_type: name.as_str().into(),
            ipv6_networks: Vec::new(),
            ipv4_networks: Vec::new(),
            gateway: None,
            name,
            mac: None,
            ip_addresses: Vec::new(),
        }
    }
}
