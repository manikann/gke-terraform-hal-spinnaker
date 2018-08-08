# Install spinnaker in GKE using terraform and hal

### Prerequisite 

* Runs only on Linux or Mac
* Following tools needs to be installed in local machine and available via `PATH` 
    * [gcloud SDK](https://cloud.google.com/sdk/install)
    * [kubectl](https://cloud.google.com/kubernetes-engine/docs/quickstart) (`gcloud components install kubectl`)
    * [terraform](https://www.terraform.io/intro/getting-started/install.html)
    * [halyard](https://www.spinnaker.io/setup/install/halyard/)
    
### Variables
* `project`: The ID of the GCP project
* `zone`: [Compute engine zone](https://cloud.google.com/compute/docs/regions-zones/) where GKE cluster needs to be created 
* `gcs_location`: Cloud storage [bucket location](https://cloud.google.com/storage/docs/bucket-locations) for storing spinnaker data
    > By default [Nearline](https://cloud.google.com/storage/docs/storage-classes#nearline) storage class is configured. 
    Ensure correct location is configured based on the configured `zone` 


## Installation steps

1.  Following API needs to be enabled for the project
    ```
    gcloud services enable serviceusage.googleapis.com
    gcloud services enable iam.googleapis.com
    ```

2.  Create service account for `terraform` 
    ```
    PROJECT=$(gcloud info --format='value(config.project)')
    SA_EMAIL=terraform@${PROJECT}.iam.gserviceaccount.com
    
    gcloud iam service-accounts create terraform --display-name "terraform" 
    gcloud iam service-accounts keys create account.json --iam-account $SA_EMAIL
    ```
    Above command will download the key and store it in `account.json` file
    
3.  Grant owner role to terraform service account    
    ```
    gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:${SA_EMAIL} --role roles/owner
    ```
    
4.  Setup google authentication. For more info refer this [guide](https://cloud.google.com/docs/authentication/production#obtaining_and_providing_service_account_credentials_manually)
    ```
    export GOOGLE_APPLICATION_CREDENTIALS="[PATH]" (for e.g. $PWD/account.json)
    ```

5.  Execute below commands. This will take some time to complete (5 to 8 mins)
    ```
    terraform init
    terraform plan -out terraform.plan
    terraform apply terraform.plan 
    ```
    
6.  After the command completes, run the following command to set up port forwarding to the Spinnaker UI 
    ```
    hal deploy connect
    ```
    
7.  Access spinnaker UI at http://localhost:9000/ 
