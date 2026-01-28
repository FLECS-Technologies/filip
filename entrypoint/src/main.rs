mod docker;
mod logging;
mod signal;
use crate::docker::container::{
    create_containers, remove_containers, start_containers, stop_containers,
};
use crate::docker::docker_client;
use crate::docker::volume::create_floxy_data_volume;
use crate::signal::init_signal_handler;
use docker::network::create_network;

#[derive(thiserror::Error, Debug)]
enum Error {
    #[error(transparent)]
    IO(#[from] std::io::Error),
    #[error(transparent)]
    Bollard(#[from] bollard::errors::Error),
}

type Result<T> = std::result::Result<T, Error>;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    info!("Hello");
    let stop_signal = init_signal_handler()?;
    let docker_client = docker_client()?;
    let gateway = create_network(&docker_client).await?;
    create_floxy_data_volume(&docker_client).await?;
    create_containers(&docker_client.clone(), gateway).await?;
    start_containers(&docker_client).await?;
    stop_signal
        .await
        .expect("The sending side is never dropped before sending");
    info!("Stopping containers...");
    stop_containers(&docker_client).await?;
    info!("...stopped containers");
    info!("Removing containers...");
    remove_containers(&docker_client).await?;
    info!("...removed containers");
    info!("Goodbye");
    Ok(())
}
