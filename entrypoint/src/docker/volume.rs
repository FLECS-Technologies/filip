use crate::info;
use bollard::Docker;
use bollard::config::VolumeCreateRequest;
use std::collections::HashMap;

pub const FLOXY_DATA_VOLUME: &str = "flecs-floxy_data";
pub const FLOXY_CERT_VOLUME: &str = "flecs-floxy_certs";
pub const OTEL_CERTS_VOLUME: &str = "flecs-otelcol_certs";
pub const OTEL_LOGS_VOLUME: &str = "flecs-otelcol_logs";

async fn create_tmpfs_volume(
    docker_client: &Docker,
    name: &str,
    size: &str,
) -> Result<(), bollard::errors::Error> {
    match docker_client.inspect_volume(name).await {
        Ok(_) => {
            info!("Reusing existing volume {name}");
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {
            docker_client
                .create_volume(VolumeCreateRequest {
                    name: Some(name.to_string()),
                    driver: Some("local".to_string()),
                    driver_opts: Some(HashMap::from([
                        ("type".to_string(), "tmpfs".to_string()),
                        ("device".to_string(), "tmpfs".to_string()),
                        ("o".to_string(), format!("size={size}")),
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

pub async fn create_floxy_data_volume(
    docker_client: &Docker,
) -> Result<(), bollard::errors::Error> {
    create_tmpfs_volume(docker_client, FLOXY_DATA_VOLUME, "4m").await
}

pub async fn create_otel_certs_volume(
    docker_client: &Docker,
) -> Result<(), bollard::errors::Error> {
    create_tmpfs_volume(docker_client, OTEL_CERTS_VOLUME, "1m").await
}

pub async fn create_otel_logs_volume(docker_client: &Docker) -> Result<(), bollard::errors::Error> {
    match docker_client.inspect_volume(OTEL_LOGS_VOLUME).await {
        Ok(_) => {
            info!("Reusing existing volume {OTEL_LOGS_VOLUME}");
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {
            docker_client
                .create_volume(VolumeCreateRequest {
                    name: Some(OTEL_LOGS_VOLUME.to_string()),
                    driver: Some("local".to_string()),
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
