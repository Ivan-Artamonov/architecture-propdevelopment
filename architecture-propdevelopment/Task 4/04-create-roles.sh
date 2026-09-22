#!/usr/bin/env bash
# Создание ролей.

set -euo pipefail
cd "$(dirname "$0")"

CONTEXT="${KUBE_CONTEXT:-minikube}"
DOMAINS=(sales utilities finance data smart-home)


echo "==> namespace по доменам"
kubectl --context "$CONTEXT" apply -f manifests/01-namespaces.yaml

echo
echo "==> роли"
kubectl --context "$CONTEXT" apply -f manifests/02-roles.yaml

echo
echo "==> namespace-maintainer в остальных доменах"
for ns in "${DOMAINS[@]}"; do
  [ "$ns" = "sales" ] && continue
  kubectl --context "$CONTEXT" get role namespace-maintainer -n sales -o yaml \
    | sed "s/^  namespace: sales$/  namespace: $ns/" \
    | kubectl --context "$CONTEXT" apply -n "$ns" -f - >/dev/null
  echo "role.rbac.authorization.k8s.io/namespace-maintainer настроен в $ns"
done


echo
echo "Роли созданы. Дальше: ./05-create-bindings.sh"
