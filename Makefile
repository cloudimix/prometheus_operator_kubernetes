#!/bin/bash
.ONESHELL:

kubespray:
	git clone -b release-2.19 --single-branch https://github.com/kubernetes-sigs/kubespray.git
	cp -nprf kubespray/* myfiles/* .

.PHONY: install
install:
	/usr/bin/env python3 -m venv venv
	. venv/bin/activate
	pip install -r requirements.txt
	ansible-playbook id_rsa_generating.yml
	terraform init
	terraform apply -auto-approve
	if [ ! -f ~/.vault_pass ]
	  then
		  echo testpass > ~/.vault_pass
	fi
	ansible-galaxy install -r requirements.yml
	ansible-playbook -i dynamic_inventory.py --vault-password-file ~/.vault_pass -b -u=root main.yml -vv
	ansible-playbook -i dynamic_inventory.py kubectl_localhost.yml -vv

.PHONY: golang
golang:
	ansible-playbook golang.yaml

operator-sdk:
	export PATH=/usr/local/go/bin:$(PATH)
	git clone -b master --single-branch https://github.com/operator-framework/operator-sdk
	cd operator-sdk
	make install
	operator-sdk olm install
	kubectl -n olm wait --for=jsonpath='{.status.phase}'=Installing csv/packageserver --timeout=10s
	kubectl -n olm delete csv packageserver
	kubectl -n olm delete deploy catalog-operator packageserver
	kubectl -n olm delete pod -l olm.catalogSource=operatorhubio-catalog
	kubectl -n olm delete svc operatorhubio-catalog

kube-prometheus:
	git clone -b release-0.11 --single-branch https://github.com/prometheus-operator/kube-prometheus.git
	cd kube-prometheus/
	kubectl apply --server-side -f manifests/setup --force-conflicts
	kubectl wait --for condition=Established \
		--all CustomResourceDefinition \
		--namespace=monitoring
	kubectl apply -f manifests/

.PHONY: promconf
promconf:
	kubectl -n monitoring patch alertmanager main --type='merge' --patch-file patch-file.yaml
	kubectl apply -f telegram_secret.yaml -f custom-rules.yaml -f alertmanagerconfig.yaml

.PHONY: clean
clean:
		rm -rf kubespray/ operator-sdk/ kube-prometheus/

all: kubespray install golang operator-sdk kube-prometheus promconf
