#!/bin/bash

echo "Set up tools"

# Set cluster context
kubectl config use-context minikube

# Install ArgoCD if it hasn't already been installed
if kubectl get ns argocd >/dev/null 2>&1 && [[ $(kubectl get deployments -n argocd -o jsonpath='{.items[*].metadata.name}') ]]
then
    echo "Argo CD is installed."
else
    echo "Argo CD is not installed. Installing it now ..."
    if ! kubectl get ns argocd >/dev/null 2>&1; then
        kubectl create ns argocd
    fi
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

# Keep Argo CD in idle state for 15 minutes
sleep 15m

# Start a port-forward in another window
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial password
password=$(argocd admin initial-password -n argocd | head -n 1 | awk '{print $NF}')

# Login to ArgoCD
argocd login localhost:8080 --insecure --username=admin --password=$password

# Get a list of cluster names
clusters=$(kubectl config get-contexts -o name)

# Loop through each cluster name
for cluster in $clusters; do
  # Check if the cluster name is not minikube
  if [ "$cluster" != "minikube" ]; then
    # Run argocd cluster add <clustername> --yes
    argocd cluster add $cluster --yes
  fi
done

# fork the following repository https://github.com/argoproj/argocd-example-apps

export github_username="your_github_username"

echo "Deploy guestbook application"

# Define the contents of the ApplicationSet
cat <<EOF > guestbook-applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  generators:
  - clusters: {} # Automatically use all clusters defined within Argo CD
  template:
    metadata:
      name: '{{name}}-guestbook' # 'name' field of the Secret
    spec:
      project: "default"
      source:
        repoURL: https://github.com/$github_username/argocd-example-apps/
        targetRevision: HEAD
        path: helm-guestbook
      destination:
        server: '{{server}}' # 'server' field of the secret
        namespace: guestbook-argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF

# Run the command to create the ApplicationSet
argocd appset create guestbook-applicationset.yaml

# Check the current deployed image tag
kubectl get pods --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace,IMAGE:.spec.containers[].image' | awk '/guestbook/ {split($2,a,":"); print $1, a[2]}'

# Perform a rolling update after 15 minutes
sleep 15m

echo "Perform a rolling update"

# Update the image tag of helm-guestbook in git repository
git clone https://github.com/$github_username/argocd-example-apps.git
cd argocd-example-apps/
sed -i 's/tag: .*/tag: 0.2/' helm-guestbook/values.yaml
sed -i 's/version: .*/version: 0.2.0/' helm-guestbook/Chart.yaml
sed -i 's/appVersion:.*/appVersion: 0.2.0/' helm-guestbook/Chart.yaml
git add helm-guestbook/values.yaml helm-guestbook/Chart.yaml
git commit -m "Perform a rolling update"
git push

# Check the current deployed image tag
kubectl get pods --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace,IMAGE:.spec.containers[].image' | awk '/guestbook/ {split($2,a,":"); print $1, a[2]}'

# Perform a rollback 15 after minutes
sleep 15m

echo "Perform a rollback"

# Update the image tag of helm-guestbook in git repository
sed -i 's/tag: .*/tag: 0.1/' helm-guestbook/values.yaml
sed -i 's/version: .*/version: 0.1.0/' helm-guestbook/Chart.yaml
git add helm-guestbook/values.yaml helm-guestbook/Chart.yaml
git commit -m "Rollback to a previous version"
git push

# Check the current deployed image tag
kubectl get pods --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace,IMAGE:.spec.containers[].image' | awk '/guestbook/ {split($2,a,":"); print $1, a[2]}'

# Perform a clean up after 15 after minutes
sleep 15m

echo "Clean up"

# Delete the ApplicationSet and the namespaces
argocd appset delete guestbook --yes

# get the list of clusters
clusters=$(kubectl config get-contexts -o name)

# iterate over each cluster and switch to it
for cluster in $clusters
do
    echo "Switching to cluster: $cluster"
    kubectl config use-context $cluster

    # check if the namespace exists and delete it if it does
    namespace=$(kubectl get ns | grep guestbook-argocd | awk '{print $1}')
    if [ ! -z "$namespace" ]
    then
        echo "Deleting namespace: $namespace"
        kubectl delete ns $namespace
    else
        echo "Namespace guestbook-argocd does not exist"
    fi
done

# Loop through each cluster name
for cluster in $clusters 
do
	# Check if the cluster name is not minikube
	if [ "$cluster" != "minikube" ]
	then
		# Run argocd cluster add <clustername> --yes
		argocd cluster rm $cluster --yes
	fi
done
