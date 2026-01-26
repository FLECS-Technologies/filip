use std::time::Duration;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    println!("Hello");
    // TODO: Initialize signal handler
    // TODO: Start flecs-core, flecs-webapp and flecs-floxy
    // TODO: Wait for signal
    // TODO: Shutdown flecs-core, flecs-webapp and flecs-floxy
    tokio::time::sleep(Duration::from_secs(1)).await;
    println!("Goodbye");
}
