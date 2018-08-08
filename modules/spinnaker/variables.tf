variable "cluster_name" {
  default = "Kubernetes cluster name"
}

variable "project" {
  description = "Project id"
}

variable "gcs_location" {
  description = "GCS bucket location"
}

variable "spinnaker_version" {
  default     = "1.8.5"
  description = "Spinnaker version (hal version list)"
}

variable "spinnaker_gcs_sa" {
  default     = "spinnaker-gcs-sa"
  description = "GCP service account for Spinnnaker storage access. Default to 'spinnaker-gcs-sa'"
}

variable "spinnaker_k8s_namespace" {
  default     = "spinnaker"
  description = "Spinnaker namespace. Default to 'spinnaker'"
}

variable "spinnaker_k8s_sa" {
  default     = "spinnaker"
  description = "Kubernetes service account for Spinnnaker. Default to 'spinnaker'"
}

variable "depends_on" {
  default     = []
  type        = "list"
  description = "Hack for expressing module to module dependency"
}
