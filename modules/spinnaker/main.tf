# Create spinnaker namespace
resource "kubernetes_namespace" "spinnaker" {
  "metadata" {
    name = "${var.spinnaker_k8s_namespace}"

    annotations {
      # To ensure namespace is created only after previous module completes
      depends-id = "${join(",", var.depends_on)}"
    }
  }
}

# Create kubernetes service account for spinnaker
resource "kubernetes_service_account" "spinnaker" {
  depends_on = [
    "kubernetes_namespace.spinnaker",
  ]

  "metadata" {
    name      = "${var.spinnaker_k8s_sa}"
    namespace = "${kubernetes_namespace.spinnaker.metadata.0.name}"
  }
}

data "template_file" "grant_admin_to_spinnaker" {
  template = <<EOF
set -ex \
&& kubectl create clusterrolebinding spinnaker-admin \
      --clusterrole=cluster-admin \
      --serviceaccount=$${namespace}:$${account}
EOF

  vars {
    namespace = "${kubernetes_service_account.spinnaker.metadata.0.namespace}"
    account   = "${kubernetes_service_account.spinnaker.metadata.0.name}"
  }
}

# Grant ClusterRoleBinding to spinnaker service account
resource "null_resource" "grant_admin_to_spinnaker" {
  depends_on = [
    "kubernetes_service_account.spinnaker",
  ]

  provisioner "local-exec" {
    command = "${data.template_file.grant_admin_to_spinnaker.rendered}"
  }
}

data "template_file" "kubectl_config" {
  depends_on = [
    "null_resource.grant_admin_to_spinnaker",
  ]

  template = <<EOF
set -ex \
&& CONTEXT=$(kubectl config current-context) \
&& SECRET_NAME=$(kubectl get serviceaccount $${account} --namespace $${namespace} -o jsonpath='{.secrets[0].name}') \
&& TOKEN=$(kubectl get secret --namespace $${namespace} $SECRET_NAME -o yaml  -o jsonpath='{.data.token}' | base64 --decode) \
&& kubectl config set-credentials $CONTEXT-token-user --token $TOKEN \
&& kubectl config set-context $CONTEXT --user $CONTEXT-token-user
EOF

  vars {
    namespace = "${kubernetes_service_account.spinnaker.metadata.0.namespace}"
    account   = "${kubernetes_service_account.spinnaker.metadata.0.name}"
  }
}

# Configure kubectl to use spinnaker service account
resource "null_resource" "kubectl_config" {
  depends_on = [
    "null_resource.grant_admin_to_spinnaker",
  ]

  provisioner "local-exec" {
    command = "${data.template_file.kubectl_config.rendered}"
  }
}

#
# Create GCS bucket
resource "google_storage_bucket" "spinnaker_config" {
  # Wait for kubectl to be configured
  depends_on = [
    "null_resource.kubectl_config",
  ]

  name          = "${var.project}-spinnaker-config"
  location      = "${var.gcs_location}"
  storage_class = "NEARLINE"
  force_destroy = "true"
}

# Create service account for spinner storage
resource "google_service_account" "spinnaker_gcs" {
  depends_on = [
    "google_storage_bucket.spinnaker_config",
  ]

  account_id   = "${var.spinnaker_gcs_sa}"
  display_name = "${var.spinnaker_gcs_sa}"
}

#
# Bind the storage.admin role to your service account:
resource "google_project_iam_binding" "spinnaker_gcs" {
  role = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.spinnaker_gcs.email}",
  ]
}

resource "google_service_account_key" "spinnaker_gcs" {
  service_account_id = "${google_service_account.spinnaker_gcs.name}"
}

data "template_file" "deploy_spinnaker" {
  depends_on = [
    "google_service_account_key.spinnaker_gcs",
  ]

  template = <<EOF
set -ex \
&& GCS_KEY_FILE=~/.hal/.$${bucket}.key \
&& echo '$${gcs_json_key}' | base64 --decode > $GCS_KEY_FILE \
&& hal -q config provider kubernetes enable \
&& hal -q config provider kubernetes account delete my-k8s-v2-account || true \
&& hal -q config provider kubernetes account add my-k8s-v2-account --provider-version v2 --context $(kubectl config current-context) \
&& hal -q config features edit --artifacts true \
&& hal -q config deploy edit --type distributed --account-name my-k8s-v2-account \
&& hal -q config storage gcs edit --project $${project} --bucket-location $${gcs_location} --json-path $GCS_KEY_FILE --bucket $${bucket} \
&& hal -q config storage edit --type gcs \
&& hal -q config version edit --version $${spinnaker_version} \
&& hal -q deploy apply
EOF

  vars {
    project           = "${var.project}"
    gcs_location      = "${var.gcs_location}"
    bucket            = "${google_storage_bucket.spinnaker_config.name}"
    gcs_json_key      = "${google_service_account_key.spinnaker_gcs.private_key}"
    spinnaker_version = "${var.spinnaker_version}"
  }
}

# Configure kubectl to use spinnaker service account
resource "null_resource" "deploy_spinnaker" {
  depends_on = [
    "google_service_account_key.spinnaker_gcs",
  ]

  provisioner "local-exec" {
    command = "${data.template_file.deploy_spinnaker.rendered}"
  }
}

#
#data "template_file" "spinnaker_config" {
#  template = <<EOF
#cat <<EOI > ${var.temp_dir}/.spinnaker-values.yaml
#storageBucket: $${bucket}
#gcs:
#  enabled: true
#  project: $${project}
#  jsonKey: '$${sa_json}'
#
## Disable minio as the default
#minio:
#  enabled: false
#
## Configure your Docker registries here
#accounts:
#- name: gcr
#  address: https://gcr.io
#  username: _json_key
#  email: $${sa_email}
#  password: '$${sa_json}'
#EOI
#EOF
#
#  vars {
#    bucket     = "${google_storage_bucket.spinnaker_config.name}"
#    project    = "${var.project}"
#    sa_json    = "${base64decode(google_service_account_key.spinnaker_gcs.private_key)}"
#    sa_email   = "${google_service_account.spinnaker_gcs.email}"
#    depends_on = "${join(",", var.depends_on)}"
#  }
#}
#
#resource "null_resource" "spinnaker_config" {
#  provisioner "local-exec" {
#    command = "${data.template_file.spinnaker_config.rendered}"
#  }
#}
#
#data "template_file" "install_spinnaker" {
#  template = <<EOF
#set -ex \
#&& kubectl --kubeconfig=$${kubeconfig_file} config set-context default --cluster=mycluster --namespace=$${namespace} --user=admin \
#&& kubectl --kubeconfig=$${kubeconfig_file} config use-context default \
#&& kubectl --kubeconfig=$${kubeconfig_file} delete --ignore-not-found=true clusterrolebinding $${crb_name} \
#&& kubectl --kubeconfig=$${kubeconfig_file} create clusterrolebinding $${crb_name} --clusterrole=cluster-admin --serviceaccount=$${namespace}:$${service_account} \
#&& export KUBECONFIG=$${kubeconfig_file} \
#&& helm --debug install --kube-context default --namespace $${namespace} --wait --timeout 600 --version 0.5.0 -f $${values_yaml} --name spinnaker stable/spinnaker
#EOF
#
#  vars {
#    kubeconfig_file = "${var.kubeconfig_file}"
#    namespace       = "${var.namespace}"
#    service_account = "${var.service_account}"
#    crb_name        = "${var.service_account}-admin-binding"
#    values_yaml     = "${var.temp_dir}/.spinnaker-values.yaml"
#    host            = "${var.host}"
#
#    # Wait for values.yaml to be available
#    depends_on = "${null_resource.spinnaker_config.id}"
#  }
#
#  depends_on = [
#    "null_resource.spinnaker_config",
#  ]
#}
#
#resource "null_resource" "install_spinnaker" {
#  #  triggers { sha256 = "${base64sha256(data.template_file.crb_commands.rendered)}" }
#
#  provisioner "local-exec" {
#    command = "${data.template_file.install_spinnaker.rendered}"
#  }
#}

