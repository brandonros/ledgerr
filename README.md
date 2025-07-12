# ledgerr
Proof-of-concept double-entry bookkeeping system 

## How to use

```shell
export DATABASE_URL="psql://..."
./scripts/migrate.sh
./scripts/run.sh # launch postgres api at http://localhost:3000
./scripts/sanity-test.sh # preseed database
./scripts/performance-test.sh
```
