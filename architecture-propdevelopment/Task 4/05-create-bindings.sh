#!/usr/bin/env bash
# Связывание пользователей с ролями.

set -euo pipefail
cd "$(dirname "$0")"

CONTEXT="${KUBE_CONTEXT:-minikube}"
DOMAINS=(sales utilities finance data smart-home)

echo "==> привязки уровня кластера"
kubectl --context "$CONTEXT" apply -f manifests/03-bindings.yaml

echo
echo "==> team-<домен> -> namespace-maintainer в остальных доменах"
for ns in "${DOMAINS[@]}"; do
  [ "$ns" = "sales" ] && continue   # для sales привязка описана в манифесте
  kubectl --context "$CONTEXT" create rolebinding team-namespace-maintainer \
    --role=namespace-maintainer --group="team-$ns" -n "$ns" \
    --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f - >/dev/null
  echo "rolebinding.rbac.authorization.k8s.io/team-namespace-maintainer настроен в $ns"
done

echo
echo "Кто с чем связан:"
kubectl --context "$CONTEXT" get clusterrolebindings \
  platform-admins-cluster-admin devops-cluster-configurator \
  observers-view security-auditor-binding \
  -o custom-columns='ПРИВЯЗКА:.metadata.name,РОЛЬ:.roleRef.name,ГРУППА:.subjects[0].name' 2>/dev/null


echo
echo "Привязки созданы"
