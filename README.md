# MLFlow Accelerator

This is an accelerator that can be used to generate a Kubernetes deployment for [MLFlow](https://mlflow.org).

* Install App Accelerator: (see https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-cert-mgr-contour-fcd-install-cert-mgr.html)
```
tanzu package available list accelerator.apps.tanzu.vmware.com --namespace tap-install
tanzu package install accelerator -p accelerator.apps.tanzu.vmware.com -v 1.0.1 -n tap-install -f resources/app-accelerator-values.yaml
Verify that package is running: tanzu package installed get accelerator -n tap-install
Get the IP address for the App Accelerator API: kubectl get service -n accelerator-system
```

Publish Accelerators:
```
tanzu plugin install --local <path-to-tanzu-cli> all
tanzu acc create mlflow --git-repository https://github.com/agapebondservant/mlflow-accelerator.git --git-branch main
```

## Contents
1. [Install MLFlow via TAP/tanzu cli](#tanzu)
2. [Install MLFlow with vanilla Kubernetes](#k8s)

### Install MLFlow via TAP/tanzu cli<a name="tanzu"/>

#### Before you begin (one time setup):
1. Create an environment file `.env` (use `.env-sample` as a template), then run:
```
source .env
```

2. Deploy Postgres operator (if it does not already exist - else skip this step):
```
resources/scripts/deploy-postgres-operator.sh
```

3. Deploy Postgres cluster (if it does not already exist - else skip this step):
```
resources/scripts/deploy-postgres-cluster.sh
```

4. Deploy Minio store (if it does not already exist - else skip this step):
```
resources/scripts/deploy-minio.sh
```
NOTE: Requires Minio Client: <a href="https://min.io/docs/minio/linux/reference/minio-mc.html" target="_blank">Link</a>

5. Build and push Docker image:  (one-time op. If it has been built previously, or if it does not need to be rebuilt, then skip this step):
```
source .env
docker build --build-arg MLFLOW_PORT_NUM=${MLFLOW_PORT} \
 --build-arg ARTIFACT_ROOT_PATH=s3://mlflow \
 --build-arg BACKEND_URI_PATH=${MLFLOW_DB_URI} \
 -t ${MLFLOW_CONTAINER_REPO} . # example: oawofolu/mlflow-server
docker push ${MLFLOW_CONTAINER_REPO}
```

#### Deploy MLFlow
6. Create the MLFlow package bundle as a pre-requisite (one-time op. If it has been built previously, or if it does not need to be rebuilt, then skip this step):
```
resources/scripts/create-mlflow-package-bundle.sh
```

#### Deploy MLFlow
Install the MLFlow Package Repository:
```
kubectl create ns ${MLFLOW_NAMESPACE}
tanzu package repository add mlflow-package-repository \
  --url ${MLFLOW_BASE_REPO}/mlflow-packages-repo:${MLFLOW_VERSION} \
  -n ${MLFLOW_NAMESPACE}
```

Verify that the MLFlow package is available for install:
```
tanzu package available list mlflow.tanzu.vmware.com --namespace ${MLFLOW_NAMESPACE}
```

Generate a values.yaml file to use for the install - update as desired:
```
resources/scripts/generate-values-yaml.sh resources/mlflow-values.yaml #replace resources/mlflow-values.yaml with /path/to/your/values/yaml/file
```

Install via **tanzu cli**:
```
tanzu package install mlflow -p mlflow.tanzu.vmware.com -v ${MLFLOW_VERSION} --values-file resources/mlflow-values.yaml --namespace ${MLFLOW_NAMESPACE} 
```

Verify that the install was successful:
```
tanzu package installed get mlflow --namespace ${MLFLOW_NAMESPACE}
```

To uninstall:
```
tanzu package installed delete mlflow --namespace ${MLFLOW_NAMESPACE}  -y
tanzu package repository delete mlflow-package-repository --namespace ${MLFLOW_NAMESPACE} -y
kubectl delete ns ${MLFLOW_NAMESPACE}
```

To uninstall Postgres/Minio dependencies:
```
kubectl delete postgres pg-mlflow-instance -n ${POSTGRES_CLUSTER_NAMESPACE}
helm uninstall minio -n ${MINIO_BUCKET_NAMESPACE}
```

Finally, access the Tracker server via the **ingress_fqdn** indicated in resources/mlflow-values.yaml.

### Install MLFlow via vanilla Kubernetes<a name="k8s"/>
### (NOTE: needs cleanup)

#### Before you begin:
1. Update `resources/mlflow-deployment.yaml` by updating the **container image**, **Minio endpoint** and **Minio bucket region** as indicated in the file.

2.If using Project Contour, uncomment out the `HttpProxy` section of the `resources/mlflow-deployment.yaml` file and update the referenced **FQDN** accordingly.

3. Create an environment file `.env`; use `.env-sample` as a template.

4. Deploy Postgres Operator via helm (if the operator does not exist in the cluster):
```
helm uninstall postgres --namespace default
for i in $(kubectl get clusterrole | grep postgres); do kubectl delete clusterrole ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get clusterrolebinding | grep postgres); do kubectl delete clusterrolebinding ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get certificate -n cert-manager | grep postgres); do kubectl delete certificate -n cert-manager ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get clusterissuer | grep postgres); do kubectl delete clusterissuer ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get mutatingwebhookconfiguration | grep postgres); do kubectl delete mutatingwebhookconfiguration ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get validatingwebhookconfiguration | grep postgres); do kubectl delete validatingwebhookconfiguration ${i} > /dev/null 2>&1; done; 
for i in $(kubectl get crd | grep postgres); do kubectl delete crd ${i} > /dev/null 2>&1; done;
helm install postgres resources/postgres/operator1.6.0 \
-f resources/postgres/overrides.yaml --namespace default --wait
kubectl apply -f resources/postgres/operator1.6.0/crds/
```

5. Deploy Postgres Cluster  (if the operator does not exist in the cluster):
```
kubectl delete ns mlflow || true
kubectl create ns mlflow
kubectl apply -f resources/postgres/postgres-cluster.yaml -n mlflow --wait
```

6. Wait for the Postgres cluster to be fully deployed:
```
watch kubectl get all -l app=postgres -n mlflow
```

7. Export Postgres environment variables:
```
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-lb-svc -n mlflow -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow
export MLFLOW_DB_USER=pgadmin 
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST}:5432/${MLFLOW_DB_NAME}
kubectl create secret docker-registry mlflow-reg-secret --namespace=mlflow \
        --docker-server=registry-1.docker.io \
        --docker-username="$DOCKER_REG_USERNAME" \
        --docker-password="$DOCKER_REG_PASSWORD"
export REGISTRY_CONFIG=$(kubectl get secret mlflow-reg-secret -n mlflow -o jsonpath='{.data.\.dockerconfigjson}')
```

8. Build and push Docker image:
```
source .env
docker build --build-arg MLFLOW_PORT_NUM=${MLFLOW_PORT} \
 --build-arg ARTIFACT_ROOT_PATH=s3://mlflow \
 -t ${MLFLOW_CONTAINER_REPO} . # example: oawofolu/mlflow-server
docker push ${MLFLOW_CONTAINER_REPO}
```

9. Test running Docker image locally:
```
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-db-secret -n mlflow -o jsonpath='{.data.password}' | base64 --decode)
#export MLFLOW_DB_URI=postgresql://pg-mlflow:${MLFLOW_DB_PASSWORD}@pg-mlflow.mlflow.svc.cluster.local:5432/pg-mlflow
docker run -it --rm -p 8020:8020 \
-e MLFLOW_PORT=${MLFLOW_PORT} \ # ex. 8020
-e ARTIFACT_ROOT=s3://${MLFLOW_BUCKET}/ \ # ex. mlflow
-e MLFLOW_S3_ENDPOINT_URL=https://minio.tanzudatatap.ml/ \ # your Minio endpoint URL
-e AWS_ACCESS_KEY_ID ${AWS_ACCESS_KEY_ID} \ # Your Minio username
-e S3_SECRET_KEY_ID ${AWS_SECRET_ACCESS_KEY} \ # Your Minio password
-e BACKEND_URI ${MLFLOW_DB_URI} \ # Your Postgres DB URI, constructed above
-e MLFLOW_S3_IGNORE_TLS=true\
--name mlflow-server ${MLFLOW_CONTAINER_REPO}
```

10. Deploy MLFLOW access creds: (Requires Kubeseal installation: https://github.com/bitnami-labs/sealed-secrets/releases)
```
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.17.4/controller.yaml
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
kubectl create secret generic mlflowcreds --from-literal=AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} --from-literal=AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} --from-literal=AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} --from-literal=MLFLOW_S3_ENDPOINT_URL=${MLFLOW_S3_ENDPOINT_URL} --from-literal=MLFLOW_S3_IGNORE_TLS=${MLFLOW_S3_IGNORE_TLS} --from-literal=MLFLOW_BACKEND_URI=${MLFLOW_DB_URI} --dry-run=client -o yaml > mlflow-creds-secret.yaml
kubeseal --scope cluster-wide -o yaml <mlflow-creds-secret.yaml> resources/mlflow-creds-sealedsecret.yaml
kubectl create secret docker-registry docker-creds --docker-server=index.docker.io --docker-username=${DOCKER_REG_USERNAME} --docker-password=${DOCKER_REG_PASSWORD} --dry-run -o yaml > docker-creds-secret.yaml
echo '---' >>resources/mlflow-creds-sealedsecret.yaml
kubeseal --scope cluster-wide -o yaml <docker-creds-secret.yaml>>resources/mlflow-creds-sealedsecret.yaml
rm mlflow-creds-secret.yaml docker-creds-secret.yaml
kubectl apply -f resources/mlflow-creds-sealedsecret.yaml -n mlflow
```

12. Deploy MlFlow Tracking Server to Kubernetes: (skip if deploying via TAP)
```
kubectl delete -f resources/mlflow-deployment.yaml -n mlflow || true
source .env # populate the .env file with the appropriate creds - use .env-sample as a template
envsubst < resources/mlflow-deployment.yaml | kubectl apply  -n mlflow -f -
watch kubectl get all -n mlflow
```

13. Deploy MlFlow Tracking Server via TAP:
```
kubectl create ns mlflow-demo
kubectl create clusterrolebinding mlflow-demo:cluster-admin --clusterrole=cluster-admin --user=system:serviceaccount:mlflow-demo:default
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "docker-creds"}],"secrets": [{"name": "docker-creds"}]}' -n mlflow-demo
kubectl apply -f resources/mlflow-workload.yaml -n mlflow-demo
tanzu apps workload tail mlflow-tap --since 64h -n mlflow-demo
```

Finally, access MLFlow in your browser via the endpoint indicated in `resources/mlflow-deployment.yaml` (either via FQDN indicated by Contour's HttpProxy, or by the endpoint indicated by the Service if not using HttpProxy)

## Integrate with TAP

* Deploy the app:
```
source .env
tanzu apps workload create mlflow-server-tap -f resources/tapworkloads/workload.yaml --yes
```

* Tail the logs of the main app:
```
tanzu apps workload tail mlflow-server-tap --since 64h
```

* Once deployment succeeds, get the URL for the main app:
```
tanzu apps workload get mlflow-server-tap    #should yield mlflow-tap.default.<your-domain>
```

* To delete the app:
```
tanzu apps workload delete mlflow-server-tap --yes
```