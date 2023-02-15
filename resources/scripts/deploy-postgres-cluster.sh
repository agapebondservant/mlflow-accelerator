# Generate TLS
openssl genrsa -out tls.key 2048
openssl req -new -x509 -nodes -days 730 -key tls.key -out tls.crt -config resources/postgres/openssl.conf
kubectl delete secret tls-ssl-postgres || true
kubectl create secret generic tls-ssl-postgres --from-file=tls.key --from-file=tls.crt --from-file=ca.crt=tls.crt --namespace ${POSTGRES_CLUSTER_NAMESPACE}

# deploy Postgres cluster
kubectl wait --for=condition=Ready pod -l app=postgres-operator --timeout=120s
kubectl apply -f resources/postgres/postgres-tap-cluster.yaml --namespace ${POSTGRES_CLUSTER_NAMESPACE}