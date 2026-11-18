source "$(dirname "$0")/lib.sh"
{ ls api/src; cat api/src/*.js; grep -n "listen\|use(\|require\|import" api/src/*.js | head -40; } 2>&1 | saida
