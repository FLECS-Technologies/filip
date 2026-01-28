use crate::info;
use async_signal::{Signal, Signals};
use futures_util::StreamExt;

pub fn init_signal_handler() -> std::io::Result<tokio::sync::oneshot::Receiver<()>> {
    let (result_sender, result_receiver) = tokio::sync::oneshot::channel();
    let mut signals = Signals::new([Signal::Term, Signal::Int])?;
    tokio::spawn(async move {
        info!("Signal handler was initialized");
        while let Some(signal) = signals.next().await {
            info!("Received signal {signal:?}");
            if matches!(signal, Ok(Signal::Int) | Ok(Signal::Term)) {
                result_sender.send(()).unwrap();
                break;
            }
        }
    });
    Ok(result_receiver)
}
