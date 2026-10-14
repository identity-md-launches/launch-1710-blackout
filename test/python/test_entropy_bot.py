import unittest,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from entropy_bot import Keeper,words
class FakeRPC:
    def __init__(self):self.block=100;self.target=102;self.captured=False;self.sent=[]
    def topic(self,kind):return kind
    def request(self,method,args):
        if method=='eth_blockNumber':return hex(self.block)
        return [{'topics':['pack',hex(1)],'removed':False}]
    def native_block(self):return self.block
    def call(self,address,data):
        return '0x'+''.join(format(x,'064x') for x in [1,self.target,1,0,0,0,0,int(self.captured),0])
    def send(self,address,receipt):
        self.sent.append(receipt)
        if self.block>self.target+256:self.target=self.block+2
        else:self.captured=True
class EntropyBotTest(unittest.TestCase):
    def test_captures_within_next_two_second_tick_and_never_pays_twice(self):
        rpc=FakeRPC();bot=Keeper(rpc,{'pack':'packs'},100)
        self.assertEqual(bot.tick(),[])
        rpc.block=102;self.assertEqual(bot.tick(),[])
        rpc.block=103;self.assertEqual(bot.tick(),[('pack',1,'capture')])
        rpc.block=104;self.assertEqual(bot.tick(),[]);self.assertEqual(rpc.sent,[1])
    def test_expiry_rearms_then_captures_without_full_inventory_dependency(self):
        rpc=FakeRPC();bot=Keeper(rpc,{'pack':'packs'},100);rpc.block=400
        self.assertEqual(bot.tick(),[('pack',1,'rearm')]);self.assertFalse(rpc.captured)
        rpc.block=402;self.assertEqual(bot.tick(),[])
        rpc.block=403;self.assertEqual(bot.tick(),[('pack',1,'capture')]);self.assertTrue(rpc.captured)
    def test_bad_abi_rejected(self):
        with self.assertRaises(ValueError):words('0x00')
