use async_signal::{Signal, Signals};
use futures_util::StreamExt;

mod logging;

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
    // TODO: Start flecs-core, flecs-webapp and flecs-floxy
    stop_signal
        .await
        .expect("The sending side is never dropped before sending");
    // TODO: Shutdown flecs-core, flecs-webapp and flecs-floxy
    info!("Goodbye");
    Ok(())
}
