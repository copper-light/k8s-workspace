kubectl replace --raw "/api/v1/namespaces/$1/finalize" -f $1.json
