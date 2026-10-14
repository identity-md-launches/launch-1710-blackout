import unittest
from tools.starter_merkle import build, verify, leaf

class MerkleTests(unittest.TestCase):
    def test_solidity_abi_single_leaf_and_odd_tree(self):
        entries=[{'tokenId':i,'holder':'0x'+format(i+123,'040x')} for i in range(3)]
        root,claims=build(entries)
        self.assertTrue(all(verify(c,root) for c in claims))
        changed=dict(claims[1],holder='0x'+format(456,'040x'))
        self.assertFalse(verify(changed,root))
        one,single=build(entries[:1])
        self.assertEqual(one,'0x'+leaf(0,entries[0]['holder']).hex())
        self.assertEqual(single[0]['proof'],[])
    def test_reject_missing_or_duplicate_snapshot(self):
        with self.assertRaises(ValueError):build([])
        entry={'tokenId':17,'holder':'0x'+format(123,'040x')}
        with self.assertRaises(ValueError):build([entry,entry])
        with self.assertRaises(ValueError):leaf(17,'0x'+'0'*40)
if __name__=='__main__':unittest.main()
