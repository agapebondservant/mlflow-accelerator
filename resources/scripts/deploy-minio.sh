source .env

kubectl delete ns ${MINIO_BUCKET_NAMESPACE}

envsubst < resources/minio/minio-http-proxy.in.yaml > resources/minio/minio-http-proxy.yaml

helm install --set resources.requests.memory=1.5Gi,auth.rootUser=minio,ingress.enabled=true,ingress.hostname=${MLFLOW_S3_ENDPOINT_FQDN} \
--namespace ${MINIO_BUCKET_NAMESPACE} minio oci://registry-1.docker.io/bitnamicharts/minio --create-namespace

kubectl apply -f resources/minio/minio-http-proxy.yaml --namespace ${MINIO_BUCKET_NAMESPACE}

export ACCESS_KEY_ID=$(kubectl get secret --namespace ${MINIO_BUCKET_NAMESPACE} minio -o jsonpath="{.data.root-user}" | base64 -d)

export SECRET_ACCESS_KEY=$(kubectl get secret --namespace ${MINIO_BUCKET_NAMESPACE} minio -o jsonpath="{.data.root-password}" | base64 -d)

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=minio -n ${MINIO_BUCKET_NAMESPACE} --timeout=120s

sleep 5

mc config host add --insecure data-e2e-minio-ml http://${MLFLOW_S3_ENDPOINT_FQDN} ${ACCESS_KEY_ID} ${SECRET_ACCESS_KEY}

mc mb --insecure -p data-e2e-minio-ml/mlflow && mc policy --insecure set public data-e2e-minio-ml/mlflow
