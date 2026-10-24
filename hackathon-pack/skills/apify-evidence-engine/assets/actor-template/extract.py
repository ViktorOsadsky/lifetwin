"""Extract offer evidence from caller-supplied HTML snapshots; performs no fetching."""
import hashlib
import json
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser
from urllib.parse import urlparse


class JsonLd(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active, self.buffer, self.blocks = False, [], []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == 'script' and dict(attrs).get('type', '').lower() == 'application/ld+json':
            self.active, self.buffer = True, []

    def handle_data(self, data):
        if self.active:
            self.buffer.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == 'script' and self.active:
            self.blocks.append(''.join(self.buffer))
            self.active = False


def nodes(value):
    if isinstance(value, list):
        for item in value:
            yield from nodes(item)
    elif isinstance(value, dict):
        yield value
        if '@graph' in value:
            yield from nodes(value['@graph'])


def extract(snapshot):
    url, html = snapshot['sourceUrl'], snapshot['html']
    parsed = urlparse(url)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Public HTTP(S) source URL without embedded credentials required')
    if not isinstance(html, str) or len(html) > 2_000_000:
        raise ValueError('Snapshot HTML must be a string no larger than two million characters')
    parser = JsonLd()
    parser.feed(html)
    rows, warnings = [], []
    for block in parser.blocks:
        try:
            document = json.loads(block)
        except json.JSONDecodeError:
            warnings.append('malformed-jsonld')
            continue
        for product in nodes(document):
            kinds = product.get('@type', [])
            if 'Product' not in (kinds if isinstance(kinds, list) else [kinds]):
                continue
            offers = product.get('offers', [])
            if isinstance(offers, dict):
                offers = [offers]
            if not isinstance(offers, list) or not offers:
                warnings.append('product-without-offer')
                continue
            for offer in offers:
                if not isinstance(offer, dict) or offer.get('@type', 'Offer') != 'Offer':
                    warnings.append('unsupported-offer-shape')
                    continue
                try:
                    raw = offer['price']
                    if isinstance(raw, bool):
                        raise ValueError('boolean price')
                    price = Decimal(str(raw))
                    if not price.is_finite() or price < 0:
                        raise ValueError('invalid price')
                    currency = offer['priceCurrency']
                    if not isinstance(currency, str) or len(currency) != 3 or not currency.isalpha() or not currency.isupper():
                        raise ValueError('invalid currency')
                except (KeyError, InvalidOperation, ValueError, TypeError):
                    warnings.append('missing-or-invalid-price-currency')
                    continue
                rows.append({'name': product.get('name'), 'sku': product.get('sku'), 'price': str(price),
                    'currency': currency, 'availability': offer.get('availability'), 'sourceUrl': url,
                    'observedAt': snapshot['observedAt'], 'evidenceType': 'caller-supplied-jsonld-snapshot',
                    'contentSha256': hashlib.sha256(html.encode()).hexdigest()})
    return rows, warnings


def self_test():
    import unittest
    class Tests(unittest.TestCase):
        def page(self, data):
            return {'sourceUrl': 'https://example.com/item', 'observedAt': '2026-10-23T00:00:00Z',
                    'html': '<script type="application/ld+json">' + json.dumps(data) + '</script>'}

        def test_graph_and_decimal(self):
            rows, warnings = extract(self.page({'@graph': [{'@type': 'Product', 'name': 'Fixture',
                'offers': {'@type': 'Offer', 'price': '12.30', 'priceCurrency': 'USD'}}]}))
            self.assertEqual(rows[0]['price'], '12.30')
            self.assertIsNone(rows[0]['availability'])
            self.assertFalse(warnings)

        def test_missing_price_is_rejected(self):
            rows, warnings = extract(self.page({'@type': 'Product', 'offers': {'priceCurrency': 'USD'}}))
            self.assertEqual(rows, [])
            self.assertIn('missing-or-invalid-price-currency', warnings)

        def test_aggregate_not_guessed_as_checkout_price(self):
            rows, warnings = extract(self.page({'@type': 'Product', 'offers': {'@type': 'AggregateOffer',
                'lowPrice': '2', 'highPrice': '20', 'priceCurrency': 'USD'}}))
            self.assertFalse(rows)
            self.assertIn('unsupported-offer-shape', warnings)

        def test_malformed_block_is_observable(self):
            page = self.page({})
            page['html'] = '<script type="application/ld+json">invalid</script>'
            self.assertEqual(extract(page), ([], ['malformed-jsonld']))

        def test_two_offers_and_nonfinite_price(self):
            page = self.page({'@type': ['Product'], 'offers': [
                {'price': '1', 'priceCurrency': 'USD'}, {'price': 'NaN', 'priceCurrency': 'USD'}]})
            rows, warnings = extract(page)
            self.assertEqual(len(rows), 1)
            self.assertEqual(len(warnings), 1)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Tests)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)


if __name__ == '__main__':
    import sys
    if sys.argv[1:] == ['--self-test']:
        self_test()
    else:
        data = json.load(sys.stdin)
        print(json.dumps({'rows': extract(data)[0], 'warnings': extract(data)[1]}, indent=2))
