#!/usr/bin/env bash
# Убирает за собой: роли, привязки, namespace, запросы на сертификаты и локальные ключи.
set -uo pipefail
cd "$(dirname "$0")"
CONTEXT="${KUBE_CONTEXT:-minikube}"
DOMAINS=(sales utilities finance data smart-home)
USERS=(a.petrov s.ivanova d.smirnov m.orlova)

kubectl --context "$CONTEXT" delete -f manifests/03-bindings.yaml --ignore-not-found
for ns in "${DOMAINS[@]}"; do
  kubectl --context "$CONTEXT" delete rolebinding team-namespace-maintainer -n "$ns" --ignore-not-found
  kubectl --context "$CONTEXT" delete role namespace-maintainer -n "$ns" --ignore-not-found
done
kubectl --context "$CONTEXT" delete clusterrole cluster-configurator security-auditor --ignore-not-found
for u in "${USERS[@]}"; do
  kubectl --context "$CONTEXT" delete csr "$u" --ignore-not-found
done
kubectl --context "$CONTEXT" delete -f manifests/01-namespaces.yaml --ignore-not-found
rm -rf users
echo "очищено"
