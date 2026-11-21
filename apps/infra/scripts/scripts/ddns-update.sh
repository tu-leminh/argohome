#!/bin/sh
# One DDNS updater for every provider, chosen by $PROVIDER. The A record is
# set from the provider's own view of our WAN IPv4; the AAAA record is set to
# $IPV6 when it is non-empty. The token ($TOKEN) only ever travels inside a
# curl config read from stdin, so it never appears in argv, `ps` or the logs
# (hence no `set -x` here).
set -eu
: "${PROVIDER:?}" "${TOKEN:?}"
DOMAIN=${DOMAIN:-}
IPV6=${IPV6:-}
failed=0

# call METHOD URL EXPECT: run the request; EXPECT is a substring the response
# body must contain ("" = any 2xx is success).
call() {
  body=$(printf 'url = "%s"\nrequest = "%s"\n' "$2" "$1" |
    curl -sS --fail --retry 3 --max-time 30 -K -) || { echo "$PROVIDER: $1 request failed" >&2; failed=1; return 0; }
  case "$body" in
    *"$3"*) echo "$PROVIDER: ok" ;;
    *) echo "$PROVIDER: unexpected response" >&2; failed=1 ;;
  esac
}

case "$PROVIDER" in
  duckdns)
    # One call sets both; an empty ip= means "use the caller's IPv4".
    call GET "https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=${IPV6:+&ipv6=$IPV6}" OK ;;
  freemyip)
    call GET "https://freemyip.com/update?token=$TOKEN&domain=$DOMAIN" ""
    [ -z "$IPV6" ] || call GET "https://freemyip.com/update?token=$TOKEN&domain=$DOMAIN&myip=$IPV6" "" ;;
  myaddr)
    call POST "https://myaddr.tools/update?key=$TOKEN&ip=self" ""
    [ -z "$IPV6" ] || call POST "https://myaddr.tools/update?key=$TOKEN&ip=$IPV6" "" ;;
  *)
    echo "unknown provider: $PROVIDER" >&2; exit 2 ;;
esac

exit $failed
