#!/usr/bin/env python3
"""Build the report-v2 single-keccak (uint256 tokenId,address holder) Merkle tree.

Uses the installed Foundry `cast` for Ethereum Keccak; Python's sha3_256 is NOT
Ethereum Keccak. No RPC, private key or environment variable is read.
"""
import argparse
import csv
import json
import re
import subprocess


def keccak(data: bytes) -> bytes:
    output = subprocess.check_output(['cast', 'keccak', '0x' + data.hex()], text=True).strip()
    return bytes.fromhex(output.removeprefix('0x'))


def leaf(token_id: int, holder: str) -> bytes:
    if not 0 <= token_id < 2**256:
        raise ValueError('tokenId must fit uint256')
    if not re.fullmatch(r'0x[0-9a-fA-F]{40}', holder) or int(holder, 16) == 0:
        raise ValueError('holder must be a nonzero 20-byte Ethereum address')
    return keccak(token_id.to_bytes(32, 'big') + int(holder, 16).to_bytes(32, 'big'))


def build(entries):
    ids = [int(e['tokenId']) for e in entries]
    if not ids or len(set(ids)) != len(ids):
        raise ValueError('snapshot must contain entries with distinct tokenIds')
    leaves = [leaf(int(e['tokenId']), e['holder']) for e in entries]
    if len(set(leaves)) != len(leaves):
        raise ValueError('duplicate leaves')
    proofs = [[] for _ in leaves]
    level = sorted((h, [i]) for i, h in enumerate(leaves))
    while len(level) > 1:
        next_level = []
        for offset in range(0, len(level), 2):
            if offset + 1 == len(level):
                next_level.append(level[offset])
                continue
            left, li = level[offset]
            right, ri = level[offset+1]
            for index in li: proofs[index].append('0x'+right.hex())
            for index in ri: proofs[index].append('0x'+left.hex())
            next_level.append((keccak(min(left,right)+max(left,right)),li+ri))
        level = next_level
    root = level[0][0]
    claims = [dict(tokenId=int(e['tokenId']), holder=e['holder'], leaf='0x'+leaves[i].hex(), proof=proofs[i]) for i,e in enumerate(entries)]
    return '0x'+root.hex(), claims


def verify(claim, root):
    value=leaf(claim['tokenId'], claim['holder'])
    for sibling in claim['proof']:
        other=bytes.fromhex(sibling[2:]);value=keccak(min(value,other)+max(value,other))
    return '0x'+value.hex()==root

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot_csv',help='CSV with tokenId,holder columns; snapshot extraction is the operator responsibility')
    parser.add_argument('--snapshot-block',type=int,required=True)
    parser.add_argument('--collection',required=True,help='Verified Ethereum collection address')
    args=parser.parse_args()
    if args.snapshot_block<=0:parser.error('snapshot block must be positive')
    try:
        leaf(0,args.collection)  # validate address syntax without guessing a collection
        with open(args.snapshot_csv,newline='') as source:entries=list(csv.DictReader(source))
        root,claims=build(entries)
        assert all(verify(c,root) for c in claims)
    except (ValueError,KeyError) as e:parser.error(str(e))
    print(json.dumps({'chainId':1,'collection':args.collection,'snapshotBlock':args.snapshot_block,'root':root,'leafEncoding':'keccak256(abi.encode(uint256 tokenId,address holder))','claims':claims},indent=2))
