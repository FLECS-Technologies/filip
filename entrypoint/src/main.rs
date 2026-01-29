mod docker;
mod logging;
mod signal;
use crate::docker::container::{
    create_containers, remove_containers, start_containers, stop_containers,
};
use crate::docker::docker_client;
use crate::docker::network::network_setup;
use crate::docker::volume::create_floxy_data_volume;
use crate::signal::init_signal_handler;

#[derive(thiserror::Error, Debug)]
enum Error {
    #[error(transparent)]
    IO(#[from] std::io::Error),
    #[error(transparent)]
    Bollard(#[from] bollard::errors::Error),
    #[error(transparent)]
    NetworkSetup(#[from] docker::network::NetworkSetupError),
    #[error(transparent)]
    CreateContainer(#[from] docker::container::CreateContainerError),
}

type Result<T> = std::result::Result<T, Error>;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let stop_signal = init_signal_handler()?;
    let docker_client = docker_client()?;

    info!("Cleanup of any leftover containers");
    stop_containers(&docker_client).await?;
    remove_containers(&docker_client).await?;

    info!("Network setup");
    let network_info = network_setup(&docker_client).await?;

    info!("Volume creation");
    create_floxy_data_volume(&docker_client).await?;

    info!("Container creation");
    create_containers(&docker_client.clone(), network_info).await?;

    info!("Container startup");
    start_containers(&docker_client).await?;
    info!("FLECS is up and running");

    stop_signal
        .await
        .expect("The sending side is never dropped before sending");
    info!("Stopping containers...");
    stop_containers(&docker_client).await?;
    info!("...stopped containers");
    info!("Removing containers...");
    remove_containers(&docker_client).await?;
    info!("...removed containers");
    Ok(())
}
