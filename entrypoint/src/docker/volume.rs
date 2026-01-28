use crate::info;
use bollard::Docker;
use bollard::config::VolumeCreateRequest;
use std::collections::HashMap;

pub const FLOXY_DATA_VOLUME: &str = "flecs-floxy_data";
pub const FLOXY_CERT_VOLUME: &str = "flecs-floxy_certs";

pub async fn create_floxy_data_volume(
    docker_client: &Docker,
) -> Result<(), bollard::errors::Error> {
    match docker_client.inspect_volume(FLOXY_DATA_VOLUME).await {
        Ok(_) => {
            info!("Reusing existing volume {FLOXY_DATA_VOLUME}");
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {
            docker_client
                .create_volume(VolumeCreateRequest {
                    name: Some(FLOXY_DATA_VOLUME.to_string()),
                    driver: Some("local".to_string()),
                    driver_opts: Some(HashMap::from([
                        ("type".to_string(), "tmpfs".to_string()),
                        ("device".to_string(), "tmpfs".to_string()),
                        ("o".to_string(), "size=4m".to_string()),
                    ])),
                    ..VolumeCreateRequest::default()
                })
                .await?;
        }
        Err(e) => {
            return Err(e);
        }
    }
    Ok(())
}
