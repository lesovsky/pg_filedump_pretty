#!/usr/bin/env bash

package="pg_filedump_pretty"
pkg_description="$package is a pg_filedump wrapper which simplifies data recovery process from Postgres data files"

show_usage() {
echo "$pkg_description

Usage:
  $package ACTION [OPTIONS] --pgdata=PATH

ACTIONS:
  list              List content of the Postgres data directory
  recover           Try to read datafiles and dump its content to CSV files

OPTIONS:                    There are no short-name options to avoid ambiguity
  --pgdata=PATH             PostgreSQL data directory with data files
  --database-oid=INTEGER    An OID of the database where tables for further  dump
  --recover-tables=REGEXP   list of tables for dump
  --output-directory=PATH   Destination directory for dumps

Examples:
List databases and tables in /var/lib/postgresql/11/main:
    $package list --pgdata=/var/lib/postgresql/11/main

Recover everything that could be recovered:
    $package recover --pgdata=/var/lib/postgresql/11/main

Recover tables from database with OID 12345:
    $package recover --database-oid=12345 --pgdata=/var/lib/postgresql/11/main

Recover tables with names contains 'customers' or 'transactions' from database with OID 12345
    $package recover --database-oid=12345 --recover-tables='customers|transactions' --pgdata=/var/lib/postgresql/11/main

Recover tables with names contains 'customers' or 'transactions' from database with OID 12345, save dump into /mnt/recovery
    $package recover --database-oid=12345 --recover-tables='customers|transactions' --output-directory=/mnt/recovery --pgdata=/var/lib/postgresql/11/main"
}

show_list_usage() {
echo "$pkg_description

LIST action usage:
  $package list --pgdata=PATH

OPTIONS:                    There are no short-name options to avoid ambiguity
  --pgdata=PATH             PostgreSQL data directory with data files

Examples:
List databases and tables in /var/lib/postgresql/11/main:
    $package list --pgdata=/var/lib/postgresql/11/main"
}

show_recover_usage() {
echo "$pkg_description

RECOVERY action usage:
  $package recover [OPTIONS] --pgdata=PATH

OPTIONS:                    There are no short-name options to avoid ambiguity
  --pgdata=PATH             PostgreSQL data directory with data files
  --database-oid=INTEGER    An OID of the database where tables for further  dump
  --recover-tables=REGEXP   list of tables for dump
  --dump-dead=BOOL          Dump dead tuples (this flag manages '-o' pg_filedump option (default: false)
  --output-directory=PATH   Destination directory for dumps

Examples:
Recover everything that could be recovered:
    $package recover --pgdata=/var/lib/postgresql/11/main

Recover tables from database with OID 12345:
    $package recover --database-oid=12345 --pgdata=/var/lib/postgresql/11/main

Recover tables with names contains 'customers' or 'transactions' from database with OID 12345
    $package recover --database-oid=12345 --recover-tables='customers|transactions' --pgdata=/var/lib/postgresql/11/main

Recover tables with names contains 'customers' or 'transactions' from database with OID 12345, save dump into /mnt/recovery
    $package recover --database-oid=12345 --recover-tables='customers|transactions' --output-directory=/mnt/recovery --pgdata=/var/lib/postgresql/11/main"
}

# Parse input arguments
PF_PRETTY_ACTION=""
PF_PRETTY_PGDATA=""
PF_PRETTY_TABLES_PATTERN=""
PF_PRETTY_DATABASE_OID=""

case "$1" in
    "list" )
        PF_PRETTY_ACTION=LIST
        shift
    ;;
    "recover" )
        PF_PRETTY_ACTION=RECOVER
        shift
    ;;
    * )
        echo "$package: error: action is not specified"
        show_usage
        exit 0
    ;;
esac

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            case "$PF_PRETTY_ACTION" in
            "LIST" )
                echo "$package - wrapper on pg_filedump for PostgreSQL data recovery"
                show_list_usage
            ;;
            "RECOVER" )
                echo "$package - wrapper on pg_filedump for PostgreSQL data recovery"
                show_recover_usage
            ;;
            * )
                echo "$package - wrapper on pg_filedump for PostgreSQL data recovery"
                show_usage
            ;;
            esac
            exit 0
        ;;
        # handle tables parameter
        --recover-tables=*)
            export PF_PRETTY_TABLES_PATTERN=$(echo $1 | sed -e 's/^[^=]*=//g')
            shift
        ;;
        # handle datadir parameter
        --pgdata=*)
            export PF_PRETTY_PGDATA=$(echo $1 | sed -e 's/^[^=]*=//g')
            shift
        ;;
        # handle output directory
        --output-directory=*)
            export PF_PRETTY_OUTPUT_DIRECTORY=$(echo $1 | sed -e 's/^[^=]*=//g')
            shift
        ;;
        # handle database oid to recover tables from
        --database-oid=*)
            export PF_PRETTY_DATABASE_OID=$(echo $1 | sed -e 's/^[^=]*=//g')
            shift
        ;;
        # skip garbage
        *)
            echo "$package: warning: extra command-line argument "$1" ignored"
            shift
        ;;
        esac
done

# Perform sanity checks
PG_FILEDUMP=$(which pg_filedump 2>/dev/null)
[[ -n $PG_FILEDUMP ]] && export PG_FILEDUMP || { echo "$package: error: pg_filedump not found"; exit 1; }

[[ ! -d $PF_PRETTY_PGDATA ]] && { echo "$package: error: pgdata not found"; exit 1; }

# TODO: check existence of postmaster.pid and its process -- exit if found or not forced to continue -- dissalow to run on running postgres.

[[ -z $PF_PRETTY_OUTPUT_DIRECTORY ]] && {
    echo "$package: log: output directory not specified, using current working directory"
    PF_PRETTY_OUTPUT_DIRECTORY=$(pwd)
}

[[ ! -d $PF_PRETTY_OUTPUT_DIRECTORY ]] && {
    echo "$package: log: output directory not exist, creating it"
    mkdir -p $PF_PRETTY_OUTPUT_DIRECTORY
}

#
# Load constants and variables
#

# Version of the PostgreSQL PGDATA
#PG_VERSION=$(cat ${PF_PRETTY_PGDATA}/base/1/PG_VERSION)

# OIDs of the databases found in PGDATA
DB_OIDS=$(ls ${PF_PRETTY_PGDATA}/base |grep -E '[0-9]+')

# System OIDs of Postgres catalog relations
PG11_PG_TYPE_OID=1247       # pg_type
PG11_PG_ATTRIBUTE_OID=1249  # pg_attribute
PG11_PG_CLASS_OID=1259      # pg_class

# List of relations' columns required during list or restore
# In most of cases we interested here in just first and last columns, but have to specify all between them.
# This list is passed to pg_filedump with -D option
PG11_PG_CLASS_COLS="name,oid,oid,oid,oid,oid,oid,oid,int,real,int,oid,bool,bool,char,char,~"
PG11_PG_ATTRIBUTE_COLS="oid,name,oid,int,smallint,~"

# Run user defined action

list_action() {
    for oid in ${DB_OIDS}; do
        echo "List tables in database with oid: $oid"
        ${PG_FILEDUMP} -o -D ${PG11_PG_CLASS_COLS} ${PF_PRETTY_PGDATA}/base/$oid/${PG11_PG_CLASS_OID} \
        |grep -E '^COPY' \
        |grep -vE 'pg_|sql_' \
        |awk -v relkind="r" '$17 == relkind { printf "  %s\t(oid: %d,\ttuples: %d,\tsize: %d)\n", $2, $8, $11, $10 * 8192}' \
        |sort -u
    done
}

recover_action() {
    for dboid in ${DB_OIDS}; do
        # skip database if user specified oid and current oid is not equal to requested
        [[ $PF_PRETTY_DATABASE_OID -ne "" && $dboid -ne $PF_PRETTY_DATABASE_OID ]] && continue

        echo "Recover tables in database with oid: $dboid"

        # generate list of tables
        declare -A tablesMap

        while read relname reloid; do
            if [[ -z $relname ]]; then
                continue        # skip empty (for example "empty" databases)
            fi
            tablesMap[$relname]=$reloid;
        done <<< $(${PG_FILEDUMP} -o -D ${PG11_PG_CLASS_COLS} ${PF_PRETTY_PGDATA}/base/$dboid/${PG11_PG_CLASS_OID} \
        |grep -E '^COPY' \
        |grep -vE 'pg_|sql_' \
        |awk -v relkind="r" '$17 == relkind { printf "%s %s\n", $2, $8}' \
        |sort -u)

    #    echo "DEBUG: being print map"
    #    for t in "${!tablesMap[@]}"; do echo "$t - ${tablesMap[$t]}"; done
    #    echo "DEBUG: end print map"

        # go over tables map and process every table
        for key in "${!tablesMap[@]}"; do
            failed=0
            tableName=$key
            tableOid=${tablesMap[$key]}

            # if user specified particular tables for recovery, check name before processing
            if [[ -n ${PF_PRETTY_TABLES_PATTERN} ]]; then
                if [[ $(echo $tableName |grep -c -E ${PF_PRETTY_TABLES_PATTERN}) -eq 0 ]]; then
                    continue
                fi
            fi

            # echo "DEBUG: table: $key, oid: ${tablesMap[$key]}";
            echo "LOG: starting to process table $tableName"

            # get colname and its oids
            coloidList=$($PG_FILEDUMP -o -D ${PG11_PG_ATTRIBUTE_COLS} ${PF_PRETTY_PGDATA}/base/$dboid/${PG11_PG_ATTRIBUTE_OID} \
            |grep $tableOid \
            |grep -vE 'ctid|xmin|cmin|xmax|cmax|tableoid' \
            |awk '{print $4}' \
            |xargs)

            #echo "DEBUG: coloidList: $coloidList"

            coltypeList=""
            for coloid in $coloidList; do
                coltype=""
                coltype=$($PG_FILEDUMP -o -i -D name,~ ${PF_PRETTY_PGDATA}/base/$dboid/${PG11_PG_TYPE_OID} \
                |grep -A5 -w -E "OID: $coloid" \
                |grep -E '^COPY:' \
                |cut -d" " -f2)
                if [[ -z $coltype ]]; then
                    echo "ERROR: failed to translate column's oid $coloid to type in table $tableName"
                    failed=1
                    break
                fi
                #echo "DEBUG: coltype: $coltype"
                coltypeList="$coltypeList $coltype"
            done

            if [[ $failed == 1 ]]; then
                echo "ERROR: can't process table $tableName, skip it"
                continue
            fi

            #echo "DEBUG: coltypeList: $coltypeList"

            # translate Postgres typenames to pg_filedump names
            coltypeList2=$(echo $coltypeList |sed \
                -e 's/int8/bigint/g' \
                -e 's/bpchar/charN/g' \
                -e 's/int4/int/g' \
                -e 's/int2/smallint/g' \
                -e 's/ /,/g')

            #echo "DEBUG: coltypeList2: $coltypeList2"

            # dump data
            #set -o xtrace
            ${PG_FILEDUMP} -o -t -D $coltypeList2 ${PF_PRETTY_PGDATA}/base/$dboid/$tableOid \
            |grep -E '^COPY:' \
            |sed -e 's/^COPY: //g' \
            > ${PF_PRETTY_OUTPUT_DIRECTORY}/recovered-$dboid-$tableName.csv
            #set +o xtrace
        done
    done

    echo "Check dumps in ${PF_PRETTY_OUTPUT_DIRECTORY}"
}

main() {
    case "$PF_PRETTY_ACTION" in
        "LIST")
            list_action
        ;;
        "RECOVER")
            recover_action
        ;;
        *)
            echo "$package: error: unknown action is specified"
        ;;
    esac

    exit 0
}

main