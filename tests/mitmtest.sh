#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 127

print_bold_red() {
  printf '\033[1;31m%s\033[0m\n' "$1"
}

set -x

if ! docker ps >/dev/null; then
  print_bold_red "test requires docker to be running"
  exit 1
fi

venv_dir=$(mktemp -d)
if ! python3 -c 'import sys; assert sys.version_info >= (3, 9)'; then
  print_bold_red "test requires Python 3.9 or newer"
  exit 1
fi
python3 -m venv "$venv_dir"

export PIP_DISABLE_PIP_VERSION_CHECK=1
"$venv_dir/bin/pip" install wheel >/dev/null
"$venv_dir/bin/pip" install --upgrade pip >/dev/null
"$venv_dir/bin/pip" install mitmproxy >/dev/null

docker_image=$(docker build -q ../)

# kill background jobs on exit
trap 'echo "cleaning up..."; jobs -p | xargs -r kill; sleep 1' SIGTERM EXIT

# run mitmdump on unprivileged port
MITM=12345
"$venv_dir/bin/mitmdump" -s pypi_intercept.py -p $MITM &

# run the pypi cache on port 80
docker run -p 80:80 --rm "$docker_image" &

# wait for everything to come up
sleep 5

printf '\n\n\n===== basic curl test =====\n\n\n\n'

# check a curl to pypi cache works
STATUS=$(curl -s --output /dev/null --write-out "%{http_code}" http://localhost/simple/)
if [ "$STATUS" -ne 200 ]; then
  print_bold_red "failed to issue request to pypi cache, got $STATUS"
  exit 1
fi
STATUS=$(curl -s --output /dev/null --write-out "%{http_code}" http://localhost/simple/boostedblob/)
if [ "$STATUS" -ne 200 ]; then
  print_bold_red "failed to issue request to pypi cache, got $STATUS"
  exit 1
fi
# check that the mypy response was not cached
if ! curl -s -I -X GET http://localhost/simple/mypy/ | grep -q 'X-Pypi-Cache: MISS'; then
  print_bold_red "mypy response was missing cache header (or unexpectedly cached)"
  exit 1
fi
# check that the mypy response did get cached
if ! curl -s -I -X GET http://localhost/simple/mypy/ | grep -q 'X-Pypi-Cache: HIT'; then
  print_bold_red "mypy response was not cached"
  exit 1
fi
# check a curl to pypi cache that should fail does fail
STATUS=$(curl -s --output /dev/null --write-out "%{http_code}" http://localhost/doesnotexist/)
if [ "$STATUS" -ne 404 ]; then
  print_bold_red "expected 404 from pypi cache, got $STATUS"
  exit 1
fi

printf '\n\n\n===== mitm pip test =====\n\n\n\n'

# check that mitmdump prevents pip installs from upstream pypi
REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca.pem ALL_PROXY=http://localhost:$MITM/ "$venv_dir/bin/pip" install --no-cache-dir --force-reinstall mypy
if [ $? -ne 1 ]; then
  print_bold_red "installing mypy from upstream unexpectedly succeeded (should be blocked by mitmdump)"
  exit 1
fi
# check that mitmdump prevents pip installs of numpy from pypi cache
REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca.pem ALL_PROXY=http://localhost:$MITM/ "$venv_dir/bin/pip" install --no-cache-dir --force-reinstall --index-url=http://localhost/simple numpy
if [ $? -ne 1 ]; then
  print_bold_red "installing numpy from pypi cache unexpectedly succeeded (should be blocked by mitmdump)"
  exit 1
fi
# but everything works for other packages if we use the pypi cache
REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca.pem ALL_PROXY=http://localhost:$MITM/ "$venv_dir/bin/pip" install --no-cache-dir --force-reinstall --index-url=http://localhost/simple mypy
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
  print_bold_red "failed to install mypy from pypi cache"
  exit 1
fi

# TODO: check that the pypi cache is actually getting cache hits, should be visible in the access log when we run the following
REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca.pem ALL_PROXY=http://localhost:$MITM/ "$venv_dir/bin/pip" install --no-cache-dir --force-reinstall --index-url=http://localhost/simple mypy

# check that installing mypy did not invalidate the cache (the requests use different Accept headers)
if ! curl -s -I -X GET http://localhost/simple/mypy/ | grep -q 'X-Pypi-Cache: HIT'; then
  print_bold_red "mypy response was not cached"
  exit 1
fi

printf '\033[1;32m%s\033[0m\n' "success!"
