source .env

envsubst < resources/minio/minio-http-proxy.in.yaml > resources/minio/minio-http-proxy.yaml

helm repo add minio-legacy https://helm.min.io/

kubectl create ns minio-ml

helm install --set resources.requests.memory=1.5Gi,tls.enabled=false --namespace minio-ml minio minio-legacy/minio --set service.type=LoadBalancer --set service.port=9000