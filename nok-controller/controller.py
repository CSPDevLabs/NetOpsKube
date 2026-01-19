import os
import logging
import time
from kubernetes import client, config, watch
import consul

# --- Configuration ---
# Kubernetes CRD details for Target
TARGET_CRD_GROUP = "inv.sdcio.dev"
TARGET_CRD_VERSION = "v1alpha1"
TARGET_CRD_PLURAL = "targets"

# Consul configuration
# Default to Consul service in 'nok-base' namespace, adjust if different
# This variable will now be parsed more flexibly by the script
CONSUL_HTTP_ADDR = os.getenv("CONSUL_HTTP_ADDR", "http://consul-svc-nok-base.nok-base.svc.cluster.local:8500")
CONSUL_HTTP_TOKEN = os.getenv("CONSUL_HTTP_TOKEN") # Optional: Set if Consul ACLs are enabled
CONSUL_SERVICE_PORT = int(os.getenv("CONSUL_SERVICE_PORT", "57400")) # Default gNMI port, adjust as needed

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class TargetConsulSyncController:
    def __init__(self):
        # Load Kubernetes configuration
        try:
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes configuration.")
        except config.ConfigException:
            try:
                config.load_kube_config()
                logger.info("Loaded kubeconfig from file system (for local development).")
            except config.ConfigException:
                logger.error("Could not configure Kubernetes client. Exiting.")
                raise

        self.k8s_api = client.CustomObjectsApi()
        self.k8s_watch = watch.Watch()

        # Initialize Consul client with robust parsing
        consul_url = CONSUL_HTTP_ADDR # This will be the value from env or default
        
        # Default scheme to http if not present in the URL
        if '://' not in consul_url:
            consul_scheme = 'http'
            address_part = consul_url
        else:
            consul_scheme, address_part = consul_url.split('://', 1)

        # Split address_part into host and port
        if ':' in address_part:
            consul_host, consul_port_str = address_part.rsplit(':', 1)
            try:
                consul_port = int(consul_port_str)
            except ValueError:
                logger.warning(f"Invalid port '{consul_port_str}' in CONSUL_HTTP_ADDR. Defaulting to 8500.")
                consul_port = 8500 # Default Consul HTTP port
        else:
            # Assume default Consul port if not specified
            consul_host = address_part
            consul_port = 8500 # Default Consul HTTP port

        self.consul_client = consul.Consul(
            host=consul_host,
            port=consul_port,
            scheme=consul_scheme,
            token=CONSUL_HTTP_TOKEN
        )
        logger.info(f"Initialized Consul client for {consul_url}")

    def _is_target_ready(self, target_obj):
        """Checks if the Target resource has a 'Ready' condition with status 'True'."""
        status = target_obj.get('status')
        if not status:
            return False
        conditions = status.get('conditions')
        if not conditions:
            return False
        for condition in conditions:
            if condition.get('type') == 'Ready' and condition.get('status') == 'True':
                return True
        return False

    def _register_consul_service(self, target_name, target_namespace, target_address, tags=None):
        """Registers or updates a service in Consul."""
        service_id = f"{target_name}-{target_namespace}" # Unique ID for Consul
        service_name = target_name # Using target name as Consul service name
        
        try:
            self.consul_client.agent.service.register(
                name=service_name,
                service_id=service_id, # Use 'service_id' as per python-consul API
                address=target_address,
                port=CONSUL_SERVICE_PORT,
                tags=tags if tags else [],
                # Removed 'meta' argument as it's not supported by this consul-python version
            )
            logger.info(f"Registered/Updated Consul service '{service_name}' (ID: {service_id}) at {target_address}:{CONSUL_SERVICE_PORT} with tags {tags}")
        except Exception as e:
            logger.error(f"Failed to register/update Consul service '{service_name}' (ID: {service_id}): {e}")

    def _deregister_consul_service(self, target_name, target_namespace):
        """Deregisters a service from Consul."""
        service_id = f"{target_name}-{target_namespace}"
        try:
            self.consul_client.agent.service.deregister(service_id)
            logger.info(f"Deregistered Consul service ID '{service_id}'")
        except Exception as e:
            logger.error(f"Failed to deregister Consul service ID '{service_id}': {e}")

    def run(self):
        """Starts watching for Target CRD events and syncs to Consul."""
        logger.info(f"Starting watch for Target CRD: {TARGET_CRD_GROUP}/{TARGET_CRD_VERSION}/{TARGET_CRD_PLURAL}")
        while True:
            try:
                # Watch for cluster-scoped custom objects (Targets)
                for event in self.k8s_watch.stream(
                    self.k8s_api.list_cluster_custom_object,
                    group=TARGET_CRD_GROUP,
                    version=TARGET_CRD_VERSION,
                    plural=TARGET_CRD_PLURAL,
                    _preload_content=False # Important for streaming large objects
                ):
                    event_type = event['type']
                    target_obj = event['object']
                    
                    target_name = target_obj['metadata']['name']
                    target_namespace = target_obj['metadata']['namespace']
                    target_address = target_obj['spec'].get('address')
                    
                    # Extract tags from labels, e.g., sdcio.dev/region
                    tags = []
                    if target_obj['metadata'].get('labels'):
                        region = target_obj['metadata']['labels'].get('sdcio.dev/region')
                        if region:
                            tags.append(f"region:{region}")
                        # Add other relevant labels as tags if desired
                        # Example: provider = target_obj['metadata']['labels'].get('inv.sdcio.dev/provider')
                        # if provider: tags.append(f"provider:{provider}")

                    logger.debug(f"Processing event: {event_type} for Target {target_namespace}/{target_name}")

                    if not target_address:
                        logger.warning(f"Target {target_namespace}/{target_name} has no 'spec.address'. Skipping.")
                        continue

                    if event_type == 'ADDED' or event_type == 'MODIFIED':
                        if self._is_target_ready(target_obj):
                            self._register_consul_service(target_name, target_namespace, target_address, tags)
                        else:
                            logger.info(f"Target {target_namespace}/{target_name} is not 'Ready'. Deregistering if exists or skipping registration.")
                            self._deregister_consul_service(target_name, target_namespace)
                    elif event_type == 'DELETED':
                        self._deregister_consul_service(target_name, target_namespace)
                    else:
                        logger.warning(f"Unknown event type: {event_type} for Target {target_namespace}/{target_name}")

            except client.ApiException as e:
                logger.error(f"Kubernetes API error: {e}. Retrying in 5 seconds.")
                time.sleep(5) # Wait before retrying
            except Exception as e:
                logger.error(f"An unexpected error occurred: {e}. Retrying in 5 seconds.")
                time.sleep(5) # Wait before retrying

if __name__ == "__main__":
    controller = TargetConsulSyncController()
    controller.run()