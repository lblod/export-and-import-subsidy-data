#!/bin/bash
# NOTE: Make sure executable permissions are set (`chmod +x <name>.sh`)

TEMP_GRAPH="http://mu.semte.ch/graphs/temp"

while :; do
  case $1 in
    --write-temp-graphs)
      if [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "[Error] --write-temp-graphs option requires a value"
        exit 1
      fi
      TEMP_GRAPH="$2"
      shift 1
      ;;
    -?*)
      printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
      ;;
    # Default case: No more options, so break out of the loop
    *)
      break
  esac
  shift
done

for path in ./subsidy-production-ttl-files/*.ttl; do
    filename=$(basename "$path" .ttl)
    type=$(echo $filename | rev | cut -d '-' -f 1 | rev)

    query=$(cat "$path")
    echo "[INFO] Importing $filename ..."
    isql-v exec="DB.DBA.TTLP_MT(file_to_string_output('/tmp/subsidy-production-ttl-files/$filename.ttl'), '', '$TEMP_GRAPH/$type');"

    echo -e "================================================================================\n"
done

echo "[INFO] Import done! You can query your import(s) in their respective temp graphs"
