#!/usr/bin/env python3
"""Offline v3.5 free-pack tree: <=500 unique wallets. Reads one wallet per line.
Output can be served as ui/allowlist.json after the swarm sets the matching root.
"""
import argparse,json
from pathlib import Path
from starter_merkle import build,verify,leaf

def free_tree(wallets):
    wallets=[w.strip() for w in wallets if w.strip()]
    if not 1<=len(wallets)<=500:raise ValueError('allowlist must have 1..500 wallets')
    if len(set(w.lower() for w in wallets))!=len(wallets):raise ValueError('duplicate wallet')
    entries=[{'tokenId':i,'holder':w} for i,w in enumerate(wallets)]
    root,claims=build(entries)
    assert all(verify(c,root) for c in claims)
    return {'root':root,'leafEncoding':'keccak256(abi.encode(uint256 index,address wallet))','claims':{c['holder'].lower():{'index':c['tokenId'],'proof':c['proof']} for c in claims}}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('wallets',type=Path);a=p.parse_args()
    try:print(json.dumps(free_tree(a.wallets.read_text().splitlines()),indent=2))
    except ValueError as e:p.error(str(e))
