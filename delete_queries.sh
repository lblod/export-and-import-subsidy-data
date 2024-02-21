#!/bin/bash
# NOTE: Make sure executable permissions are set (`chmod +x <name>.sh`)

# Variable defaults
FAILED=0
OUT_FOLDER="tmp_delete_output"

SPARQL_ENDPOINT="http://localhost:8890/sparql"

while :; do
  case $1 in
    --sparql-endpoint)
       if [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "[Error] --sparql-endpoint option requires a value"
        exit 1
      fi
      SPARQL_ENDPOINT="$2"
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

mkdir -p "$OUT_FOLDER"
rm -rf "$OUT_FOLDER"/*

for path in delete_queries/*.sparql; do
    filename=$(basename "$path" .sparql)
    type=$(echo $filename | rev | cut -d '-' -f 1 | rev)

    # Create a folder containing a turtle file with the current timestamp
    current_date=$(date '+%Y%m%d%H%M%S')
    mkdir -p "$OUT_FOLDER"/"$current_date-$filename"
    count_ttl_filename="$current_date-$filename.ttl"

    query=$(cat "$path")
    if curl --fail -X POST "$SPARQL_ENDPOINT" \
      -H 'Accept: text/plain' \
      --form-string "query=$query" >> "$OUT_FOLDER"/"$current_date-$filename"/"$count_ttl_filename"; then

      echo "Delete for $type was successful!"
    else
      echo "[ERROR] Delete for $type failed!"
      FAILED+=1
    fi;

    echo -e "================================================================================\n"
done

echo "[INFO] Export done! You can find your delete export(s) results in $OUT_FOLDER."

if ((FAILED > 0)); then
  echo "[WARNING] $FAILED queries failed, delete incomplete ..."
fi;