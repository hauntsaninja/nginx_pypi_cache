import sys
from mitmproxy import http


class ChangeHTTPCode:
    def response(self, flow: http.HTTPFlow) -> None:
        if not flow.response:
            raise ValueError("No response")
        if flow.response.status_code >= 400:
            print(
                f"[pypi_intercept] got error response: {flow.response.status_code}",
                flow.response.data,
                file=sys.stderr,
            )

        # prevent requests to upstream pypi
        if "pypi" in flow.request.pretty_url or "pythonhosted" in flow.request.pretty_url:
            flow.response.status_code = 400
        # prevent requests involving numpy
        if "numpy" in flow.request.pretty_url:
            flow.response.status_code = 400


addons = [ChangeHTTPCode()]
