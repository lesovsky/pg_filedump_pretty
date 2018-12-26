# pg_filedump_pretty
pg_filedump_pretty is a [pg_filedump](https://wiki.postgresql.org/wiki/Pg_filedump) wrapper which simplifies data recovery process from Postgres data files

## pg_filedump advantages
- dump tables content when Postgres is offline and unable to start
- dump live and dead tuples
- dump TOASTed values

## pg_filedump drawbacks
- can't list databases and tables - before dump you need to know the schema and exact data files 
- can't translate databases' oids to names - you can see numeric OIDs, but names are more useful
- can't automatically translates oids to tables and recover data - you neen to do some manual steps before starting recovery
- doesn't support numeric data type - yes, but it's not look impossibe, just need to write a patch to pg_filedump
- has it's own names for postgres data types (eg. `bool` instead of `boolean`), it's confusing sometimes.

## Why pg_filedump_pretty?
- wish to automate the manual work such as resolving oid to names, translating columns and their types, dump many tables, etc
- under the hood `pg_filedump_pretty` uses `pg_filedump` with `-t` and `-o` flags (dump TOASTed values and do not dump dead tuples). Original `pg_filedump` has additional paramaters that may be useful in some circumstances (see built-in help) 

## Why bash?
- need quick (and dirty) solution, have no time to make beautiful tool
- all that stuff could be implemented in original pg_filedump
- have no time to propose patches to original pg_filedump

## Disclaimer
**No warranties. At all. Use at your own risk.**

Neither `pg_filedump_pretty`, nor `pg_filedump` are not the silver bullets. There may be different reasons of data corruption and it is not possible to cover all cases. If `pg_filedump_pretty` or `pg_filedump` don't recover your data, it isn't their bug, it just you have a bad day.

## pg_filedump/pg_filedump_pretty installation
```
sudo apt-get update
sudo apt-get install git gcc make postgresql-server-dev-11
git clone git://git.postgresql.org/git/pg_filedump.git
cd pg_filedump
make
make install
cd ..
git clone https://github.com/lesovsky/pg_filedump_pretty
cd pg_filedump_pretty/
./pg_filedump_pretty.sh --help
```
See `pg_filedump_pretty` built-in help for examples.

## Good luck.