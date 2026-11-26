# Shared helpers for the osac-lab-* scripts. Sourced after lab-config.sh
# and after the script has set $lab, $WORK, $errfile and exported
# KUBECONFIG. Provides the listing, deleting and finalizer-strip helpers
# both the factory reset and the wipe use.

kind_names_in() { # kind namespace
  local kind=$1 namespace=$2 output
  if output=$(oc -n "$namespace" get "$kind" -o name 2>"$errfile"); then
    printf '%s' "$output"
    return 0
  fi
  case "$(cat "$errfile")" in
    *"the server doesn't have the resource type"*) return 0 ;;
    *)
      printf '%s: oc get %s failed:\n%s\n' "$lab" "$kind" "$(cat "$errfile")" >&2
      return 1
      ;;
  esac
}

# Instances of one kind minus the built-in tenants, which are the
# service's own state and are re-created on startup.
demo_kind_names() { # kind namespace
  local kind=$1 namespace=$2 names
  names=$(kind_names_in "$kind" "$namespace")
  if [ "$kind" = tenants ]; then
    printf '%s' "$names" | grep -vw -e shared -e system || true
  else
    printf '%s' "$names"
  fi
}

namespace_name() { # namespace
  local namespace=$1 output
  if output=$(oc get namespace "$namespace" -o name 2>"$errfile"); then
    printf '%s' "$output"
    return 0
  fi
  case "$(cat "$errfile")" in
    *NotFound*) return 0 ;;
    *)
      printf '%s: oc get namespace %s failed:\n%s\n' "$lab" "$namespace" "$(cat "$errfile")" >&2
      return 1
      ;;
  esac
}

wait_names_gone() { # description timeout_seconds listing_command...
  local description=$1 timeout=$2
  shift 2
  local deadline=$((SECONDS + timeout)) names
  while true; do
    names=$("$@")
    if [ -z "$names" ]; then
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      printf '%s: timed out after %ss waiting for %s; still present:\n%s\n' \
        "$lab" "$timeout" "$description" "$names" >&2
      return 1
    fi
    printf '%s: waiting for %s (%ss left): %s\n' "$lab" "$description" \
      "$((deadline - SECONDS))" "$(printf '%s' "$names" | tr '\n' ' ')"
    sleep 10
  done
}

tenant_namespaces() {
  local output
  if ! output=$(oc get namespace -l osac.openshift.io/tenant-ref \
      -o custom-columns=NAME:.metadata.name --no-headers 2>"$errfile"); then
    printf '%s: listing tenant namespaces failed:\n%s\n' "$lab" "$(cat "$errfile")" >&2
    return 1
  fi
  # grep exits 1 when nothing matches, which means no demo namespaces:
  # a success with empty output, not a failure.
  printf '%s' "$output" | grep -vw -e system -e shared || true
}

guest_namespaces() {
  oc get namespace -o custom-columns=NAME:.metadata.name --no-headers 2>"$errfile" |
    sed -n '/^osac-order-/p' ||
    { printf '%s: listing namespaces failed:\n%s\n' "$lab" "$(cat "$errfile")" >&2; return 1; }
}

# Delete instances by name. The names come from `oc get -o name` in
# resource/name form, which oc accepts without a separate kind argument.
# The protected kinds go out as the namespace-controller: the
# osac-osac-managed-resources admission policy refuses plain kubectl
# deletes for them, and only the Kubernetes controllers pass both that
# policy and RBAC.
delete_kind() { # kind names... (names in resource/name form)
  local kind=$1
  shift
  case " $PROTECTED_KINDS " in
    *" $kind "*)
      oc --as=system:serviceaccount:kube-system:namespace-controller \
        -n "$OSAC_NS" delete "$@" --wait=false
      ;;
    *)
      oc -n "$OSAC_NS" delete "$@" --wait=false
      ;;
  esac
}

# Remove the finalizers from this kind's instances that are already
# Terminating (a deletionTimestamp is set). Live instances are never
# touched: their finalizers belong to their running controllers. A
# built-in left Terminating by an earlier failed run is completed here
# too; the fulfillment service re-creates the built-in tenants on
# startup.
strip_kind_finalizers() { # kind
  local kind=$1 names name deleting stripped=0
  names=$(kind_names_in "$kind" "$OSAC_NS")
  [ -z "$names" ] && return 0
  for name in $names; do
    name=${name##*/}
    deleting=$(oc -n "$OSAC_NS" get "$kind" "$name" \
      -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
    [ -n "$deleting" ] || continue
    note "stripping orphaned finalizers from $kind/$name"
    case " $PROTECTED_KINDS " in
      *" $kind "*)
        oc --as=system:serviceaccount:osac:osac-operator \
          -n "$OSAC_NS" patch "$kind" "$name" \
          --type merge -p '{"metadata":{"finalizers":null}}'
        ;;
      *)
        oc -n "$OSAC_NS" patch "$kind" "$name" \
          --type merge -p '{"metadata":{"finalizers":null}}'
        ;;
    esac
    stripped=$((stripped + 1))
  done
  [ "$stripped" = 0 ] || note "stripped finalizers from $stripped $kind instance(s)"
}

# Stop the controllers, delete every demo custom resource, and strip the
# orphaned finalizers. Used by both the factory reset and the wipe after
# their own scale-down.
strip_all_kinds() {
  local kind names left=0
  for kind in $OSAC_CRD_KINDS; do
    names=$(demo_kind_names "$kind" "$OSAC_NS")
    [ -n "$names" ] && left=1
    # A built-in left Terminating by an earlier failed run also needs work.
    if [ "$kind" = tenants ]; then
      local name deleting
      for name in $(kind_names_in tenants "$OSAC_NS"); do
        deleting=$(oc -n "$OSAC_NS" get tenants "${name##*/}" \
          -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
        [ -n "$deleting" ] && left=1
      done
    fi
  done
  if [ "$left" = 0 ]; then
    note 'no osac custom resources'
    return 0
  fi
  for kind in $OSAC_CRD_KINDS; do
    names=$(demo_kind_names "$kind" "$OSAC_NS")
    if [ -n "$names" ]; then
      note "deleting $kind:$(printf '%s' "$names" | tr '\n' ' ')"
      delete_kind "$kind" $names
    fi
  done
  for kind in $OSAC_CRD_KINDS; do
    strip_kind_finalizers "$kind"
  done
  for kind in $OSAC_CRD_KINDS; do
    wait_names_gone "the stripped $kind to disappear" "${WIPE_WAIT_STRIP:-300}" \
      demo_kind_names "$kind" "$OSAC_NS" ||
      fail "$kind did not disappear after the finalizer strip"
  done
}
