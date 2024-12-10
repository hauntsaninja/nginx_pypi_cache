# pypi_nginx_cache

A PyPI cache using nginx.

## Usage

This serves as a caching mirror for PyPI. It's a simple stateless service and does not
support uploading packages / private indices. For this use case, I've found it to be
significantly faster and significantly more reliable than devpi.

To run it locally:
```bash
docker run -p 80:80 --rm $(docker build -q .)
```

To tell `pip` to connect to this instead of `pypi.org`, use:
```bash
pip install --index-url=http://localhost/simple mypy
```
or
```bash
export PIP_INDEX_URL=http://localhost/simple
pip install mypy
```

## Github container registry

To pull the latest version from the Github container registry:

```bash
docker pull ghcr.io/hauntsaninja/nginx_pypi_cache:latest
```

See https://github.com/hauntsaninja/nginx_pypi_cache/pkgs/container/nginx_pypi_cache

## Troubleshooting

It turns out it's surprisingly easy to mess something up and not actually end up proxying
requests. `tests/mitmtest.sh` should help confirm that we're hitting the cache when we expect to,
instead of hitting upstream PyPI.

The log messages are also pretty useful (check `nginx.conf` to see exactly what these
correspond to):
```
172.17.0.1 - localhost [13/Jan/2023:02:36:00 +0000] request_time=0.000 upstream_time=- cache_status=HIT 	200 "GET /simple/mypy/ HTTP/1.1" 78368
```
