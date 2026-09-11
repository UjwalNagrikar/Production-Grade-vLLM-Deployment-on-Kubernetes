SHELL := /bin/sh
NAMESPACE := ai-inference
RELEASE := qwen-vllm

.PHONY: lint deploy status logs destroy

lint:
	helm lint helm/vllm

validate:
	kubectl apply --dry-run=client -f kubernetes/

render:
	helm template $(RELEASE) helm/vllm --namespace $(NAMESPACE)

deploy:
	helm upgrade --install $(RELEASE) helm/vllm --namespace $(NAMESPACE) --create-namespace

status:
	kubectl -n $(NAMESPACE) get all,pvc,ingress

logs:
	kubectl -n $(NAMESPACE) logs deploy/qwen-vllm -f

destroy:
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)
