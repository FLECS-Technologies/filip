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

#[tokio::main(flavor = "current_thread")]
async fn main() -> std::io::Result<()> {
    info!("Hello");
    let stop_signal = init_signal_handler()?;
    // TODO: Handle errors instead of unwrapping
    let docker_client = docker_client().unwrap();
    let gateway = create_network(&docker_client).await.unwrap();
    create_floxy_data_volume(&docker_client).await.unwrap();
    create_containers(&docker_client.clone(), gateway)
        .await
        .unwrap();
    start_containers(&docker_client).await.unwrap();
    stop_signal
        .await
        .expect("The sending side is never dropped before sending");
    info!("Stopping containers...");
    stop_containers(&docker_client).await.unwrap();
    info!("...stopped containers");
    info!("Removing containers...");
    remove_containers(&docker_client).await.unwrap();
    info!("...removed containers");
    info!("Goodbye");
    Ok(())
}
