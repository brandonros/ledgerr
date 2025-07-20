# ledgerr
Proof-of-concept double-entry bookkeeping system 

## How to use (Postgres + Postgres mode)

```shell
export DATABASE_URL="psql://..."
./scripts/migrate.sh
./scripts/run-postgrest.sh # launch postgrest api at http://localhost:3000
./scripts/sanity-test.sh # preseed database
k6 run k6/write.js # performance test
```

## How to use (Tigerbeetle mode)

```shell
./scripts/run-tigerbeetle.sh # launch tigerbeetle cluster at http://localhost:5000
./scripts/run-dotnet.sh # launch tigerbeetle api at http://localhost:3000
./scripts/sanity-test.sh # preseed
k6 run k6/write.js # performance test
```
