# Generate Postgres/Minio variables
source .env
export MLFLOW_DB_HOST=$(kubectl get svc pg-mlflow-instance-lb-svc -n${POSTGRES_CLUSTER_NAMESPACE} -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
export MLFLOW_DB_NAME=pg-mlflow-instance
export MLFLOW_DB_HOST_LOCAL=${MLFLOW_DB_NAME}.${POSTGRES_CLUSTER_NAMESPACE}.svc.cluster.local
export MLFLOW_DB_USER=pgadmin
export MLFLOW_DB_PASSWORD=$(kubectl get secret pg-mlflow-instance-db-secret -n ${POSTGRES_CLUSTER_NAMESPACE} -o jsonpath="{.data.password}" | base64 --decode)
export MLFLOW_DB_URI=postgresql://${MLFLOW_DB_USER}:${MLFLOW_DB_PASSWORD}@${MLFLOW_DB_HOST_LOCAL}:5432/${MLFLOW_DB_NAME}?sslmode=require
export MLFLOW_S3_ENDPOINT_URL=http://${MLFLOW_S3_ENDPOINT_FQDN}
export AWS_ACCESS_KEY_ID=$(kubectl get secret --namespace ${MINIO_BUCKET_NAMESPACE} minio -o jsonpath="{.data.root-user}" | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret --namespace ${MINIO_BUCKET_NAMESPACE} minio -o jsonpath="{.data.root-password}" | base64 -d)

# Generate values.yaml
cat > $1 <<- EOF
region: ${S3_DEFAULT_REGION}
artifact_store: ${MLFLOW_S3_ENDPOINT_URL}
access_key: ${AWS_ACCESS_KEY_ID}
secret_key: ${AWS_SECRET_ACCESS_KEY}
version: ${MLFLOW_VERSION:-"1.0.0"}
backing_store: ${MLFLOW_DB_URI:-"sqlite:///my.db"}
ingress_fqdn: mlflow.${MLFLOW_INGRESS_DOMAIN}
bucket: ${MLFLOW_BUCKET:-"mlflow"}
ignore_tls: "true"
ingress_domain: ${MLFLOW_INGRESS_DOMAIN}
EOF