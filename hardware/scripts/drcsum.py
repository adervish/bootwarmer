import json,collections,sys
d=json.load(open(sys.argv[1]))
skip=('silk_overlap','silk_over_copper','silk_edge_clearance','lib_footprint_issues','lib_footprint_mismatch')
c=collections.Counter(v['type'] for v in d['violations'])
print(dict(c), '| unconnected:',len(d.get('unconnected_items',[])))
for v in d['violations']:
    if v['type'] in skip: continue
    print(' ',v['type'],'|',v['description'][:70],'|',' ; '.join(i['description'][:46]+' @(%.1f,%.1f)'%(i['pos']['x']-100,i['pos']['y']-80) for i in v['items']))
for v in d.get('unconnected_items',[]):
    print('  UNCONNECTED |',' ; '.join(i['description'][:46]+' @(%.1f,%.1f)'%(i['pos']['x']-100,i['pos']['y']-80) for i in v['items']))
