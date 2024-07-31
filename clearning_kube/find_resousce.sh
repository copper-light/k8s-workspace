#!/usr/bin/env bash
die() {
  echo "$*" 1>&2
  exit 1
}
need() {
  command -v "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"

echo "------------------------------------------------"
echo "get all resources in namespace..."
echo "------------------------------------------------"
FOUND=""
NOT_FOUND=""
ERROR=""
RESOURCES=$(kubectl api-resources --namespaced=true -o name)
for resource in $RESOURCES; do
  if [[ $resource =~ "metrics" ]]; then
    continue
  fi

  found=$(kubectl get "$resource" 2>&1)
  if [[ "$found" == "No resources found." ]]; then
    echo "$resource: $found"
    NOT_FOUND="$NOT_FOUND\n$resource"
  elif [[ $found =~ "Error" ]]; then
    echo "$resource: $found"
    ERROR="$ERROR\n$resource"
  else
    printf ">> %s:\n%s" "$resource" "$found"
    FOUND="$FOUND\n$resource"
  fi
done

echo "------------------------------------------------"
echo "summary"
echo "------------------------------------------------"
printf ">> found: %b\n" "$FOUND"
echo "------------------------------------------------"
printf ">> not found: %b\n" "$NOT_FOUND"
echo "------------------------------------------------"
printf ">> error: %b\n" "$ERROR"
