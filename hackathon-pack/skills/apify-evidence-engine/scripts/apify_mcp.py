#!/usr/bin/env python3
"""Small no-account Apify discovery client. Never runs Actors or reads private data."""
import argparse
import json
import urllib.request

TOOLS = ('search-actors', 'fetch-actor-details', 'search-apify-docs', 'fetch-apify-docs')
URL = 'https://mcp.apify.com?tools=' + ','.join(TOOLS)


def decode_rpc(raw, content_type):
    text = raw.decode('utf-8')
    if 'text/event-stream' in content_type:
        messages = []
        for event in text.replace('\r\n', '\n').split('\n\n'):
            data = '\n'.join(line[5:].lstrip() for line in event.splitlines() if line.startswith('data:'))
            if data:
                messages.append(json.loads(data))
        responses = [m for m in messages if 'id' in m]
        if not responses:
            raise ValueError('SSE response contained no JSON-RPC response')
        return responses[-1]
    return json.loads(text)


class DiscoveryClient:
    def __init__(self, opener=urllib.request.urlopen):
        self.opener, self.session, self.sequence = opener, None, 0
        self.protocol = '2025-03-26'

    def rpc(self, method, params=None, notification=False):
        self.sequence += 1
        payload = {'jsonrpc': '2.0', 'method': method, 'params': params or {}}
        if not notification:
            payload['id'] = self.sequence
        headers = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'}
        if self.session:
            headers['Mcp-Session-Id'] = self.session
        if method != 'initialize':
            headers['MCP-Protocol-Version'] = self.protocol
        request = urllib.request.Request(URL, json.dumps(payload).encode(), headers, method='POST')
        with self.opener(request, timeout=30) as response:
            self.session = response.headers.get('Mcp-Session-Id', self.session)
            raw = response.read()
            if notification and not raw:
                return None
            data = decode_rpc(raw, response.headers.get('Content-Type', 'application/json'))
        if data.get('id') != payload.get('id'):
            raise ValueError('JSON-RPC response ID mismatch')
        if 'error' in data:
            raise RuntimeError('MCP protocol error: ' + json.dumps(data['error']))
        return data['result']

    def connect(self):
        info = self.rpc('initialize', {'protocolVersion': self.protocol, 'capabilities': {},
            'clientInfo': {'name': 'hackathon-apify-discovery', 'version': '1.0.0'}})
        self.protocol = info['protocolVersion']
        self.rpc('notifications/initialized', notification=True)
        return info

    def tools(self):
        result, cursor = [], None
        while True:
            page = self.rpc('tools/list', {'cursor': cursor} if cursor else {})
            result.extend(page['tools'])
            cursor = page.get('nextCursor')
            if not cursor:
                return result

    def call(self, name, arguments):
        if name not in TOOLS:
            raise ValueError('Only no-account discovery and documentation tools are allowed')
        result = self.rpc('tools/call', {'name': name, 'arguments': arguments})
        if result.get('isError'):
            raise RuntimeError('Discovery tool error: ' + json.dumps(result))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool', choices=TOOLS)
    parser.add_argument('--arguments', default='{}', help='Exact JSON from discovered inputSchema')
    args = parser.parse_args()
    client = DiscoveryClient()
    info = client.connect()
    result = client.call(args.tool, json.loads(args.arguments)) if args.tool else {'server': info, 'tools': client.tools()}
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
