# Terraforming steps from https://cloud.google.com/solutions/continuous-delivery-spinnaker-kubernetes-engine

provider "google" {
  version = "~> 1.16"
  project = "${var.project}"
  zone    = "${var.zone}"

  #credentials = "${file(var.credential)}"
}

data "google_service_account" "terraform" {
  account_id = "${var.service_account}"
}

# Need to enable serviceusage API manully on the console first
# https://console.developers.google.com/apis/library/serviceusage.googleapis.com
resource "google_project_services" "myproject" {
  disable_on_destroy = false

  services = [
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "container.googleapis.com",
    "oslogin.googleapis.com",
    "containerregistry.googleapis.com",
    "compute.googleapis.com",
    "deploymentmanager.googleapis.com",
    "replicapool.googleapis.com",
    "replicapoolupdater.googleapis.com",
    "resourceviews.googleapis.com",
    "cloudbuild.googleapis.com",
    "sourcerepo.googleapis.com",
    "bigquery-json.googleapis.com",
  ]
}

# Create GKE cluster
module "gke_cluster" {
  source             = "modules/cluster"
  name               = "${var.cluster_name}"
  initial_node_count = "${var.cluster_nodes_count}"
  machine_type       = "${var.node_type}"
  zone               = "${var.zone}"
  tags               = ["spinnaker"]

  ## Project id is added as tag to create dependency between project services (above commands) and cluster creation
  project = "${google_project_services.myproject.id}"
}

# k8s provider is used for installing helm
provider "kubernetes" {
  load_config_file       = false
  version                = "~> 1.1"
  host                   = "${module.gke_cluster.host}"
  username               = "${module.gke_cluster.username}"
  password               = "${module.gke_cluster.password}"
  client_certificate     = "${module.gke_cluster.client_certificate}"
  client_key             = "${module.gke_cluster.client_key}"
  cluster_ca_certificate = "${module.gke_cluster.cluster_ca_certificate}"
}

module "spinnaker" {
  source            = "modules/spinnaker"
  gcs_location      = "${var.gcs_location}"
  project           = "${var.project}"
  spinnaker_version = "${var.spinnaker_version}"
  cluster_name      = "${module.gke_cluster.id}"

  depends_on = [
    "${module.gke_cluster.gcloud_config_id}",
  ]
}
