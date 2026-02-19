#Makefile for Banking Platform Local Environment
#Usage: make [command]

# ---Configuration---
CLUSTER_NAME := bank-cluster
MEMORY := 5240
CPUS := 2
DRIVER := docker

APP_NAMESPACES := dev qa staging prod
TOOL_NAMESPACES := kafka rabbitmq redis postgres monitoring jenkins
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

install-argo: ## Install ArgoCD Tools
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
		@echo -e "$(CYAN)Opening tunnel to ArgoCD at http://localhost:8085$(RESET)"
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

create-namespaces: ## Create namespaces to imitate different deployment environments(dev, qa, staging, prod)
		@echo -e "$(CYAN)Creating app namespaces: $(APP_NAMESPACES)$(RESET)"
		@for ns in $(APP_NAMESPACES); do \
			kubectl create namespace $$ns --dry-run=client -o yaml | kubectl apply -f -; \
		done
		@echo -e "$(CYAN)Creating tool namespaces: $(TOOL_NAMESPACES)$(RESET)"
		@for ns in $(TOOL_NAMESPACES); do \
  			kubectl create namespace $$ns --dry-run=client -o yaml | kubectl apply -f -; \
  		done
install-kafka: ## Install shared Kafka using Strimzi Operator i.e managed kafka
		@echo -e "$(CYAN)Installing Strimzi Kafka Operator...$(RESET)"
		helm repo add strimzi https://strimzi.io/charts/
		helm repo update strimzi
		helm upgrade --install strimzi strimzi/strimzi-kafka-operator \
				--namespace kafka \
				--create-namespace \
				--set watchAnyNamespace=true \
				--wait
install-rabbitmq: ## Install shared RabbitMQ
		@echo -e "$(CYAN)Installing RabbitMQ...$(RESET)"
		helm repo add bitnami https://charts.bitnami.com/bitnami
		helm repo update bitnami
		helm upgrade --install rabbitmq bitnami/rabbitmq \
				--namespace rabbitmq \
				--create-namespace \
				--wait
install-redis: ## Install shared Redis
		@echo -e "$(CYAN)Installing Redis...$(RESET)"
		helm repo add bitnami https://charts.bitnami.com/bitnami
		helm repo update bitnami
		helm upgrade --install redis bitnami/redis \
				--namespace redis \
				--create-namespace \
				--wait
install-postgres: ## Install shared Postgres Operator
		@echo -e "$(CYAN)Installing Postgres Operator...$(RESET)"
		helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
		helm repo update postgres-operator
		helm upgrade --install postgres-operator postgres-operator/postgres-operator \
				--namespace postgres \
				--create-namespace \
				--wait
install-monitoring: ## Install Prometheus and Grafana
		@echo -e "$(CYAN)Installing Prometheus and Grafana via kube-prometheus-stack...$(RESET)"
		helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
		helm repo update
		helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
				--namespace monitoring \
				--create-namespace \
				--values 00-tooling/monitoring/values.yaml \
				--wait
install-jenkins: ## Install Jenkins
		@echo -e "$(CYAN)Installing Jenkins and Applying PV and SA...$(RESET)"
		kubectl apply -f 00-tooling/jenkins/pv.yaml
		kubectl apply -f 00-tooling/jenkins/sa.yaml
		minikube ssh "sudo mkdir -p /data/jenkins-volume/ && sudo chown -R 1000:1000 /data/jenkins-volume/"
		helm repo add jenkinsci https://charts.jenkins.io
		helm repo update
		helm upgrade --install jenkins jenkinsci/jenkins \
				--namespace jenkins \
				-- values 00-tooling/jenkins/values.yaml \
				--wait
access-jenkins: ##Open Jenkins via NodePort
		@echo -e "$(CYAN)Jenkins available at http://$(minikube ip):32000$(RESET)"
		@echo -e "$(CYAN)Admin password: $(RESET)"
		@kubectl get secret -n jenkins jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 -d && echo ""
access-grafana: ##Open Grafana UI
		@export POD_NAME=$(kubectl --namespace monitoring get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=monitoring" -oname)
		kubectl --namespace monitoring port-forward $POD_NAME 3000
		kubectl get secret --namespace monitoring -l app.kubernetes.io/component=admin-secret -o jsonpath="{.items[0].data.admin-password}" | base64 --decode ; echo

bootstrap: create-namespaces install-argo install-kafka install-redis install-postgres install-monitoring install-jenkins## Install the entire tools in the cluster

