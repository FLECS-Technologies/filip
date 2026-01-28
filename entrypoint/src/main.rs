use async_signal::{Signal, Signals};
use futures_util::StreamExt;

mod docker;
mod logging;
use crate::docker::container::{
    create_containers, remove_containers, start_containers, stop_containers,
};
use crate::docker::docker_client;
use crate::docker::volume::create_floxy_data_volume;
use docker::network::create_network;

fn init_signal_handler() -> std::io::Result<tokio::sync::oneshot::Receiver<()>> {
    let (result_sender, result_receiver) = tokio::sync::oneshot::channel();
    let mut signals = Signals::new([Signal::Term, Signal::Int, Signal::Quit])?;
    tokio::spawn(async move {
        info!("Signal handler was initialized");
        while let Some(signal) = signals.next().await {
            info!("Received signal {signal:?}");
            if matches!(
                signal,
                Ok(Signal::Int) | Ok(Signal::Term) | Ok(Signal::Quit)
            ) {
                result_sender.send(()).unwrap();
                break;
            }
        }
    });
    Ok(result_receiver)
}

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
