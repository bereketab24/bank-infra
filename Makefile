#Makefile for Banking Platform Local Environment
#Usage: make [command]

# ---Configuration---
CLUSTER_NAME := bank-cluster
MEMORY := 5240
CPUS := 2
DRIVER := docker

# ---Colors for the printing---
CYAN := \e[36m #36 is the color code for Cyan color
RESET := \e[0m #0 is the color code to reset into default color

.PHONY: help up bootstrap access-argo down clean status dashboard cluster-info

help: ## Show this help message
		@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Start Minikube
		@echo -e "$(CYAN)Starting Minikube Cluster '$(CLUSTER_NAME)'...$(RESET)"
		@minikube start --profile $(CLUSTER_NAME) --driver $(DRIVER) --memory $(MEMORY) --cpus $(CPUS) --addons ingress --addons metrics-server --addons dashboard
		@echo -e "$(CYAN)Cluster is up! Switching context with: kubectl config use-context $(CLUSTER_NAME)$(RESET)"
		kubectl config use-context bank-cluster

bootstrap: ## Install the Platform Tools
		@echo -e "$(CYAN) Adding ArgoCD helm repo$(RESET)"
		helm repo add argo https://argoproj.github.io/argo-helm
		helm repo update
		@echo -e "$(CYAN) Installing ArgoCD...$(RESET)"
		helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --values 00-tooling/argocd/values.yaml --wait

		@echo -e "$(CYAN)Waiting for the ArgoCD server to be ready...$(RESET)"
		kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
		@echo -e "$(CYAN) ArgoCD is ready, the password is: $(RESET)"
		@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

access-argo: ## Create a tunnel connection to ArgoCD to access the dashboard
		@echo -e "$(CYAN)Opening tunnel to ArgoCD at https://localhost:8085$(RESET)"
		kubectl port-forward svc/argocd-server -n argocd 8085:443

down: ## Stop cluster for freeing up RAM without losing the cluster
		@echo -e "$(CYAN)Stopping cluster...$(RESET)"
		minikube stop -p $(CLUSTER_NAME)

clean: ## Delete cluster completely
		@echo -e "$(CYAN)Deleting cluster...$(RESET)"
		minikube delete -p $(CLUSTER_NAME)

status: ## Check cluster status
		minikube status -p $(CLUSTER_NAME)

dashboard: ## Open K8s Dashboard
		minikube dashboard -p $(CLUSTER_NAME)

cluster-info: ## Check the cluster info per cluster name
		kubectl cluster-info --context $(CLUSTER_NAME)




