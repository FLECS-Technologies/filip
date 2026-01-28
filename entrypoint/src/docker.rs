use bollard::Docker;

pub mod container;
pub mod network;
pub mod volume;

pub fn docker_client() -> Result<Docker, bollard::errors::Error> {
    Docker::connect_with_socket_defaults()
}
