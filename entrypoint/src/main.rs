use std::thread::sleep;
use std::time::Duration;

fn main() {
    println!("Hello");
    // TODO: Initialize signal handler
    // TODO: Start flecs-core, flecs-webapp and flecs-floxy
    // TODO: Wait for signal
    // TODO: Shutdown flecs-core, flecs-webapp and flecs-floxy
    sleep(Duration::from_secs(1));
    println!("Goodbye");
}
