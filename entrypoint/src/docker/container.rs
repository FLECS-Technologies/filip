use crate::docker::container::config::{
    core_container_config, floxy_container_config, webapp_container_config,
};
use crate::{error, warn};
use bollard::Docker;
use bollard::auth::DockerCredentials;
use bollard::query_parameters::{CreateImageOptions, RemoveContainerOptions, StopContainerOptions};
use config::ContainerConfig;
use futures_util::TryStreamExt;
use std::net::Ipv4Addr;

const CORE_CONTAINER_NAME: &str = "flecs-flecsd";
const CORE_VOLUME: &str = "flecsd";
const WEBAPP_CONTAINER_NAME: &str = "flecs-webapp";
const FLOXY_CONTAINER_NAME: &str = "flecs-floxy";
mod config;

#[derive(thiserror::Error, Debug)]
pub enum CreateContainerError {
    #[error(transparent)]
    Bollard(#[from] bollard::errors::Error),
    #[error("Logic error during container creation: {message}")]
    Logic { message: String },
}

pub async fn pull(
    docker_client: &Docker,
    credentials: Option<DockerCredentials>,
    image: String,
    tag: Option<String>,
) -> Result<(), bollard::errors::Error> {
    let options = Some(CreateImageOptions {
        from_image: Some(image),
        tag,
        ..Default::default()
    });

    docker_client
        .create_image(options, None, credentials)
        .try_for_each(|_| async { Ok(()) })
        .await
}

async fn re_create_container(
    docker_client: &Docker,
    config: ContainerConfig,
) -> Result<String, CreateContainerError> {
    let image_with_tag = config
        .1
        .image
        .clone()
        .ok_or_else(|| CreateContainerError::Logic {
            message: "Container config contains no image".to_string(),
        })?;
    let container_name = config
        .0
        .name
        .clone()
        .ok_or_else(|| CreateContainerError::Logic {
            message: "Container config contains no container name".to_string(),
        })?;
    let (image, tag) = match image_with_tag.split_once(':') {
        None => (image_with_tag.clone(), None),
        Some((image, tag)) => (image.to_string(), Some(tag.to_string())),
    };
    if let Err(pull_error) = pull(docker_client, None, image.to_string(), tag).await {
        match docker_client.inspect_image(&image_with_tag).await {
            Ok(_) => {
                warn!("Reusing local copy of {image_with_tag}, failed to pull: ({pull_error}), ")
            }
            Err(bollard::errors::Error::DockerResponseServerError {
                status_code: 404, ..
            }) => {
                warn!("Failed to pull image {image_with_tag} and no local copy exists");
            }
            Err(inspect_error) => {
                error!("Failed to inspect local image of {image_with_tag}: {inspect_error}");
                return Err(CreateContainerError::from(pull_error));
            }
        }
    };
    match docker_client.inspect_container(&container_name, None).await {
        Ok(_) => {
            warn!("Removing existing container {container_name}");
            docker_client
                .remove_container(
                    FLOXY_CONTAINER_NAME,
                    Some(RemoveContainerOptions {
                        force: true,
                        ..RemoveContainerOptions::default()
                    }),
                )
                .await?;
        }
        Err(bollard::errors::Error::DockerResponseServerError {
            status_code: 404, ..
        }) => {}
        Err(e) => return Err(CreateContainerError::from(e)),
    }
    let response = docker_client
        .create_container(Some(config.0), config.1)
        .await?;
    for warning in response.warnings {
        warn!("{warning}");
    }
    Ok(response.id)
}

pub async fn create_containers(
    docker_client: &Docker,
    gateway: Ipv4Addr,
) -> Result<(), CreateContainerError> {
    // TODO: Determine free http port, free https port
    let http_port = 80;
    let https_port = 443;
    let [first_octet, second_octet, _, _] = gateway.octets();
    let webapp_ip = Ipv4Addr::new(first_octet, second_octet, 255, 254);

    // floxy
    let config = floxy_container_config(http_port, https_port, gateway);
    re_create_container(docker_client, config).await?;

    // core
    let config = core_container_config();
    re_create_container(docker_client, config).await?;

    // webapp
    let config = webapp_container_config(webapp_ip, gateway);
    re_create_container(docker_client, config).await?;

    Ok(())
}

pub async fn start_containers(docker_client: &Docker) -> Result<(), bollard::errors::Error> {
    docker_client
        .start_container(FLOXY_CONTAINER_NAME, None)
        .await?;
    docker_client
        .start_container(CORE_CONTAINER_NAME, None)
        .await?;
    docker_client
        .start_container(WEBAPP_CONTAINER_NAME, None)
        .await?;
    Ok(())
}

pub async fn remove_containers(docker_client: &Docker) -> Result<(), bollard::errors::Error> {
    let options = Some(RemoveContainerOptions {
        force: true,
        ..RemoveContainerOptions::default()
    });
    docker_client
        .remove_container(FLOXY_CONTAINER_NAME, options.clone())
        .await?;
    docker_client
        .remove_container(CORE_CONTAINER_NAME, options.clone())
        .await?;
    docker_client
        .remove_container(WEBAPP_CONTAINER_NAME, options)
        .await?;
    Ok(())
}

pub async fn stop_containers(docker_client: &Docker) -> Result<(), bollard::errors::Error> {
    let options = Some(StopContainerOptions {
        t: Some(120),
        ..StopContainerOptions::default()
    });
    docker_client
        .stop_container(FLOXY_CONTAINER_NAME, options.clone())
        .await?;
    docker_client
        .stop_container(CORE_CONTAINER_NAME, options.clone())
        .await?;
    docker_client
        .stop_container(WEBAPP_CONTAINER_NAME, options)
        .await?;
    Ok(())
}
