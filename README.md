# Transfer subsidy production data from `app-digitaal-loket` to `app-subsidie-loket`

Guide based on [https://github.com/Riadabd/export-and-import-lpdc-data](https://github.com/Riadabd/export-and-import-lpdc-data)

## Note on Virtuoso settings

The following parameters must be changed inside `config/virtuoso/virtuoso-production.ini` before any data export/import was performed due to some types containing a large number of triples.

```
MaxVectorSize     = 10000000 ; Query vector size threshold, edited from 1 million to 10 million
MaxSortedTopRows  = 10000000 ; Edited from 1 million to 10 million
ResultSetMaxRows  = 10000000 ; Edited from 1 million to 10 million
```

## Export subsidy production data

First, download the production database onto your local system since some database parameters have to be tweaked before data can be correctly exported. The [Note on Virtuoso settings](#note-on-virtuoso-settings) section describes what file and which parameters need to be changed.

Add the following to your `docker-compose.override.yml` in `app-digitaal-loket` in order to load the production database:

```
virtuoso:
    volumes:
      - ./data/db:/data
      - ./config/virtuoso/virtuoso-production.ini:/data/virtuoso.ini
      - ./config/virtuoso/:/opt/virtuoso-scripts
    command: "tail -f /dev/null"
```

Load the production database into your local `app-digitaal-loket` repo and wait for migrations to run. Once done, comment out `command: "tail -f /dev/null"`. Data export can now commence.

Exporting the data will occur through [sparql-export-script](https://github.com/Riadabd/sparql-export-script). The necessary `CONSTRUCT` queries should be placed inside the `construct_queries/` directory; these queries have already been written and are ready to be used. The default endpoint for the export service is `http://localhost:8890`, so there is no need to specify one (provided you have the loket repo running and are using the default SPARQL endpoint). The script will output a turtle file for each type; they are as follows:
* Address
* Concept Display Configuration
* Conceptual Public Service
* Contact Point
* Cost
* Evidence
* Financial Advantage
* Legal Resource
* Location
* Output
* Public Organization
* Public Service
* Requirement
* Rule
* Tombstone
* Website

## Import subsidy production data

After exporting is finished, the resulting turtle files for each type are stored inside the local `tmp/` folder of the `sparql-export-script` project. We will be using the `iSQL-v` interface in order to quickly and robustly import the data. Copy the turtle files into any folder and add the following to your `docker-compose.override.yml` file:

```
virtuoso:
  volumes:
    - ./data/db:/data
    - ./config/virtuoso/virtuoso-production.ini:/data/virtuoso.ini
    - ./config/virtuoso/:/opt/virtuoso-scripts
    - <location/to/turtle/files>:/tmp/subsidy-production-ttl-files
```

Add the `import-subsidy-production-data.sh` script to the volume mounts of `virtuoso` as well:

```
virtuoso:
  volumes:
    - ./data/db:/data
    - ./config/virtuoso/virtuoso-production.ini:/data/virtuoso.ini
    - ./config/virtuoso/:/opt/virtuoso-scripts
    - <location/to/turtle/files>:/tmp/subsidy-production-ttl-files
    - <location/to/import-subsidy-production-data.sh>:/tmp/import-subsidy-production-data.sh
```

Before running migrations in `app-subsidy-loket`, make sure to edit the parameters described in the [Note on Virtuoso settings](#note-on-virtuoso-settings) section. Run `docker compose up -d virtuoso` and wait for `virtuoso` to start up (by seeing `Server online at 1111 (pid 1)` in the logs). Enter the `virtuoso` container (`docker compose exec virtuoso bash`) and `cd /tmp`; you will find the script (`import-subsidy-production-data.sh`) and a folder containing the subsidy production turtle files.

Running the script (`./import-subsidy-production-data.sh`) will quickly load all triples into the database.

Once all turtle files have been imported, the following `INSERT` queries can be performed to place triples back to their original graphs:

```
PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>

INSERT {
  GRAPH ?g {
   ?s ?p ?o .
  }
}
WHERE {
  VALUES ?h {
    <http://mu.semte.ch/graphs/temp/ConceptualPublicService>
    <http://mu.semte.ch/graphs/temp/PublicService>
    <http://mu.semte.ch/graphs/temp/Tombstone>
    <http://mu.semte.ch/graphs/temp/PublicOrganisation>
    <http://mu.semte.ch/graphs/temp/Requirement>
    <http://mu.semte.ch/graphs/temp/Evidence>
    <http://mu.semte.ch/graphs/temp/Rule>
    <http://mu.semte.ch/graphs/temp/Cost>
    <http://mu.semte.ch/graphs/temp/Output>
    <http://mu.semte.ch/graphs/temp/FinancialAdvantage>
    <http://mu.semte.ch/graphs/temp/LegalResource>
    <http://mu.semte.ch/graphs/temp/ContactPoint>
    <http://mu.semte.ch/graphs/temp/Location>
    <http://mu.semte.ch/graphs/temp/Website>
    <http://mu.semte.ch/graphs/temp/Address>
  }

  GRAPH ?h {
    ?s a ?type ;
      ?p ?o ;
      ext:wasInGraph ?g .
  }
}
```

The above query moves all types except `ConceptDisplayConfiguration`, which is handled by the query below.

```
PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>

INSERT {
  GRAPH ?g {
   ?s ?p ?o .
   ?target ?targetP ?s .
  }
}
WHERE {
  VALUES ?h {
    <http://mu.semte.ch/graphs/temp/ConceptDisplayConfiguration>
  }

  GRAPH ?h {
    ?s a ?type ;
      ?p ?o ;
      ext:wasInGraph ?g .
    
    ?target ?targetP ?s .
  }
}
```

At this stage, all triples have been moved, and are situated in their correct graphs. One thing to check is whether there are any concept snapshots marked as `Delete`; these can be found throught the following query:

```
PREFIX lpdcExt: <https://productencatalogus.data.vlaanderen.be/ns/ipdc-lpdc#>
PREFIX dct:     <http://purl.org/dc/terms/>
PREFIX mu:      <http://mu.semte.ch/vocabularies/core/>

SELECT * WHERE {
  GRAPH <http://mu.semte.ch/graphs/lpdc/ldes-data> {
    ?snapshot a lpdcExt:ConceptualPublicService ;
      dct:isVersionOf ?concept ;
      lpdcExt:snapshotType ?snapshotType .
    
    FILTER(?snapshotType = <https://productencatalogus.data.vlaanderen.be/id/concept/SnapshotType/Delete>)
  }

  GRAPH <http://mu.semte.ch/graphs/public> {
    ?concept a lpdcExt:ConceptualPublicService ;
      mu:uuid ?id .
  }
}
```

At the moment, the total number of concepts between our and IPDC's side is not matching up; further information can be found in [this ticket](https://binnenland.atlassian.net/browse/LPDC-644).

Once everything is set up, we can delete all data inside the temporary graphs:

```
DELETE {
  GRAPH ?g {
    ?s ?p ?o .
  }
}
WHERE {
  VALUES ?g {
    <http://mu.semte.ch/graphs/temp/ConceptualPublicService>
    <http://mu.semte.ch/graphs/temp/PublicService>
    <http://mu.semte.ch/graphs/temp/Tombstone>
    <http://mu.semte.ch/graphs/temp/PublicOrganisation>
    <http://mu.semte.ch/graphs/temp/Requirement>
    <http://mu.semte.ch/graphs/temp/Evidence>
    <http://mu.semte.ch/graphs/temp/Rule>
    <http://mu.semte.ch/graphs/temp/Cost>
    <http://mu.semte.ch/graphs/temp/Output>
    <http://mu.semte.ch/graphs/temp/FinancialAdvantage>
    <http://mu.semte.ch/graphs/temp/LegalResource>
    <http://mu.semte.ch/graphs/temp/ContactPoint>
    <http://mu.semte.ch/graphs/temp/Location>
    <http://mu.semte.ch/graphs/temp/Website>
    <http://mu.semte.ch/graphs/temp/Address>
    <http://mu.semte.ch/graphs/temp/ConceptDisplayConfiguration>
  }
  
  GRAPH ?g {
    ?s ?p ?o .
  }
}
```

In addition, delete all instances of `ext:wasInGraph`, which is the predicate used to map the types back to their correct graphs:

```
PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>

DELETE {
  GRAPH ?g {
    ?s ext:wasInGraph ?graph .
  }
}
WHERE {
  GRAPH ?g {
    ?s ext:wasInGraph ?graph .
  }
}
```

Once the setup queries have run, execute a manual database checkpoint as such:
* `docker compose exec virtuoso isql-v`
* You are now inside the virtuoso iSQL interface.
* Run `exec('checkpoint');`
* Press `Ctrl+D` or type `exit` in the command-line interface in order to exit.

Backing up the newly imported data is also a good way to better our safety net:
* `docker compose exec -i virtuoso_container mkdir -p backups`
* `docker exec -i virtuoso_container isql-v`
* You are now inside the virtuoso iSQL interface.
* `exec('checkpoint');`
* `backup_context_clear();`
* `backup_online('backup_',30000,0,vector('backups'));`
* `exit;`
* You should see `.bp` files inside `data/db/backups`.

After performing the steps above, comment out the `virtuoso` volume mounts from `docker-compose.override.yml` and restore the values inside `config/virtuoso/virtuoso-production.ini` back to their original values (back to 1 million from 10 million).

## Sanity Checks

Once the import is finished, we need to perform some sanity checks to make sure the number of triples for each subsidy type matches between Loket and the new subsidy production environment.

In order to streamline these checks, a script (`sanity_checks.sh`) has been made to automatically execute the `COUNT` queries inside `sanity_queries/` on two endpoints (one for Loket and another for subsidy-loket). The results are sent to `results/sanity_type_count_results.csv`, which contains the type being counted, the count of this type in Loket, its count in the new subsidy app, and whether they are equal (`type,loket_count,subsidy_count,equal`).

The type count checks are done on a global level, so we cannot see how they are divided, but they do give us confidence if the numbers match up. To further push that confidence level, we also perform a sanity check to count the number of instantiated public services per bestuurseenheid, for both Loket and subsidy-loket. In order to perform this check, execute `select_queries.sh` first in order to download a list of non-eredienst bestuurseenheden (located in `tmp_select_out/non_eredienst_bestuurseenheden.csv`). After performing the regular type count checks, `sanity_checks.sh` confirms the existence of the aforementioned csv file and runs queries to count the number of public services for distinct bestuurseenheden. The result of this is piped into `results/sanity_public_services_count_per_bestuurseenheid_results.csv`, in a similar fashion to `results/sanity_type_count_results.csv`.

The default endpoints are `http://localhost:8890` for subsidy-loket, and `http:localhost:8892` for Loket. These can be changed by passing the `--subsidy-sparql-endpoint` and `--loket-sparql-endpoint` flags respectively.

### In case of mismatch

At the moment, only the `Requirement` type is displaying mismatches after the import process. The reason is due to the `<http://mu.semte.ch/vocabularies/core/uuid>` predicate being copied to the `ldes-data` graph; it should only be present in the `public graph`. The query below deletes the excess triples:

```
PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>

DELETE {
  GRAPH <http://mu.semte.ch/graphs/lpdc/ldes-data> {
    ?s <http://mu.semte.ch/vocabularies/core/uuid> ?o .
  }
}
WHERE {
  VALUES ?type {
    <http://data.europa.eu/m8g/Requirement>
  }

  GRAPH <http://mu.semte.ch/graphs/lpdc/ldes-data> {
    ?s a ?type ;
      <http://mu.semte.ch/vocabularies/core/uuid> ?o .
  }
}
```

## Delete Data in Case of Success/Re-run

The process described above, as it stands, should work without issues; however, it is possible something goes wrong during the export/import process. We have to consider the possibility of both cases:

### Success

In this case, we want to delete all subsidy data from the dev, QA and production Loket environments. The `DELETE` queries inside `delete_queries/` will be executed by `delete_queries.sh`; the SPARQL endpoint is provided through `--sparql-endpoint` and is set to `http://localhost:8890` by default.

### Failure

Similar to the success state, subsidy data needs to be deleted from the subsidy prod instance in case of import or sanity check failure. The same `DELETE` queries inside `delete_queries\` need to be run through `delete_queries.sh`, and the SPARQL endpoint needs to be specified.
