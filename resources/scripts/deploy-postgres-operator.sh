source .env

# login to container registry
echo $DOCKER_REG_PASSWORD | docker login registry-1.docker.io --username=$DOCKER_REG_USERNAME --password-stdin

# install the operator
kubectl create secret docker-registry image-pull-secret --namespace=default --docker-username=$DOCKER_REG_USERNAME --docker-password=$DOCKER_REG_PASSWORD --dry-run -o yaml | kubectl apply -f -

helm uninstall postgres --namespace default;

helm uninstall postgres --namespace postgres-system;

for i in $(kubectl get clusterrole | grep postgres | grep -v postgres-operator-default-cluster-role); do kubectl delete clusterrole ${i} > /dev/null 2>&1; done;

for i in $(kubectl get clusterrolebinding | grep postgres | grep -v postgres-operator-default-cluster-role-binding); do kubectl delete clusterrolebinding ${i} > /dev/null 2>&1; done;

for i in $(kubectl get certificate -n cert-manager | grep postgres); do kubectl delete certificate -n cert-manager ${i} > /dev/null 2>&1; done;

for i in $(kubectl get clusterissuer | grep postgres); do kubectl delete clusterissuer ${i} > /dev/null 2>&1; done;

for i in $(kubectl get mutatingwebhookconfiguration | grep postgres); do kubectl delete mutatingwebhookconfiguration ${i} > /dev/null 2>&1; done;

for i in $(kubectl get validatingwebhookconfiguration | grep postgres); do kubectl delete validatingwebhookconfiguration ${i} > /dev/null 2>&1; done;

for i in $(kubectl get crd | grep postgres); do kubectl delete crd ${i} > /dev/null 2>&1; done;

envsubst < resources/postgres/overrides.in.yaml > resources/postgres/overrides.yaml

helm install postgres resources/postgres/operatorv${POSTGRES_OPERATOR_VERSION} -f resources/postgres/overrides.yaml --namespace default --wait &> /dev/null;

kubectl apply -f resources/postgres/operatorv${POSTGRES_OPERATOR_VERSION}/crds/