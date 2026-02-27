import os
import logging
import time
import threading
from datetime import datetime, timezone
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException
import consul
from flask import Flask, jsonify
import ping3 # For soft ping

# --- Configuration ---
# Kubernetes CRD details for Target (inv.sdcio.dev) - Renamed from original for clarity 
SDCIO_TARGET_CRD_GROUP = "inv.sdcio.dev"
SDCIO_TARGET_CRD_VERSION = "v1alpha1"
SDCIO_TARGET_CRD_PLURAL = "targets" # Original controller's target

# Kubernetes CRD details for AdditionalTarget (nok.dev) - Original controller's additional target
ADDITIONAL_TARGET_CRD_GROUP = "nok.dev"
ADDITIONAL_TARGET_CRD_VERSION = "v1alpha1"
ADDITIONAL_TARGET_CRD_PLURAL = "additionaltargets"

# Kubernetes CRD details for NetworkDeviceTarget (nok.dev) - NEW
NETWORK_DEVICE_TARGET_CRD_GROUP = "nok.dev"
NETWORK_DEVICE_TARGET_CRD_VERSION = "v1alpha1"
NETWORK_DEVICE_TARGET_CRD_PLURAL = "networkdevicetargets"

# Kubernetes CRD details for operator.gnmic.dev/v1alpha1 Target - NEW
GNMIC_TARGET_CRD_GROUP = "operator.gnmic.dev"
GNMIC_TARGET_CRD_VERSION = "v1alpha1"
GNMIC_TARGET_CRD_PLURAL = "targets"

# Kubernetes CRD details for inv.sdcio.dev/v1alpha1 DiscoveryRule - NEW
SDCIO_DISCOVERY_RULE_CRD_GROUP = "inv.sdcio.dev"
SDCIO_DISCOVERY_RULE_CRD_VERSION = "v1alpha1"
SDCIO_DISCOVERY_RULE_CRD_PLURAL = "discoveryrules"
# Name of the DiscoveryRule to manage (can be configured or derived)
DEFAULT_DISCOVERY_RULE_NAME = "dr-static"
DEFAULT_DISCOVERY_RULE_PERIOD = "1m" # Default period for DiscoveryRule

# Consul configuration
CONSUL_HTTP_ADDR = os.getenv("CONSUL_HTTP_ADDR", "http://consul-svc-nok-base.nok-base.svc.cluster.local:8500")
CONSUL_HTTP_TOKEN = os.getenv("CONSUL_HTTP_TOKEN")
CONSUL_SERVICE_PORT = int(os.getenv("CONSUL_SERVICE_PORT", "57400"))
ADDITIONAL_TARGET_TAG = 'additional-target'
TARGET_TAG = 'network-element'

# HTTP Server Configuration
HTTP_SERVER_PORT = int(os.getenv("HTTP_SERVER_PORT", "8080"))
HTTP_SERVER_HOST = os.getenv("HTTP_SERVER_HOST", "0.0.0.0")

# Reachability Check Configuration
REACHABILITY_CHECK_PERIOD_SECONDS = int(os.getenv("REACHABILITY_CHECK_PERIOD_SECONDS", "60")) # 1 minute

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
        self.k8s_core_api = client.CoreV1Api() # For secret checks if needed
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

        # Initialize Flask app
        self.app = Flask(__name__)
        self.app.add_url_rule('/targets', 'get_targets', self._get_targets_json)

        # Data structure to hold registered Target hostnames for the HTTP service
        self.registered_target_hostnames = set()
        self.target_hostnames_lock = threading.Lock()

        # Data structure to hold NetworkDeviceTarget info for reachability checks
        # { "namespace/name": { "address": "ip", "last_status": "Reachable/Unreachable/Unknown" } }
        self.network_device_targets_for_reachability = {}
        self.network_device_targets_lock = threading.Lock()

    def _get_targets_json(self):
        """HTTP endpoint to return registered Target hostnames."""
        with self.target_hostnames_lock:
            # Convert set to a dictionary with empty strings as values
            targets_dict = {hostname: "" for hostname in self.registered_target_hostnames}
        return jsonify(targets_dict)

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

    def _deregister_consul_service(self, service_id: str):
        """Deregisters a service from Consul."""
        try:
            self.consul_client.agent.service.deregister(service_id)
            logger.info(f"Deregistered Consul service ID '{service_id}'")
        except Exception as e:
            logger.error(f"Failed to deregister Consul service ID '{service_id}': {e}")

    def _process_sdcio_target_event(self, event_type, target_obj: dict):
        """Processes events for SDCIO Target CRDs (original controller logic)."""
        target_name = target_obj['metadata']['name']
        target_namespace = target_obj['metadata']['namespace']
        target_address = target_obj['spec'].get('address')

        tags = [TARGET_TAG]  # Ensure tags is a list
        if target_obj['metadata'].get('labels'):
            region = target_obj['metadata']['labels'].get('sdcio.dev/region')
            if region:
                tags.append(f"region:{region}")
            # Add a tag to identify the resource type
            tags.append("k8s-crd-type:sdcio-target")
            # Example: provider = target_obj['metadata']['labels'].get('inv.sdcio.dev/provider')
            # if provider: tags.append(f"provider:{provider}")

        logger.debug(f"Processing event: {event_type} for SDCIO Target {target_namespace}/{target_name}")

        service_id = target_name
        service_name = target_name
        consul_hostname = f"{target_name}.service.consul"  # Format for the HTTP service

        if not target_address:
            logger.warning(f"SDCIO Target {target_namespace}/{target_name} has no 'spec.address'. Skipping.")
            # If address is missing, ensure it's not in the HTTP service list
            with self.target_hostnames_lock:
                if consul_hostname in self.registered_target_hostnames:
                    self.registered_target_hostnames.remove(consul_hostname)
                    logger.info(f"Removed '{consul_hostname}' from HTTP service list due to missing address.")
            return

        if event_type == 'ADDED' or event_type == 'MODIFIED':
            if self._is_target_ready(target_obj):
                self._register_consul_service(service_id, service_name, target_address, CONSUL_SERVICE_PORT, tags)
                with self.target_hostnames_lock:
                    self.registered_target_hostnames.add(consul_hostname)
                    logger.info(f"Added '{consul_hostname}' to HTTP service list.")
            else:
                logger.info(f"SDCIO Target {target_namespace}/{target_name} is not 'Ready'. Deregistering if exists or skipping registration.")
                self._deregister_consul_service(service_id)
                with self.target_hostnames_lock:
                    if consul_hostname in self.registered_target_hostnames:
                        self.registered_target_hostnames.remove(consul_hostname)
                        logger.info(f"Removed '{consul_hostname}' from HTTP service list as target is not ready.")
        elif event_type == 'DELETED':
            self._deregister_consul_service(service_id)
            with self.target_hostnames_lock:
                if consul_hostname in self.registered_target_hostnames:
                    self.registered_target_hostnames.remove(consul_hostname)
                    logger.info(f"Removed '{consul_hostname}' from HTTP service list due to deletion.")
        else:
            logger.warning(f"Unknown event type: {event_type} for SDCIO Target {target_namespace}/{target_name}")

    def _process_additional_target_event(self, event_type, additional_target_obj: dict):
        """Processes events for AdditionalTarget CRDs (original controller logic)."""
        at_name = additional_target_obj['metadata']['name']
        at_namespace = additional_target_obj['metadata']['namespace']
        at_address = additional_target_obj['spec'].get('address')
        at_port = additional_target_obj['spec'].get('port', CONSUL_SERVICE_PORT)  # Use spec.port if available, else default
        at_spec_tags = additional_target_obj['spec'].get('tags', [])

        # Combine spec.tags with other generated tags
        tags = [ADDITIONAL_TARGET_TAG]  # Ensure tags is a list
        for tag in at_spec_tags:
            tags.append(tag)
        if additional_target_obj['metadata'].get('labels'):
            for label_key, label_value in additional_target_obj['metadata']['labels'].items():
                tags.append(f"label:{label_key}={label_value}")
        tags.append("k8s-crd-type:additional-target")

        logger.debug(f"Processing event: {event_type} for AdditionalTarget {at_namespace}/{at_name}")

        # Use spec.Id or spec.Name for Consul service name/ID if available, otherwise metadata.name
        consul_id_base = additional_target_obj['spec'].get('id', at_name)

        service_id = consul_id_base
        service_name = consul_id_base  # Using spec.name or metadata.name as Consul service name

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

    def _ensure_gnmic_target(self, ndt_obj: dict, create: bool):
        """
        Creates, updates, or deletes an operator.gnmic.dev/v1alpha1 Target resource
        based on the NetworkDeviceTarget.
        """
        ndt_name = ndt_obj['metadata']['name']
        ndt_namespace = ndt_obj['metadata']['namespace']
        gnmic_spec = ndt_obj['spec'].get('gnmic', {})
        common_labels = ndt_obj['spec'].get('commonLabels', {})

        target_name = ndt_name # gNMIc Target name matches NDT name
        target_namespace = ndt_namespace

        if not gnmic_spec.get('enabled', True) or not create:
            # Delete the gNMIc Target if disabled or NDT is being deleted
            try:
                self.k8s_api.delete_namespaced_custom_object(
                    group=GNMIC_TARGET_CRD_GROUP,
                    version=GNMIC_TARGET_CRD_VERSION,
                    name=target_name,
                    namespace=target_namespace,
                    plural=GNMIC_TARGET_CRD_PLURAL,
                    body=client.V1DeleteOptions()
                )
                logger.info(f"Deleted gNMIc Target {target_namespace}/{target_name} for NetworkDeviceTarget {ndt_namespace}/{ndt_name}.")
            except ApiException as e:
                if e.status == 404:
                    logger.debug(f"gNMIc Target {target_namespace}/{target_name} not found, no need to delete.")
                else:
                    logger.error(f"Error deleting gNMIc Target {target_namespace}/{target_name}: {e}")
            return

        # Construct gNMIc Target spec
        gnmic_target_address = f"{ndt_obj['spec']['address']}:{gnmic_spec.get('port', '57400')}" # Default gNMI port
        gnmic_target_profile = gnmic_spec.get('targetProfileRef', 'default') # Default profile

        # Combine labels
        gnmic_labels = common_labels.copy()
        gnmic_labels.update(gnmic_spec.get('labels', {}))
        gnmic_labels['networkdevicetarget.nok.dev/name'] = ndt_name # Link back to NDT

        gnmic_target_body = {
            "apiVersion": f"{GNMIC_TARGET_CRD_GROUP}/{GNMIC_TARGET_CRD_VERSION}",
            "kind": "Target",
            "metadata": {
                "name": target_name,
                "namespace": target_namespace,
                "labels": gnmic_labels
            },
            "spec": {
                "address": gnmic_target_address,
                "profile": gnmic_target_profile,
                "credentialsSecretRef": gnmic_spec.get('credentialsSecretRef')
            }
        }

        try:
            # Try to get the existing gNMIc Target
            existing_target = self.k8s_api.get_namespaced_custom_object(
                group=GNMIC_TARGET_CRD_GROUP,
                version=GNMIC_TARGET_CRD_VERSION,
                name=target_name,
                namespace=target_namespace,
                plural=GNMIC_TARGET_CRD_PLURAL
            )
            # Update existing
            self.k8s_api.patch_namespaced_custom_object(
                group=GNMIC_TARGET_CRD_GROUP,
                version=GNMIC_TARGET_CRD_VERSION,
                name=target_name,
                namespace=target_namespace,
                plural=GNMIC_TARGET_CRD_PLURAL,
                body=gnmic_target_body
            )
            logger.info(f"Updated gNMIc Target {target_namespace}/{target_name} for NetworkDeviceTarget {ndt_namespace}/{ndt_name}.")
        except ApiException as e:
            if e.status == 404:
                # Create new if not found
                self.k8s_api.create_namespaced_custom_object(
                    group=GNMIC_TARGET_CRD_GROUP,
                    version=GNMIC_TARGET_CRD_VERSION,
                    namespace=target_namespace,
                    plural=GNMIC_TARGET_CRD_PLURAL,
                    body=gnmic_target_body
                )
                logger.info(f"Created gNMIc Target {target_namespace}/{target_name} for NetworkDeviceTarget {ndt_namespace}/{ndt_name}.")
            else:
                logger.error(f"Error ensuring gNMIc Target {target_namespace}/{target_name}: {e}")

    def _ensure_sdcio_discovery_rule(self, ndt_obj: dict, create: bool):
        """
        Ensures the inv.sdcio.dev/v1alpha1 DiscoveryRule exists and contains the
        NetworkDeviceTarget's information.
        """
        ndt_name = ndt_obj['metadata']['name']
        ndt_namespace = ndt_obj['metadata']['namespace']
        sdcio_spec = ndt_obj['spec'].get('sdcio', {})
        common_labels = ndt_obj['spec'].get('commonLabels', {})

        discovery_rule_name = DEFAULT_DISCOVERY_RULE_NAME # Use a fixed name for now
        discovery_rule_namespace = ndt_namespace # DiscoveryRule in the same namespace as NDT

        # Define the target entry for the DiscoveryRule
        target_entry = {
            "address": ndt_obj['spec']['address'],
            "hostName": ndt_obj['spec']['hostname'],
            "labels": common_labels.copy() # Labels for this specific address entry
        }
        target_entry['labels'].update(sdcio_spec.get('labels', {}))
        target_entry['labels']['networkdevicetarget.nok.dev/name'] = ndt_name # Link back to NDT

        if not sdcio_spec.get('enabled', True) or not create:
            # Remove the target from the DiscoveryRule if disabled or NDT is being deleted
            try:
                existing_dr = self.k8s_api.get_namespaced_custom_object(
                    group=SDCIO_DISCOVERY_RULE_CRD_GROUP,
                    version=SDCIO_DISCOVERY_RULE_CRD_VERSION,
                    name=discovery_rule_name,
                    namespace=discovery_rule_namespace,
                    plural=SDCIO_DISCOVERY_RULE_CRD_PLURAL
                )
                addresses = existing_dr['spec'].get('addresses', [])
                updated_addresses = [
                    addr for addr in addresses
                    if not (addr.get('address') == ndt_obj['spec']['address'] and
                            addr.get('hostName') == ndt_obj['spec']['hostname'])
                ]
                if len(addresses) != len(updated_addresses):
                    existing_dr['spec']['addresses'] = updated_addresses
                    self.k8s_api.patch_namespaced_custom_object(
                        group=SDCIO_DISCOVERY_RULE_CRD_GROUP,
                        version=SDCIO_DISCOVERY_RULE_CRD_VERSION,
                        name=discovery_rule_name,
                        namespace=discovery_rule_namespace,
                        plural=SDCIO_DISCOVERY_RULE_CRD_PLURAL,
                        body=existing_dr
                    )
                    logger.info(f"Removed NetworkDeviceTarget {ndt_namespace}/{ndt_name} from DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name}.")
                else:
                    logger.debug(f"NetworkDeviceTarget {ndt_namespace}/{ndt_name} not found in DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name}, no action needed.")
            except ApiException as e:
                if e.status == 404:
                    logger.debug(f"DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name} not found, no need to update.")
                else:
                    logger.error(f"Error removing NetworkDeviceTarget {ndt_namespace}/{ndt_name} from DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name}: {e}")
            return

        # Construct SDCIO DiscoveryRule body
        sdcio_dr_body = {
            "apiVersion": f"{SDCIO_DISCOVERY_RULE_CRD_GROUP}/{SDCIO_DISCOVERY_RULE_CRD_VERSION}",
            "kind": "DiscoveryRule",
            "metadata": {
                "name": discovery_rule_name,
                "namespace": discovery_rule_namespace,
                "labels": {
                    "managed-by": "nokiagpt-controller",
                    "networkdevicetarget.nok.dev/managed": "true"
                }
            },
            "spec": {
                "period": DEFAULT_DISCOVERY_RULE_PERIOD,
                "concurrentScans": 1, # Example value
                "defaultSchema": sdcio_spec.get('schema', {}),
                "targetConnectionProfiles": [
                    {
                        "credentials": sdcio_spec.get('credentialsSecretRef'),
                        "connectionProfile": sdcio_spec.get('connectionProfileRef'),
                        "syncProfile": sdcio_spec.get('syncProfileRef')
                    }
                ],
                "targetTemplate": {
                    "labels": common_labels.copy() # Labels for all targets created by this rule
                },
                "addresses": [] # This will be populated dynamically
            }
        }
        sdcio_dr_body['spec']['targetTemplate']['labels'].update(sdcio_spec.get('labels', {}))

        try:
            existing_dr = self.k8s_api.get_namespaced_custom_object(
                group=SDCIO_DISCOVERY_RULE_CRD_GROUP,
                version=SDCIO_DISCOVERY_RULE_CRD_VERSION,
                name=discovery_rule_name,
                namespace=discovery_rule_namespace,
                plural=SDCIO_DISCOVERY_RULE_CRD_PLURAL
            )
            # Update existing DiscoveryRule
            addresses = existing_dr['spec'].get('addresses', [])
            # Check if target_entry already exists to avoid duplicates
            found = False
            for i, addr in enumerate(addresses):
                if addr.get('address') == target_entry['address'] and addr.get('hostName') == target_entry['hostName']:
                    addresses[i] = target_entry # Update existing entry
                    found = True
                    break
            if not found:
                addresses.append(target_entry)
            existing_dr['spec']['addresses'] = addresses

            # Patch other fields if necessary, or replace the whole spec
            # For simplicity, we'll just update addresses and ensure defaultSchema/profiles are present
            existing_dr['spec']['defaultSchema'] = sdcio_dr_body['spec']['defaultSchema']
            existing_dr['spec']['targetConnectionProfiles'] = sdcio_dr_body['spec']['targetConnectionProfiles']
            existing_dr['spec']['targetTemplate'] = sdcio_dr_body['spec']['targetTemplate']
            existing_dr['spec']['period'] = sdcio_dr_body['spec']['period']
            existing_dr['spec']['concurrentScans'] = sdcio_dr_body['spec']['concurrentScans']

            self.k8s_api.patch_namespaced_custom_object(
                group=SDCIO_DISCOVERY_RULE_CRD_GROUP,
                version=SDCIO_DISCOVERY_RULE_CRD_VERSION,
                name=discovery_rule_name,
                namespace=discovery_rule_namespace,
                plural=SDCIO_DISCOVERY_RULE_CRD_PLURAL,
                body=existing_dr
            )
            logger.info(f"Updated DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name} with NetworkDeviceTarget {ndt_namespace}/{ndt_name}.")
        except ApiException as e:
            if e.status == 404:
                # Create new DiscoveryRule
                sdcio_dr_body['spec']['addresses'] = [target_entry]
                self.k8s_api.create_namespaced_custom_object(
                    group=SDCIO_DISCOVERY_RULE_CRD_GROUP,
                    version=SDCIO_DISCOVERY_RULE_CRD_VERSION,
                    namespace=discovery_rule_namespace,
                    plural=SDCIO_DISCOVERY_RULE_CRD_PLURAL,
                    body=sdcio_dr_body
                )
                logger.info(f"Created DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name} for NetworkDeviceTarget {ndt_namespace}/{ndt_name}.")
            else:
                logger.error(f"Error ensuring DiscoveryRule {discovery_rule_namespace}/{discovery_rule_name}: {e}")

    def _check_reachability(self, address: str) -> str:
        """Performs a soft ping to the given address and returns 'Reachable' or 'Unreachable'."""
        try:
            # ping3.ping returns latency in seconds, or False if unreachable
            delay = ping3.ping(address, timeout=1, unit='ms')
            if delay is not False:
                logger.debug(f"Ping to {address} successful, latency: {delay:.2f} ms")
                return "Reachable"
            else:
                logger.debug(f"Ping to {address} failed.")
                return "Unreachable"
        except Exception as e:
            logger.error(f"Error during reachability check for {address}: {e}")
            return "Unknown"

    def _update_network_device_target_status(self, ndt_namespace: str, ndt_name: str, status: str):
        """Updates the status subresource of a NetworkDeviceTarget CRD."""
        now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        status_body = {
            "status": {
                "reachability": status,
                "lastProbeTime": now
            }
        }
        try:
            self.k8s_api.patch_namespaced_custom_object_status(
                group=NETWORK_DEVICE_TARGET_CRD_GROUP,
                version=NETWORK_DEVICE_TARGET_CRD_VERSION,
                name=ndt_name,
                namespace=ndt_namespace,
                plural=NETWORK_DEVICE_TARGET_CRD_PLURAL,
                body=status_body
            )
            logger.info(f"Updated NetworkDeviceTarget {ndt_namespace}/{ndt_name} status to: {status}")
        except ApiException as e:
            logger.error(f"Error updating status for NetworkDeviceTarget {ndt_namespace}/{ndt_name}: {e}")
        except Exception as e:
            logger.error(f"Unexpected error updating status for NetworkDeviceTarget {ndt_namespace}/{ndt_name}: {e}")

    def _process_network_device_target_event(self, event_type, ndt_obj: dict):
        """Processes events for NetworkDeviceTarget CRDs."""
        ndt_name = ndt_obj['metadata']['name']
        ndt_namespace = ndt_obj['metadata']['namespace']
        ndt_address = ndt_obj['spec'].get('address')
        ndt_key = f"{ndt_namespace}/{ndt_name}"

        logger.info(f"Processing event: {event_type} for NetworkDeviceTarget {ndt_key}")

        if not ndt_address:
            logger.warning(f"NetworkDeviceTarget {ndt_key} has no 'spec.address'. Skipping processing.")
            with self.network_device_targets_lock:
                self.network_device_targets_for_reachability.pop(ndt_key, None)
            return

        with self.network_device_targets_lock:
            self.network_device_targets_for_reachability[ndt_key] = {
                "address": ndt_address,
                "last_status": ndt_obj.get('status', {}).get('reachability', 'Unknown')
            }

        if event_type == 'ADDED' or event_type == 'MODIFIED':
            # Ensure gNMIc Target
            self._ensure_gnmic_target(ndt_obj, create=True)
            # Ensure SDCIO DiscoveryRule entry
            self._ensure_sdcio_discovery_rule(ndt_obj, create=True)
            # Perform initial reachability check and update status
            current_reachability = self._check_reachability(ndt_address)
            self._update_network_device_target_status(ndt_namespace, ndt_name, current_reachability)
            with self.network_device_targets_lock:
                if ndt_key in self.network_device_targets_for_reachability:
                    self.network_device_targets_for_reachability[ndt_key]["last_status"] = current_reachability

        elif event_type == 'DELETED':
            # Delete gNMIc Target
            self._ensure_gnmic_target(ndt_obj, create=False)
            # Remove from SDCIO DiscoveryRule
            self._ensure_sdcio_discovery_rule(ndt_obj, create=False)
            # Remove from reachability tracking
            with self.network_device_targets_lock:
                self.network_device_targets_for_reachability.pop(ndt_key, None)
            logger.info(f"Removed NetworkDeviceTarget {ndt_key} from tracking.")
        else:
            logger.warning(f"Unknown event type: {event_type} for NetworkDeviceTarget {ndt_key}")

    def _reachability_loop(self):
        """Periodically checks reachability for all tracked NetworkDeviceTargets."""
        logger.info(f"Starting reachability check loop with period: {REACHABILITY_CHECK_PERIOD_SECONDS} seconds.")
        while True:
            time.sleep(REACHABILITY_CHECK_PERIOD_SECONDS)
            logger.debug("Performing periodic reachability checks...")
            targets_to_check = {}
            with self.network_device_targets_lock:
                targets_to_check = self.network_device_targets_for_reachability.copy()

            for ndt_key, info in targets_to_check.items():
                ndt_namespace, ndt_name = ndt_key.split('/', 1)
                address = info['address']
                current_status = self._check_reachability(address)

                # Only update if status has changed or if it 