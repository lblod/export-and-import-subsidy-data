#!/bin/bash
# NOTE: Make sure executable permissions are set (`chmod +x <name>.sh`)

# Variable defaults
FAILED=0
OUT_FOLDER="tmp"
OUT_FOLDER_LOKET="tmp_count_loket"
OUT_FOLDER_SUBSIDY="tmp_count_subsidy"

SUBSIDY_SPARQL_ENDPOINT="http://localhost:8895/sparql"
LOKET_SPARQL_ENDPOINT="http://localhost:8890/sparql"

while :; do
  case $1 in
    --subsidy-sparql-endpoint)
       if [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "[Error] --subsidy-sparql-endpoint option requires a value"
        exit 1
      fi
      SUBSIDY_SPARQL_ENDPOINT="$2"
      shift 1
      ;;
      --loket-sparql-endpoint)
       if [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "[Error] --loket-sparql-endpoint option requires a value"
        exit 1
      fi
      LOKET_SPARQL_ENDPOINT="$2"
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

mkdir -p "$OUT_FOLDER_LOKET"
rm -rf "$OUT_FOLDER_LOKET"/*

mkdir -p "$OUT_FOLDER_SUBSIDY"
rm -rf "$OUT_FOLDER_SUBSIDY"/*

# Store Loket and Subsidy count results in a CSV file
rm -rf "results/"
mkdir "results/"

touch "./results/sanity_type_count_results.csv"
echo "type,loket_count,subsidy_count,equal" > "./results/sanity_type_count_results.csv"

touch "./results/sanity_checks_for_instance_public_services.csv"
echo "bestuursType,label,loket_bestuurs_count,subsidy_bestuurs_count,equal" > "./results/sanity_checks_for_instance_public_services.csv"

for path in sanity_queries/*.sparql; do
    filename=$(basename "$path" .sparql)
    type=$(echo $filename | rev | cut -d '-' -f 1 | rev)

    # Create a folder containing a turtle file with the current timestamp
    current_date=$(date '+%Y%m%d%H%M%S')
    mkdir -p "$OUT_FOLDER_LOKET"/"$current_date-$filename"
    mkdir -p "$OUT_FOLDER_SUBSIDY"/"$current_date-$filename"
    count_ttl_filename="$current_date-$filename.ttl"

    subsidy_type_count=0
    loket_type_count=0

    query=$(cat "$path")
    echo "[INFO] Generating subsidy count for $filename ..."
    if curl --fail -X POST "$SUBSIDY_SPARQL_ENDPOINT" \
      -H 'Accept: text/plain' \
      --form-string "query=$query" >> "$OUT_FOLDER_SUBSIDY"/"$current_date-$filename"/"$count_ttl_filename"; then

      echo "Count was successful!"
      subsidy_type_count=$(cat "$OUT_FOLDER_SUBSIDY"/"$current_date-$filename"/"$count_ttl_filename" | grep value | cut -d ' ' -f 3 | awk -F'[""]' '{print $2}')
    else
      echo "[ERROR] Count for $type in subsidy failed!"
      FAILED+=1
    fi;

    echo -e "\n"

    echo "[INFO] Generating loket count for $filename ..."
    if curl --fail -X POST "$LOKET_SPARQL_ENDPOINT" \
      -H 'Accept: text/plain' \
      --form-string "query=$query" >> "$OUT_FOLDER_LOKET"/"$current_date-$filename"/"$count_ttl_filename"; then

      echo "Count was successful!"
      loket_type_count=$(cat "$OUT_FOLDER_LOKET"/"$current_date-$filename"/"$count_ttl_filename" | grep value | cut -d ' ' -f 3 | awk -F'[""]' '{print $2}')
    else
      echo "[ERROR] Count for $type in Loket failed!"
      FAILED+=1
    fi;

    if [ $subsidy_type_count == $loket_type_count ]; then
      echo "$type,$loket_type_count,$subsidy_type_count,✅" >> "./results/sanity_type_count_results.csv"
    else
      echo "$type,$loket_type_count,$subsidy_type_count,❌" >> "./results/sanity_type_count_results.csv"
    fi;

    echo -e "================================================================================\n"
done

echo "[INFO] Export done! You can find your count export(s) in $OUT_FOLDER_LOKET and $OUT_FOLDER_SUBSIDY."
echo "[INFO] Count results for types are in results/sanity_type_count_results.csv"

# if [ -f "./tmp_select_output/select_non_eredienst_bestuurseenheden_having_instance_public_services.csv" ]; then
#   while IFS="," read -r h bestuursType label; do
#     string=$(cat << EOF
# SELECT COUNT DISTINCT * WHERE {
#   GRAPH <$h> {
#     ?s a <http://purl.org/vocab/cpsv#PublicService> ;
#       ?p ?o .
#   }
# }
# EOF
# )

#     subsidy_bestuurs_count=0
#     loket_bestuurs_count=0

#     if curl --fail -X POST "$SUBSIDY_SPARQL_ENDPOINT" \
#       -H 'Accept: text/csv' \
#       --form-string "query=$string" > "$OUT_FOLDER"/count_results.csv; then

#       subsidy_bestuurs_count=$(cat "$OUT_FOLDER"/count_results.csv | tail -n +2)
#     else
#       echo "[ERROR] "
#       FAILED+=1
#     fi;

#     if curl --fail -X POST "$LOKET_SPARQL_ENDPOINT" \
#       -H 'Accept: text/csv' \
#       --form-string "query=$string" > "$OUT_FOLDER"/count_results.csv; then

#       loket_bestuurs_count=$(cat "$OUT_FOLDER"/count_results.csv | tail -n +2)
#     else
#       echo "[ERROR] Select for $type failed!"
#       FAILED+=1
#     fi;

#     if [ $subsidy_bestuurs_count == $loket_bestuurs_count ]; then
#       echo "$bestuursType,$label,$loket_bestuurs_count,$subsidy_bestuurs_count,✅" >> "./results/sanity_checks_for_instance_public_services.csv"
#     else
#       echo "$bestuursType,$label,$loket_bestuurs_count,$subsidy_bestuurs_count,❌" >> "./results/sanity_checks_for_instance_public_services.csv"
#     fi;

#   done < <(tail -n +2 tmp_select_output/select_non_eredienst_bestuurseenheden_having_instance_public_services.csv)
# fi;

echo "[INFO] Count results for public services per bestuurseenheid are in results/sanity_checks_for_instance_public_services.csv"

if ((FAILED > 0)); then
  echo "[WARNING] $FAILED queries failed, export incomplete ..."
fi;
