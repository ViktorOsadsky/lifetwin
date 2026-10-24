"""Create an inert review catalog from supplied MCP tools/list or OpenAPI JSON."""
import json
import sys


def catalog(document):
    payload = document.get('result', document)
    if 'tools' in payload:
        return {'format': 'mcp', 'nextCursor': payload.get('nextCursor'), 'tools': [
            {'name': t['name'], 'description': t.get('description', ''),
             'inputSchema': t.get('inputSchema'), 'outputSchema': t.get('outputSchema'),
             'annotations': t.get('annotations', {}), 'execution_review': 'required'}
            for t in payload['tools']]}
    if 'openapi' not in document:
        raise ValueError('Expected MCP tools/list JSON or OpenAPI 3 JSON')
    operations = []
    for path, item in document.get('paths', {}).items():
        for method, op in item.items():
            if method.lower() not in {'get', 'post', 'put', 'patch', 'delete', 'head', 'options', 'trace'}:
                continue
            operations.append({'name': op.get('operationId'), 'method': method.upper(), 'path': path,
                               'parameters': item.get('parameters', []) + op.get('parameters', []),
                               'requestBody': op.get('requestBody'), 'responses': op.get('responses'),
                               'security': op.get('security', document.get('security', [])),
                               'servers': op.get('servers', item.get('servers', document.get('servers', []))),
                               'execution_review': 'required'})
    return {'format': 'openapi', 'version': document.get('info', {}).get('version'),
            'securitySchemes': document.get('components', {}).get('securitySchemes', {}),
            'components': document.get('components', {}), 'operations': operations}


if __name__ == '__main__':
    try:
        print(json.dumps(catalog(json.load(open(sys.argv[1]))), indent=2))
    except (ValueError, KeyError, IndexError, OSError) as exc:
        sys.exit(str(exc))
