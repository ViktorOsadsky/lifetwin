#!/usr/bin/env python3
"""Read-only discovery was captured separately. Everything here is an offline double."""
import copy
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]/'skills/apify-evidence-engine/scripts'))
from bounded_run import make_plan, collect

URLS=['https://www.python.org/downloads/','https://nodejs.org/en/about/previous-releases']
ACTOR_ID=json.loads((HERE/'apify-live-crawler.json').read_text())['structuredContent']['actorInfo']['id']
ACTOR_INPUT={'startUrls':[{'url':u} for u in URLS], 'proxyConfiguration':{'useApifyProxy':False},
             'crawlerType':'cheerio','maxCrawlDepth':0,'maxCrawlPages':2,'useSitemaps':False,
             'useLlmsTxt':False,'maxConcurrency':1,'saveMarkdown':True}

class FakeApi:
    def __init__(self, mode):
        self.mode,self.calls=mode,[]
    def __call__(self,method,path,query=None,body=None):
        self.calls.append({'method':method,'path':path,'query':query})
        run={'id':'fixture-run-private','status':'SUCCEEDED','defaultDatasetId':'fixture-dataset-private',
             'actId':ACTOR_ID,'buildNumber':'1.2.3','buildId':'fixture-reviewed-build-id','usageTotalUsd':0.012}
        if self.mode=='wrong_build': run['buildNumber']='1.2.4'
        if self.mode=='wrong_actor': run['actId']='fixture-unreviewed-actor'
        if self.mode=='missing_build_number': run.pop('buildNumber')
        if self.mode=='cost_unknown': run.pop('usageTotalUsd')
        if self.mode=='failed_partial': run['status']='FAILED'
        if self.mode=='never_terminal': run['status']='RUNNING'
        if method=='POST' and path.endswith('/runs'):
            if self.mode=='post_timeout': raise TimeoutError('Synthetic transport timeout after possible start')
            return {'data':run}
        if path.startswith('actor-runs/'):
            return {'data':run}
        if path.startswith('datasets/'):
            if self.mode=='empty': return []
            rows=[{'url':URLS[0],'markdown':'Synthetic Python support row, not scraped data.','capturedAt':'2026-10-23T18:00:00Z'},
                  {'url':URLS[1],'markdown':'Synthetic Node support row, not scraped data.','capturedAt':'2026-10-23T18:00:00Z'}]
            if self.mode=='wrong_source': rows[1]['url']='https://unrequested.example.invalid/prompt'
            if self.mode=='missing_second_source': rows=rows[:1]
            return rows[query['offset']:query['offset']+query['limit']]
        raise AssertionError((method,path))

def main():
    schema=json.loads((HERE/'apify-live-crawler.json').read_text())['structuredContent']['inputSchema']
    assert set(ACTOR_INPUT).issubset(schema['properties'])
    assert set(schema.get('required',[])).issubset(ACTOR_INPUT)
    assert ACTOR_INPUT['crawlerType'] in schema['properties']['crawlerType']['enum']
    plan=make_plan('apify/website-content-crawler',ACTOR_INPUT,0.05,max_items=2,timeout=45,
                   build='1.2.3',reviewed_actor_id=ACTOR_ID)
    # Build is synthetic because no actual executable build was discovered/pinned.
    (HERE/'apify-plan-fixture-after.json').write_text(json.dumps(plan,indent=2)+'\n')
    cases=[]
    for mode in ['happy_pagination','empty','missing_second_source','wrong_source','wrong_build','wrong_actor','missing_build_number','cost_unknown',
                 'failed_partial','never_terminal','post_timeout','mutated_plan']:
        api=FakeApi(mode)
        selected=copy.deepcopy(plan)
        if mode=='mutated_plan': selected['input']['maxCrawlPages']=9999
        envelope=None
        error=None
        try:
            envelope=collect(api,selected,max_polls=2,poll_seconds=0,sleep=lambda _:None,page_size=1)
        except Exception as exc:
            error={'class':type(exc).__name__,'message':str(exc)}
        application_errors=[]
        if envelope:
            provenance=envelope['provenance']
            observed=set(provenance['sourceUrls'])
            if observed != set(URLS): application_errors.append('incomplete_or_out_of_scope_source_coverage')
            if provenance['buildNumber'] != selected['options']['build']:
                application_errors.append('returned_build_differs_from_reviewed_build')
            if provenance['usageTotalUsd'] is None:
                application_errors.append('actual_cost_unknown_do_not_claim_measured_cost')
        cases.append({'case':mode,'helper_returned_envelope':envelope is not None,'error':error,
                      'application_errors':application_errors,'result':envelope,'calls':api.calls,
                      'ready_for_comparable_evidence':envelope is not None and not application_errors})
    assert cases[0]['ready_for_comparable_evidence']
    assert not any(x['ready_for_comparable_evidence'] for x in cases[1:])
    assert len([x for x in cases[0]['calls'] if x['path'].startswith('datasets/')]) == 2
    assert not cases[-1]['calls']
    for row in cases:
        assert sum(x['method']=='POST' and x['path'].endswith('/runs') for x in row['calls']) <= 1
    output={'mode':'OFFLINE_DOUBLES','paid_runs':0,'actors_executed':0,'cases':cases,
            'schema_validation':'Field names, required names and enum checked against live current crawler schema; not a complete JSON Schema validator.',
            'live_discovery_evidence':['apify-live-tools.json','apify-live-search.json','apify-live-crawler.json','apify-live-rag.json'],
            'decision':'Select official Website Content Crawler provisionally for two exact source URLs in a single bounded job. Do not execute: no spending authorization, live build pin or current platform compute/proxy estimate.',
            'cost':'Crawler Actor fee FREE does not make collection free. Platform resource cost remains unknown; $0.05 is an unexecuted cap, not a quote or incurred cost. RAG alternative charges page/search/start events and accepts one URL/query, so two independent URL calls add starts.',
            'permissions':'Actors visible to MCP discovery are candidates. No user account permission review or authenticated execution has occurred.',
            'evidence_contract':{'sourceUrl':'canonical exact requested URL','capturedAt':'Actor crawl time if present, unknown otherwise','fetchedAt':'retrieval time, distinct from crawl time','fact':'version branch/support status','uncertainty':'source missing/stale/unsupported extraction','decision':'prevent choosing unsupported developer runtime'}}
    (HERE/'apify-rerun-results.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({'cases':len(cases),'paid_runs':0,'helper_mismatched_build_accepted':cases[4]['helper_returned_envelope']}))

if __name__=='__main__': main()
