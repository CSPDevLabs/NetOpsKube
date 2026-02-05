import os
import logging
import time
from kubernetes import client, config, watch
import consul
import threading

# --- Configuration ---
# Kubernetes CRD details for Target
TARGET_CRD_GROUP = "inv.sdcio.dev"
TARGET_CRD_VERSION = "v1alpha1"
TARGET_CRD_PLURAL = "targets"

# Kubernetes CRD details for AdditionalTarget (NEW)
ADDITIONAL_TARGET_CRD_GROUP = "nok.dev"
ADDITIONAL_TARGET_CRD_VERSION = "v1alpha1"
ADDITIONAL_TARGET_CRD_PLURAL = "additionaltargets" # Plural name for your AdditionalTarget CRD

# Consul configuration
CONSUL_HTTP_ADDR = os.getenv("CONSUL_HTTP_ADDR", "http://consul-svc-nok-base.nok-base.svc.cluster.local:8500")
CONSUL_HTTP_TOKEN = os.getenv("CONSUL_HTTP_TOKEN")
CONSUL_SERVICE_PORT = int(os.getenv("CONSUL_SERVICE_PORT", "57400"))
ADDITIONAL_TARGET_TAG = 'additional-target'
TARGET_TAG = 'network-element'

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class TargetConsulSyncController:
    def __init__(self):
        try:
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes configuration.")
        except config.ConfigException:
            try:
                config.load_kube_config()
                logger.info("Loaded kubeconfig from file system for local development.")
            except config.ConfigException:
                logger.error("Could not configure Kubernetes client. Exiting.")
                raise

        self.k8s_api = client.CustomObjectsApi()
        self.k8s_watch = watch.Watch()

        consul_url = CONSUL_HTTP_ADDR
        consul_scheme = 'http'
        address_part = consul_url

        if '://' in consul_url:
            consul_scheme, address_part = consul_url.split('://', 1)

        consul_host = address_part
        consul_port = 8500

        if ':' in address_part:
            consul_host, consul_port_str = address_part.rsplit(':', 1)
            try:
                consul_port = int(consul_port_str)
            except ValueError:
                logger.warning(f"Invalid port '{consul_port_str}' in CONSUL_HTTP_ADDR. Defaulting to 8500.")

        self.consul_client = consul.Consul(
            host=consul_host,
            port=consul_port,
            scheme=consul_scheme,
            token=CONSUL_HTTP_TOKEN
        )
        logger.info(f"Initialized Consul client for {consul_url}")

    def _is_target_ready(self, target_obj: dict) -> bool:
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

    def _register_consul_service(self, service_id, service_name, address, port, tags=None):
        """Registers or updates a service in Consul."""
        try:
            self.consul_client.agent.service.register(
                name=service_name,
                service_id=service_id,
                address=address,
                port=port,
                tags=tags if tags else [],
            )
            logger.info(f"Registered/Updated Consul service '{service_name}' ID: {service_id} at {address}:{port} with tags {tags}")
        except Exception as e:
            logger.error(f"Failed to register/update Consul service '{service_name}' ID: {service_id}: {e}")

    def _deregister_consul_service(self, service_id):
        """Deregisters a service from Consul."""
        try:
            self.consul_client.agent.service.deregister(service_id)
            logger.info(f"Deregistered Consul service ID '{service_id}'")
        except Exception as e:
            logger.error(f"Failed to deregister Consul service ID '{service_id}': {e}")

    def _process_target_event(self, event_type, target_obj):
        """Processes events for Target CRDs."""
        target_name = target_obj['metadata']['name']
        target_namespace = target_obj['metadata']['namespace']
        target_address = target_obj['spec'].get('address')

        tags = [TARGET_TAG]
        if target_obj['metadata'].get('labels'):
            region = target_obj['metadata']['labels'].get('sdcio.dev/region')
            if region:
                tags.append(f"region:{region}")
            # Add a tag to identify the resource type
            tags.append("k8s-crd-type:target")
            # Example: provider = target_obj['metadata']['labels'].get('inv.sdcio.dev/provider')
            # if provider: tags.append(f"provider:{provider}")

        logger.debug(f"Processing event: {event_type} for Target {target_namespace}/{target_name}")

        service_id = target_name
        service_name = target_name

        if not target_address:
            logger.warning(f"Target {target_namespace}/{target_name} has no 'spec.address'. Skipping.")
            return

        if event_type == 'ADDED' or event_type == 'MODIFIED':
            if self._is_target_ready(target_obj):
                self._register_consul_service(service_id, service_name, target_address, CONSUL_SERVICE_PORT, tags)
            else:
                logger.info(f"Target {target_namespace}/{target_name} is not 'Ready'. Deregistering if exists or skipping registration.")
                self._deregister_consul_service(service_id)
        elif event_type == 'DELETED':
            self._deregister_consul_service(service_id)
        else:
            logger.warning(f"Unknown event type: {event_type} for Target {target_namespace}/{target_name}")

    def _process_additional_target_event(self, event_type, additional_target_obj):
        """Processes events for AdditionalTarget CRDs."""
        at_name = additional_target_obj['metadata']['name']
        at_namespace = additional_target_obj['metadata']['namespace']
        at_address = additional_target_obj['spec'].get('address')
        at_port = additional_target_obj['spec'].get('port', CONSUL_SERVICE_PORT) # Use spec.port if available, else default
        at_spec_tags = additional_target_obj['spec'].get('tags', [])

        # Combine spec.tags with other generated tags
        tags = [ADDITIONAL_TARGET_TAG]
        for tag in at_spec_tags:
            tags.append(tag)
        if additional_target_obj['metadata'].get('labels'):
            for label_key, label_value in additional_target_obj['metadata']['labels'].items():
                tags.append(f"label:{label_key}={label_value}")

        logger.debug(f"Processing event: {event_type} for AdditionalTarget {at_namespace}/{at_name}")

        # Use spec.Id or spec.Name for Consul service name/ID if available, otherwise metadata.name
        consul_id_base = additional_target_obj['spec'].get('id', at_name)

        service_id = consul_id_base
        service_name = consul_id_base # Using spec.name or metadata.name as Consul service name

        if not at_address:
            logger.warning(f"AdditionalTarget {at_namespace}/{at_name} has no 'spec.address'. Skipping.")
            return

        if event_type == 'ADDED' or event_type == 'MODIFIED':
            # AdditionalTarget is considered "ready" if it has an address
            self._register_consul_service(service_id, service_name, at_address, at_port, tags)
        elif event_type == 'DELETED':
            self._deregister_consul_service(service_id)
        else:
            logger.warning(f"Unknown event type: {event_type} for AdditionalTarget {at_namespace}/{at_name}")

    def _watch_crd(self, crd_group, crd_version, crd_plural, processor_func):
        """Watches for events of a specific CRD type and calls the appropriate processor."""
        logger.info(f"Starting watch for CRD: {crd_group}/{crd_version}/{crd_plural}")
        while True:
            try:
                for event in self.k8s_watch.stream(
                    self.k8s_api.list_cluster_custom_object,
                    group=crd_group,
                    version=crd_version,
                    plural=crd_plural,
                    _preload_content=False
                ):
                    event_type = event['type']
                    obj = event['object']
                    processor_func(event_type, obj)
            except client.ApiException as e:
                logger.error(f"Kubernetes API error for {crd_plural} CRD: {e}. Retrying in 5 seconds.")
                time.sleep(5)
            except Exception as e:
                logger.error(f"An unexpected error occurred for {crd_plural} CRD: {e}. Retrying in 5 seconds.")
                time.sleep(5)

    def run(self):
        """Starts watching for Target and AdditionalTarget CRD events concurrently."""
        target_thread = threading.Thread(target=self._watch_crd, args=(TARGET_CRD_GROUP, TARGET_CRD_VERSION, TARGET_CRD_PLURAL, self._process_target_event))
        additional_target_thread = threading.Thread(target=self._watch_crd, args=(ADDITIONAL_TARGET_CRD_GROUP, ADDITIONAL_TARGET_CRD_VERSION, ADDITIONAL_TARGET_CRD_PLURAL, self._process_additional_target_event))

        target_thread.start()
        additional_target_thread.start()

        target_thread.join()
        additional_target_thread.join()

if __name__ == "__main__":
    controller = TargetConsulSyncController()
    controller.run()