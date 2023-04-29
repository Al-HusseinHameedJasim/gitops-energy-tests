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

# fork the following repository https://github.com/argoproj/argocd-example-apps

export github_username="your_github_username"

echo "Deploy guestbook application"

# Deploy the application with Argo CD
kubectl create namespace guestbook-argocd
argocd app create guestbook \
  --app-namespace argocd \
  --repo https://github.com/Al-HusseinHameedJasim/argocd-example-apps.git \
  --path helm-guestbook \
  --release-name guestbook \
  --dest-namespace guestbook-argocd \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated \
  --self-heal \
  --auto-prune

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
argocd app delete guestbook --yes
kubectl delete namespace guestbook-argocd
