#!/usr/bin/python3
"""
Copyright 2022 Wormhole Project Contributors

Licensed under the Apache License, Version 2.0 (the "License");

you may not use this file except in compliance with the License.

You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

"""
from typing import Tuple

from algosdk.v2client.algod import AlgodClient
from pyteal.ast import *
from pyteal.compiler import *
from pyteal.ir import *
from pyteal.types import *

from globals import *
from inlineasm import *
from local_blob import LocalBlob
from TmplSig import TmplSig

max_keys = 15
max_bytes_per_key = 127
bits_per_byte = 8

max_bytes = max_bytes_per_key * max_keys
max_bits = bits_per_byte * max_bytes

def fullyCompileContract(genTeal, client: AlgodClient, contract: Expr, name, devmode) -> bytes:
    if devmode:
        teal = compileTeal(contract, mode=Mode.Application, version=6, assembleConstants=True)
    else:
        teal = compileTeal(contract, mode=Mode.Application, version=6, assembleConstants=True, optimize=OptimizeOptions(scratch_slots=True))

    if genTeal:
        with open(name, "w") as f:
            print("Writing " + name)
            f.write(teal)
    else:
        with open(name, "r") as f:
            print("Reading " + name)
            teal = f.read()

    response = client.compile(teal)
    return response

def clear_token_bridge():
    return Int(1)

def approve_token_bridge(seed_amt: int, tmpl_sig: TmplSig, devMode: bool):
    blob = LocalBlob()
    tidx = ScratchVar()
    mfee = ScratchVar()
    bfee = ScratchVar()
    basset = ScratchVar()

    normAmount = ScratchVar()
    normFee = ScratchVar()

    def MagicAssert(a) -> Expr:
        if devMode:
            from inspect import currentframe
            return Assert(And(a, Int(currentframe().f_back.f_lineno)))
        else:
            return Assert(a)

    @Subroutine(TealType.uint64)
    def governanceSet() -> Expr:
        maybe = App.globalGetEx(App.globalGet(Bytes("coreid")), Bytes("currentGuardianSetIndex"))
        return Seq(maybe, MagicAssert(maybe.hasValue()), maybe.value())

    @Subroutine(TealType.uint64)
    def getMessageFee() -> Expr:
        maybe = App.globalGetEx(App.globalGet(Bytes("coreid")), Bytes("MessageFee"))
        return Seq(maybe, MagicAssert(maybe.hasValue()), maybe.value())

    @Subroutine(TealType.bytes)
    def getAppAddress(appid : Expr) -> Expr:
        maybe = AppParam.address(appid)
        return Seq(maybe, MagicAssert(maybe.hasValue()), maybe.value())

    def assert_common_checks(e) -> Expr:
        return MagicAssert(And(
            e.rekey_to() == Global.zero_address(),
            e.close_remainder_to() == Global.zero_address(),
            e.asset_close_to() == Global.zero_address(),
            e.on_completion() == OnComplete.NoOp
        ))

    @Subroutine(TealType.none)
    def checkFeePmt(off : Expr):
        return Seq([
            If(mfee.load() > Int(0), Seq([
                    tidx.store(Txn.group_index() - off),
                    MagicAssert(And(
                        Gtxn[tidx.load()].type_enum() == TxnType.Payment,
                        Gtxn[tidx.load()].sender() == Txn.sender(),
                        Gtxn[tidx.load()].receiver() == Global.current_application_address(),
                        Gtxn[tidx.load()].amount() >= mfee.load()
                    )),
                    assert_common_checks(Gtxn[tidx.load()])
            ]))
        ])
    
    @Subroutine(TealType.none)
    def checkTokenLimit(acct, amount):
        maxToken = ScratchVar()
        minToken = ScratchVar()
        return Seq([
            maxToken.store(Btoi(blob.read(acct, Int(124), Int(132)))),
            minToken.store(Btoi(blob.read(acct, Int(132), Int(140)))),
            If (maxToken.load() > Int(0), Seq([
                MagicAssert(And(maxToken.load() >= amount, minToken.load() <= amount)),
            ])),
        ])

    @Subroutine(TealType.none)
    def checkTokenMax(acct, amount):
        maxToken = ScratchVar()
        return Seq([
            maxToken.store(Btoi(blob.read(acct, Int(124), Int(132)))),
            If (maxToken.load() > Int(0), Seq([
                MagicAssert(And(maxToken.load() >= amount)),
            ])),
        ])

    @Subroutine(TealType.none)
    def checkPaused():
        return Seq([
            MagicAssert(App.globalGet(Bytes("onPaused")) == Int(0))
        ])

    @Subroutine(TealType.none)
    def sendMfee():
        return Seq([
            If (mfee.load() > Int(0), Seq([
                    InnerTxnBuilder.SetFields(
                        {
                            TxnField.type_enum: TxnType.Payment,
                            TxnField.receiver: App.globalGet(Bytes("coreAddr")),
                            TxnField.amount: mfee.load(),
                            TxnField.fee: Int(0),
                        }
                    ),
                    InnerTxnBuilder.Next(),
            ])),
        ])

    @Subroutine(TealType.none)
    def escrowLiquidity(escrow, ain, aout):
        return Seq([
            InnerTxnBuilder.SetFields(
                    {
                        TxnField.type_enum: TxnType.ApplicationCall,
                        TxnField.application_id: escrow,
                        TxnField.application_args: [Bytes("liquidity"), Itob(ain), Itob(aout)],
                        TxnField.applications: [Global.current_application_id()],
                        TxnField.fee: Int(0),
                    }
                ),
        ])


    @Subroutine(TealType.none)
    def escrowTransfer(escrow, receiver, amt, aid):
        return Seq([
            If (aid == Int(0), Seq([
                InnerTxnBuilder.SetFields(
                        {
                            TxnField.type_enum: TxnType.ApplicationCall,
                            TxnField.application_id: escrow,
                            TxnField.application_args: [Bytes("transfer"), Itob(amt)],
                            TxnField.accounts: [receiver],
                            TxnField.applications: [Global.current_application_id()],
                            TxnField.fee: Int(0),
                        }
                    ),
            ]), Seq([
                    InnerTxnBuilder.SetFields(
                        {
                            TxnField.type_enum: TxnType.ApplicationCall,
                            TxnField.application_id: escrow,
                            TxnField.application_args: [Bytes("transfer"), Itob(amt)],
                            TxnField.accounts: [receiver],
                            TxnField.applications: [Global.current_application_id()],
                            TxnField.fee: Int(0),
                            TxnField.assets: [aid],
                        }
                    ),
            ])),
        ])

    @Subroutine(TealType.bytes)
    def encode_uvarint(val: Expr, b: Expr):
        buff = ScratchVar()
        return Seq(
            buff.store(b),
            Concat(
                buff.load(),
                If(
                        val >= Int(128),
                        encode_uvarint(
                            val >> Int(7),
                            Extract(Itob((val & Int(255)) | Int(128)), Int(7), Int(1)),
                        ),
                        Extract(Itob(val & Int(255)), Int(7), Int(1)),
                ),
            ),
        )

    # @Subroutine(TealType.bytes)
    # def trim_bytes(str: Expr):
    #     len = ScratchVar()
    #     off = ScratchVar()
    #     zero = ScratchVar()
    #     r = ScratchVar()

    #     return Seq([
    #         r.store(str),

    #         len.store(Len(r.load())),
    #         zero.store(BytesZero(Int(1))),
    #         off.store(Int(0)),

    #         While(off.load() < len.load()).Do(Seq([
    #             If(Extract(r.load(), off.load(), Int(1)) == zero.load()).Then(Seq([
    #                     r.store(Extract(r.load(), Int(0), off.load())),
    #                     off.store(len.load())
    #             ])),
    #                 off.store(off.load() + Int(1))
    #         ])),
    #         r.load()
    #     ])

    @Subroutine(TealType.uint64)
    def calculateBridgeFee(acc, asset, amount, isTransfer):
        src = ScratchVar()
        dest = ScratchVar()
        bridgeFee = ScratchVar()
        ret = ScratchVar()

        return Seq([
            src.store(Btoi(blob.read(acc, Int(198), Int(199)))),
            dest.store(Btoi(blob.read(acc, Int(199), Int(200)))),

            If (isTransfer == Int(1), Seq([
                # src == true || (!src && !dest)
                If (Or(src.load() == Int(1), And(src.load() == Int(0), dest.load() == Int(0))), Seq([
                    # Send Transfer Fee
                    bridgeFee.store(Btoi(blob.read(acc, Int(174), Int(182)))),
                ]), Seq([
                    bridgeFee.store(Int(0)),
                ]))
            ]), Seq([
                # dest == true || (!src && !dest)
                If (Or(dest.load() == Int(1), And(src.load() == Int(0), dest.load() == Int(0))), Seq([
                    # Redeem / Complete Transfer Fee
                    bridgeFee.store(Btoi(blob.read(acc, Int(182), Int(190)))),
                ]), Seq([
                    bridgeFee.store(Int(0)),
                ]))
            ])),

            # We have no bridge fee
            If (bridgeFee.load() == Int(0), Return(Int(0))),

            ret.store(amount * bridgeFee.load()),
            ret.store(ret.load() / Int(10000000000)),
            basset.store(asset),

            Return(ret.load()),
        ])

    @Subroutine(TealType.none) # when completeTransfer - Always make it the same decimal as ASA
    def normalizedAmount(dec, amount, fee):
        d = ScratchVar()

        return Cond(
            [dec < Int(9),
            Seq([
                d.store(Exp(Int(10), Int(8) - dec)),
                normAmount.store(amount / d.load()),
                normFee.store(fee / d.load()),
            ])],

            [dec > Int(19), Reject()],

            [Int(1), Seq([
                d.store(Exp(Int(10), dec - Int(8))),
                normAmount.store(amount * d.load()),
                normFee.store(fee * d.load()),
            ])]
        )

    @Subroutine(TealType.none) # when sendTransfer - Always make it 8 decimals
    def denormalizedAmount(dec, amount, fee):
        d = ScratchVar()

        return Cond(
            [dec < Int(9),
            Seq([
                d.store(Exp(Int(10), Int(8) - dec)),
                normAmount.store(amount * d.load()),
                normFee.store(fee * d.load())
            ])],

            [dec > Int(19), Reject()],

            [Int(1), Seq([
                d.store(Exp(Int(10), dec - Int(8))),
                normAmount.store(amount / d.load()),
                normFee.store(fee / d.load()),
            ])]
        )

    @Subroutine(TealType.bytes)
    def get_sig_address(acct_seq_start: Expr, emitter: Expr):
        # We could iterate over N items and encode them for a more general interface
        # but we inline them directly here

        return Sha512_256(
            Concat(
                Bytes("Program"),
                # ADDR_IDX aka sequence start
                tmpl_sig.get_bytecode_chunk(0),
                encode_uvarint(acct_seq_start, Bytes("")),

                # EMMITTER_ID
                tmpl_sig.get_bytecode_chunk(1),
                encode_uvarint(Len(emitter), Bytes("")),
                emitter,

                # APP_ID
                tmpl_sig.get_bytecode_chunk(2),
                encode_uvarint(Global.current_application_id(), Bytes("")),

                # TMPL_APP_ADDRESS
                tmpl_sig.get_bytecode_chunk(3),
                encode_uvarint(Len(Global.current_application_address()), Bytes("")),
                Global.current_application_address(),

                tmpl_sig.get_bytecode_chunk(4),
            )
        )

    def updateEscrow():
        return Seq([
            # Only the admin can do the update
            MagicAssert(
                And(
                    Txn.sender() == App.globalGet(Bytes("owner")),
                    # the first apps should be the escrow ID
                    # the second apps should be the new bridge ID
                    Txn.applications.length() == Int(2),
                )
            ),

            InnerTxnBuilder.Begin(),

            # https://pyteal.readthedocs.io/en/stable/accessing_transaction_field.html?highlight=txn%20applications#special-case-txn-accounts-and-txn-applications
            InnerTxnBuilder.SetFields(
                    {
                        TxnField.type_enum: TxnType.ApplicationCall,
                        TxnField.application_id: Txn.applications[1],
                        TxnField.application_args: [Bytes("updateBridge")],
                        TxnField.applications: [Txn.applications[2], Txn.applications[0]],
                        TxnField.fee: Int(0), # Fee paid by the user
                    }
                ),

            InnerTxnBuilder.Submit(),

            Approve(),
        ])

    def updateWhitelist():
        return Seq([
            # Only the admin can do the update
            MagicAssert(And(
                Txn.sender() == App.globalGet(Bytes("owner")),
                Txn.application_args.length() == Int(2),
                Txn.applications.length() == Int(1),
                Txn.accounts.length() == Int(1),
                Or(Txn.application_args[1] == Bytes("w1"), Txn.application_args[1] == Bytes("w2"))
            )),

            InnerTxnBuilder.Begin(),

            # https://pyteal.readthedocs.io/en/stable/accessing_transaction_field.html?highlight=txn%20applications#special-case-txn-accounts-and-txn-applications
            InnerTxnBuilder.SetFields(
                    {
                        TxnField.type_enum: TxnType.ApplicationCall,
                        TxnField.application_id: Txn.applications[1],
                        TxnField.application_args: [Bytes("updateWhitelist"), Txn.application_args[1]],
                        TxnField.accounts: [Txn.accounts[1]],
                        TxnField.fee: Int(0), # Fee paid by the user
                        TxnField.applications: [Global.current_application_id()]
                    }
                ),

            InnerTxnBuilder.Submit(),

            Approve(),
        ])

    def registerChain():
        return Seq([
            assert_common_checks(Txn),
            MagicAssert(Txn.sender() == App.globalGet(Bytes("owner"))),

            # Remove check for enabling re-registering foreign contract 
            # MagicAssert(App.globalGet(Concat(Bytes("Chain"), Txn.application_args[1])) == Int(0)),

            # Txn.application_args[1] is the chainId
            # Txn.application_args[2] is ther emitterAddress
            App.globalPut(Concat(Bytes("Chain"), Txn.application_args[1]), Txn.application_args[2]),

            Approve()
        ])

    def receiveAttest():
        off = ScratchVar()
        Address = ScratchVar()
        Chain = ScratchVar()
        FromChain = ScratchVar()

        asset = ScratchVar()
        buf = ScratchVar()

        return Seq([
            # Only the admin can receiveAttest
            MagicAssert(Txn.sender() == App.globalGet(Bytes("owner"))),

            checkForDuplicate(),

            tidx.store(Txn.group_index() - Int(5)),

            MagicAssert(And(
                # Lets see if the vaa we are about to process was actually verified by the core
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].application_id() == App.globalGet(Bytes("coreid")),
                Gtxn[tidx.load()].application_args[0] == Bytes("verifyVAA"),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                Gtxn[tidx.load()].on_completion() == OnComplete.NoOp,

                # we are all taking about the same vaa?
                Gtxn[tidx.load()].application_args[1] == Txn.application_args[1],

                )),
            assert_common_checks(Gtxn[tidx.load()]),
                
            tidx.store(Txn.group_index() - Int(4)),
            MagicAssert(And(
                # Did the user pay the lsig to attest a new product?
                Gtxn[tidx.load()].type_enum() == TxnType.Payment,
                Gtxn[tidx.load()].amount() >= Int(100000),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                Gtxn[tidx.load()].receiver() == Txn.accounts[3],
                )),
            assert_common_checks(Gtxn[tidx.load()]),

            tidx.store(Txn.group_index() - Int(3)),
            MagicAssert(And(
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].application_id() == Global.current_application_id(),
                Gtxn[tidx.load()].application_args[0] == Bytes("nop"),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                
                (Global.group_size() - Int(1)) == Txn.group_index()    # This should be the last entry...
            )),
            assert_common_checks(Gtxn[tidx.load()]),

            tidx.store(Txn.group_index() - Int(2)),
            MagicAssert(And(
                # We had to buy some extra CPU
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].application_id() == Global.current_application_id(),
                Gtxn[tidx.load()].application_args[0] == Bytes("nop"),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                )),
            assert_common_checks(Gtxn[tidx.load()]),

            tidx.store(Txn.group_index() - Int(1)),
            MagicAssert(And(
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].application_id() == Global.current_application_id(),
                Gtxn[tidx.load()].application_args[0] == Bytes("nop"),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                
                (Global.group_size() - Int(1)) == Txn.group_index()    # This should be the last entry...
            )),
            assert_common_checks(Gtxn[tidx.load()]),

            off.store(Btoi(Extract(Txn.application_args[1], Int(5), Int(1))) * Int(66) + Int(6) + Int(8)), # The offset of the chain
            Chain.store(Btoi(Extract(Txn.application_args[1], off.load(), Int(2)))),

            # Make sure that the emitter on the sending chain is correct for the token bridge
            MagicAssert(App.globalGet(Concat(Bytes("Chain"), Extract(Txn.application_args[1], off.load(), Int(2)))) 
                   == Extract(Txn.application_args[1], off.load() + Int(2), Int(32))),
            
            off.store(off.load()+Int(43)),

            MagicAssert(Int(2) ==      Btoi(Extract(Txn.application_args[1], off.load(),      Int(1)))),
            Address.store(             Extract(Txn.application_args[1], off.load() + Int(1),  Int(32))),
            
            FromChain.store(      Btoi(Extract(Txn.application_args[1], off.load() + Int(33), Int(2)))),

            #   This confirms the user gave us access to the correct memory for this asset..
            MagicAssert(Txn.accounts[3] == get_sig_address(FromChain.load(), Address.load())),

            # Lets see if we've seen this asset before
            asset.store(blob.read(Int(3), Int(0), Int(8))),

            # The # offset to the digest
            off.store(Btoi(Extract(Txn.application_args[1], Int(5), Int(1))) * Int(66) + Int(6)), 

            # New asset
            If(asset.load() == Itob(Int(0))).Then(Seq([
                    asset.store(Itob(Btoi(Txn.application_args[2]))),
                    Pop(blob.write(Int(4), Int(0), asset.load())),
                    Pop(blob.write(Int(3), Int(0), asset.load())),
                    blob.meta(Int(4), Bytes("asset")),
                    blob.meta(Int(3), Bytes("asset")),
            ])),

            # Save the max, min, and transfer fee - inside the asset storage
            Pop(blob.write(Int(4), Int(132), Itob(Btoi(Txn.application_args[3])))), # Token Min
            Pop(blob.write(Int(4), Int(124), Itob(Btoi(Txn.application_args[4])))), # Token Max
            Pop(blob.write(Int(4), Int(174), Itob(Btoi(Txn.application_args[5])))), # Transfer fee
            Pop(blob.write(Int(4), Int(182), Itob(Btoi(Txn.application_args[6])))), # Redeem fee
            Pop(blob.write(Int(4), Int(116), Itob(Int(0)))), # This token is not native

            Pop(blob.write(Int(4), Int(190), Itob(Btoi(Txn.application_args[7])))), # Escrow ID

            Pop(blob.write(Int(4), Int(198), Itob(Btoi(Txn.application_args[8])))), # Source Fee
            Pop(blob.write(Int(4), Int(199), Itob(Btoi(Txn.application_args[9])))), # Destination Fee

            # We save away the entire digest that created this asset in case we ever need to reproduce it while sending this
            # coin to another chain

            buf.store(Txn.application_args[1]),
            Pop(blob.write(Int(3), Int(8), Extract(buf.load(), off.load(), Len(buf.load()) - off.load()))),

            Pop(blob.write(Int(4), Int(140), blob.read(Int(3), Int(60), Int(92)))),
            Pop(blob.write(Int(4), Int(172), blob.read(Int(3), Int(92), Int(94)))),

            Approve()
        ])

    def completeTransfer():
        off = ScratchVar()
        
        Chain = ScratchVar()
        Emitter = ScratchVar()

        Amount = ScratchVar()
        Origin = ScratchVar()
        OriginChain = ScratchVar()
        Destination = ScratchVar()
        DestChain = ScratchVar()
        Fee = ScratchVar()
        asset = ScratchVar()
        assetD = ScratchVar()

        zb = ScratchVar()
        action = ScratchVar()
        aid = ScratchVar()

        escrow = ScratchVar()
        
        return Seq([
            checkPaused(),

            checkForDuplicate(),

            zb.store(BytesZero(Int(32))),

            tidx.store(Txn.group_index() - Int(1)),

            MagicAssert(And(
                # Lets see if the vaa we are about to process was actually verified by the core
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].application_id() == App.globalGet(Bytes("coreid")),
                Gtxn[tidx.load()].application_args[0] == Bytes("verifyVAA"),
                Gtxn[tidx.load()].sender() == Txn.sender(),
                Gtxn[tidx.load()].on_completion() == OnComplete.NoOp,

                # Lets see if the vaa we are about to process was actually verified by the core
                Gtxn[tidx.load()].application_args[1] == Txn.application_args[1],

                # We all opted into the same accounts?
                Gtxn[tidx.load()].accounts[0] == Txn.accounts[0],
            )),
            assert_common_checks(Gtxn[tidx.load()]),
            assert_common_checks(Txn),

            off.store(Btoi(Extract(Txn.application_args[1], Int(5), Int(1))) * Int(66) + Int(6) + Int(8)), # The offset of the chain

            Chain.store(Btoi(Extract(Txn.application_args[1], off.load(), Int(2)))),
            Emitter.store(Extract(Txn.application_args[1], off.load() + Int(2), Int(32))),

            # We coming from the correct emitter on the sending chain for the token bridge
            # ... This is 90% of the security...
            If(Chain.load() == Int(8),
               MagicAssert(Global.current_application_address() == Emitter.load()), # This came from us?
               MagicAssert(App.globalGet(Concat(Bytes("Chain"), Extract(Txn.application_args[1], off.load(), Int(2)))) == Emitter.load())),

            off.store(off.load()+Int(43)),

            # This is a transfer message... right?
            action.store(Btoi(Extract(Txn.application_args[1], off.load(), Int(1)))),

            MagicAssert(Or(action.load() == Int(1), action.load() == Int(3))),

            MagicAssert(Extract(Txn.application_args[1], off.load() + Int(1), Int(24)) == Extract(zb.load(), Int(0), Int(24))),
            Amount.store(        Btoi(Extract(Txn.application_args[1], off.load() + Int(25), Int(8)))),  # uint256

            Origin.store(             Extract(Txn.application_args[1], off.load() + Int(33), Int(32))),
            OriginChain.store(   Btoi(Extract(Txn.application_args[1], off.load() + Int(65), Int(2)))),
            Destination.store(        Extract(Txn.application_args[1], off.load() + Int(67), Int(32))),
            DestChain.store(     Btoi(Extract(Txn.application_args[1], off.load() + Int(99), Int(2)))),

            MagicAssert(Extract(Txn.application_args[1], off.load() + Int(101),Int(24)) == Extract(zb.load(), Int(0), Int(24))),
            Fee.store(           Btoi(Extract(Txn.application_args[1], off.load() + Int(125),Int(8)))),  # uint256

            # This directed at us?
            MagicAssert(DestChain.load() == Int(8)),

            MagicAssert(Fee.load() <= Amount.load()),

            # The relayer fee is deducted in sendTransfer()
            If (action.load() == Int(3), Seq([
                    aid.store(Btoi(Extract(Destination.load(), Int(24), Int(8)))), # The destination is the appid in a payload3
                    tidx.store(Txn.group_index() + Int(1)),
                    MagicAssert(And(
                        Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                        Gtxn[tidx.load()].application_args[0] == Txn.application_args[0],
                        Gtxn[tidx.load()].application_args[1] == Txn.application_args[1],
                        Gtxn[tidx.load()].application_id() == aid.load()
                    )),
                    Destination.store(getAppAddress(aid.load()))
            ])),

            # Origin chain is not coming from Algorand, asset not native to Algorand
            If(OriginChain.load() == Int(8),
               Seq([
                   asset.store(Btoi(Extract(Origin.load(), Int(24), Int(8)))),

                    # Get the escrow
                    MagicAssert(Txn.accounts[3] == get_sig_address(asset.load(), Bytes("native"))),
                    escrow.store(Btoi(blob.read(Int(3), Int(190), Int(198)))), # Escrow APP ID

                   MagicAssert(Txn.accounts[3] == get_sig_address(asset.load(), Bytes("native"))),
                   # Now, the horrible part... we have to scale the amount back out to compensate for the "dedusting" 
                   # when this was sent...

                   If(asset.load() == Int(0),
                      Seq([
                        # normalize to ALGO decimal (6 decimals)
                        normalizedAmount(Int(6), Amount.load(), Fee.load()),
                        Amount.store(normAmount.load()),
                        Fee.store(normFee.load()),

                        # Check max token transfer amount
                        checkTokenMax(Int(3), Amount.load()),

                        # Calculate Bridge Fees
                        bfee.store(calculateBridgeFee(Int(3), Int(0), Amount.load(), Int(0))),
                        Amount.store(Amount.load() - bfee.load()),

                          InnerTxnBuilder.Begin(),
                          If(bfee.load() > Int(0), Seq([
                                escrowTransfer(escrow.load(), App.globalGet(Bytes("Treasury")), bfee.load(), asset.load()),
                                InnerTxnBuilder.Next(),
                          ])),

                            escrowTransfer(escrow.load(), Destination.load(), Amount.load(), asset.load()),
                            InnerTxnBuilder.Next(),
                            escrowLiquidity(escrow.load(), Int(0), Amount.load()),
                 
                          If(Fee.load() > Int(0), Seq([
                                  InnerTxnBuilder.Next(),
                                  escrowTransfer(escrow.load(), Txn.sender(), Fee.load(), asset.load()),
                          ])),
                          InnerTxnBuilder.Submit(),

                          Approve()
                      ]),            # End of special case for algo
                      Seq([          # Start of handling code for algorand tokens
                        
                        # Normalize back to asa decimal
                        assetD.store(Btoi(extract_decimal(asset.load()))),
                        normalizedAmount(assetD.load(), Amount.load(), Fee.load()),
                        Amount.store(normAmount.load()),
                        Fee.store(normFee.load()),

                        # Check max token transfer amount
                        checkTokenMax(Int(3), Amount.load()),

                        # Calculate Bridge Fees
                        bfee.store(calculateBridgeFee(Int(3), asset.load(), Amount.load(), Int(0))),
                        Amount.store(Amount.load() - bfee.load()),

                                    # If(factor.load() != Int(1),
                      ])           # End of handling code for algorand tokens
                   ),              # If(asset.load() == Int(0),
               ]),                 # If(OriginChain.load() == Int(8),

               # OriginChain.load() != Int(8),
               Seq([
                   # Lets see if we've seen this asset before
                   asset.store(Btoi(blob.read(Int(3), Int(0), Int(8)))),
                   escrow.store(Btoi(blob.read(Int(3), Int(190), Int(198)))), # Escrow APP ID

                   MagicAssert(And(
                       asset.load() != Int(0),
                       Txn.accounts[3] == get_sig_address(asset.load(), Bytes("native")),
                     )
                   ),

                    # Normalize back to asa decimal
                    assetD.store(Btoi(extract_decimal(asset.load()))),
                    normalizedAmount(assetD.load(), Amount.load(), Fee.load()),
                    Amount.store(normAmount.load()),
                    Fee.store(normFee.load()),

                    # Check max token transfer amount
                    checkTokenMax(Int(3), Amount.load()),

                    # Calculate Bridge Fees
                    bfee.store(calculateBridgeFee(Int(3), asset.load(), Amount.load(), Int(0))),
                    Amount.store(Amount.load() - bfee.load()),

               ])  # OriginChain.load() != Int(8),
            ),  #  If(OriginChain.load() == Int(8)

            # Actually send the coins...
            InnerTxnBuilder.Begin(),
            If(bfee.load() > Int(0), Seq([
                escrowTransfer(escrow.load(), App.globalGet(Bytes("Treasury")), bfee.load(), asset.load()),
                InnerTxnBuilder.Next(),
            ])),

            escrowTransfer(escrow.load(), Destination.load(), Amount.load(), asset.load()),
            InnerTxnBuilder.Next(),
            escrowLiquidity(escrow.load(), Int(0), Amount.load()),

            If(Fee.load() > Int(0), Seq([
                InnerTxnBuilder.Next(),
                escrowTransfer(escrow.load(), Txn.sender(), Fee.load(), asset.load()),
            ])),
            InnerTxnBuilder.Submit(),

            Approve()
        ])

    METHOD = Txn.application_args[0]

    on_delete = Seq([Reject()])

    # @Subroutine(TealType.bytes)
    # def auth_addr(id) -> Expr:
    #     maybe = AccountParam.authAddr(id)
    #     return Seq(maybe, If(maybe.hasValue(), maybe.value(), Bytes("")))

    @Subroutine(TealType.bytes)
    def extract_name(id) -> Expr:
        maybe = AssetParam.name(id)
        return Seq(maybe, If(maybe.hasValue(), maybe.value(), Bytes("")))

    # @Subroutine(TealType.bytes)
    # def extract_creator(id) -> Expr:
    #     maybe = AssetParam.creator(id)
    #     return Seq(maybe, If(maybe.hasValue(), maybe.value(), Bytes("")))

    @Subroutine(TealType.bytes)
    def extract_unit_name(id) -> Expr:
        maybe = AssetParam.unitName(id)
        return Seq(maybe, If(maybe.hasValue(), maybe.value(), Bytes("")))

    @Subroutine(TealType.bytes)
    def extract_decimal(id) -> Expr:
        maybe = AssetParam.decimals(id)
        return Seq(maybe, If(maybe.hasValue(), Extract(Itob(maybe.value()), Int(7), Int(1)), Bytes("base16", "00")))


    def sendTransfer():
        aid = ScratchVar()
        amount = ScratchVar()
        p = ScratchVar()
        asset = ScratchVar()
        Address = ScratchVar()
        FromChain = ScratchVar()
        zb = ScratchVar()
        fee = ScratchVar()

        escrow = ScratchVar()

        isN = ScratchVar() # is native?

        return Seq([
            checkPaused(),

            mfee.store(getMessageFee()),

            zb.store(BytesZero(Int(32))),

            aid.store(Btoi(Txn.application_args[1])),

            # what should we pass as a fee...
            fee.store(Btoi(Txn.application_args[4])),

            # Mfee check
            checkFeePmt(Int(2)),

            # Get the escrow
            MagicAssert(Txn.accounts[2] == get_sig_address(aid.load(), Bytes("native"))),
            escrow.store(Btoi(blob.read(Int(2), Int(190), Int(198)))), # Escrow APP ID

            tidx.store(Txn.group_index() - Int(1)),

            If(aid.load() == Int(0),
               Seq([
                   MagicAssert(And(
                       # The previous txn is the asset transfer itself
                       Gtxn[tidx.load()].type_enum() == TxnType.Payment,
                       Gtxn[tidx.load()].sender() == Txn.sender(),
                       Gtxn[tidx.load()].receiver() == getAppAddress(escrow.load()),
                   )),
                   assert_common_checks(Gtxn[tidx.load()]),

                   amount.store(Gtxn[tidx.load()].amount()),

                   # Check min and max token transfer amount
                    checkTokenLimit(Int(2), amount.load()),
                   
                   MagicAssert(fee.load() < amount.load()),
                   amount.store(amount.load() - fee.load()),

                    # Bridge Fees
                   bfee.store(calculateBridgeFee(Int(2), aid.load(), amount.load(), Int(1))),
                   amount.store(amount.load() - bfee.load()),

                   # Normalize to 8 decimals (ALGO has 6 decimals)
                    amount.store(amount.load() * Int(100)),
                    fee.store(fee.load() * Int(100)),
               ]),
               Seq([

                   MagicAssert(And(
                       # The previous txn is the asset transfer itself
                       Gtxn[tidx.load()].type_enum() == TxnType.AssetTransfer,
                       Gtxn[tidx.load()].sender() == Txn.sender(),
                       Gtxn[tidx.load()].xfer_asset() == aid.load(),
                       Gtxn[tidx.load()].asset_receiver() == getAppAddress(escrow.load()),
                   )),
                   assert_common_checks(Gtxn[tidx.load()]),

                   amount.store(Gtxn[tidx.load()].asset_amount()),

                    # Check min and max token transfer amount
                    checkTokenLimit(Int(2), amount.load()),

                   # peal the fee off the amount
                   MagicAssert(fee.load() <= amount.load()),
                   amount.store(amount.load() - fee.load()),

                    # Bridge Fees
                    bfee.store(calculateBridgeFee(Int(2), aid.load(), amount.load(), Int(1))),
                    amount.store(amount.load() - bfee.load()),

                    # Normalize amount to 8 decimals
                    denormalizedAmount(Btoi(extract_decimal(aid.load())), amount.load(), fee.load()),
                    amount.store(normAmount.load()),
                    fee.store(normFee.load()),
               ]),
            ),

            # If it is nothing but dust lets just abort the whole transaction and save 
            MagicAssert(And(amount.load() > Int(0), fee.load() >= Int(0))),

            isN.store(Btoi(blob.read(Int(2), Int(116), Int(124)))),

            # Is the authorizing signature of the creator of the asset the address of the token_bridge app itself?
            If(And(aid.load() != Int(0), isN.load() == Int(0)),
               Seq([
                   # Foreign/Non Native Tokens
#                   Log(Bytes("Wormhole wrapped")),
                   asset.store(blob.read(Int(2), Int(0), Int(8))),
                   # This the correct asset?
                   MagicAssert(Txn.application_args[1] == asset.load()),

                    # Pull the foreign asset data from the storage (receivedAttest)
                    Address.store(blob.read(Int(2), Int(140), Int(172))),
                    FromChain.store(blob.read(Int(2), Int(172), Int(174))),

               ]),
               Seq([
                   # Native Tokens
#                   Log(Bytes("Non Wormhole wrapped")),
                   FromChain.store(Bytes("base16", "0008")),
                   Address.store(Txn.application_args[1]),
               ])
            ),

            # Correct address len?
            MagicAssert(And(
                Len(Address.load()) <= Int(32),
                Len(FromChain.load()) == Int(2),
                Len(Txn.application_args[2]) <= Int(32),
                Txn.application_args.length() >= Int(5),
                Txn.application_args.length() <= Int(6),
            )),

            p.store(Concat(
                If(Txn.application_args.length() == Int(5),
                   Bytes("base16", "01"),
                   Bytes("base16", "03")),
                Extract(zb.load(), Int(0), Int(24)),
                Itob(amount.load()),  # 8 bytes
                Extract(zb.load(), Int(0), Int(32) - Len(Address.load())),
                Address.load(),
                FromChain.load(),
                Extract(zb.load(), Int(0), Int(32) - Len(Txn.application_args[2])),
                Txn.application_args[2],
                Extract(Txn.application_args[3], Int(6), Int(2)),
                Extract(zb.load(), Int(0), Int(24)),
                Itob(fee.load()),  # 8 bytes
                If(Txn.application_args.length() == Int(6), Txn.application_args[5], Bytes(""))
            )),

            # This one magic line should protect us from overruns/underruns and trickery..
            If(Txn.application_args.length() == Int(6), 
               MagicAssert(Len(p.load()) == Int(133) + Len(Txn.application_args[5])),
               MagicAssert(Len(p.load()) == Int(133))),

            InnerTxnBuilder.Begin(),
            If(bfee.load() > Int(0), Seq([
                escrowTransfer(escrow.load(), App.globalGet(Bytes("Treasury")), bfee.load(), aid.load()),
                InnerTxnBuilder.Next(),
            ])),
            escrowLiquidity(escrow.load(), amount.load(), Int(0)),
            InnerTxnBuilder.Next(),
            sendMfee(),
            InnerTxnBuilder.SetFields(
                {
                    TxnField.type_enum: TxnType.ApplicationCall,
                    TxnField.application_id: App.globalGet(Bytes("coreid")),
                    TxnField.application_args: [Bytes("publishMessage"), p.load(), Itob(Int(0))],
                    TxnField.accounts: [Txn.accounts[1]],
                    TxnField.note: Bytes("publishMessage"),
                    TxnField.fee: Int(0),
                }
            ),
            InnerTxnBuilder.Submit(),

            Approve()
        ])

    def updateTokenConfig():
        return Seq([
            # Only the admin can do the fee update
            MagicAssert(Txn.sender() == App.globalGet(Bytes("owner"))),

            # Check the correct logic sig storage
            MagicAssert(Txn.accounts[1] == get_sig_address(Btoi(Txn.application_args[1]), Bytes("native"))),

            Pop(blob.write(Int(1), Int(174), Itob(Btoi(Txn.application_args[2])))), # Transfer Fee
            Pop(blob.write(Int(1), Int(182), Itob(Btoi(Txn.application_args[3])))), # Redeem Fee
            Pop(blob.write(Int(1), Int(132), Itob(Btoi(Txn.application_args[4])))), # Min Token
            Pop(blob.write(Int(1), Int(124), Itob(Btoi(Txn.application_args[5])))), # Max Token
            Pop(blob.write(Int(1), Int(198), Itob(Btoi(Txn.application_args[6])))), # Source Fee
            Pop(blob.write(Int(1), Int(199), Itob(Btoi(Txn.application_args[7])))), # Destination Fee

            Approve(),
        ])

    def do_paused():
        isP = ScratchVar()

        return Seq([
            # Only the admin can pause
            MagicAssert(Txn.sender() == App.globalGet(Bytes("owner"))),

            isP.store(Btoi(Txn.application_args[1])),

            # Check the argument
            MagicAssert(Or(isP.load() == Int(0), isP.load() == Int(1))),

            App.globalPut(Bytes("onPaused"), isP.load()),

            Approve()
        ])

    def do_deposit():
        aid = ScratchVar()
        escrow = ScratchVar()

        return Seq([
            aid.store(Btoi(Txn.application_args[1])),
            MagicAssert(Txn.accounts[1] == get_sig_address(aid.load(), Bytes("native"))),
            escrow.store(Btoi(blob.read(Int(1), Int(190), Int(198)))),

            # after this tx should be an escrow call
            tidx.store(Txn.group_index() + Int(1)),
            MagicAssert(And(
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].sender() == Txn.sender(),
                Gtxn[tidx.load()].application_id() == escrow.load(),
                Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
            )),

            Approve(),
        ])

    def do_withdraw():
        aid = ScratchVar()
        escrow = ScratchVar()

        return Seq([
            aid.store(Btoi(Txn.application_args[1])),
            MagicAssert(Txn.accounts[1] == get_sig_address(aid.load(), Bytes("native"))),
            escrow.store(Btoi(blob.read(Int(1), Int(190), Int(198)))),

             # after this tx should be an escrow call
            tidx.store(Txn.group_index() + Int(1)),
            MagicAssert(And(
                Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                Gtxn[tidx.load()].sender() == Txn.sender(),
                Gtxn[tidx.load()].application_id() == escrow.load(),
                Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
            )),

            Approve(),
        ])

    def do_optin():
        return Seq([
            MagicAssert(Or(
                Txn.accounts[1] == get_sig_address(Btoi(Txn.application_args[1]), Bytes("native")),
                Txn.sender() == App.globalGet(Bytes("owner")),
            )),
            assert_common_checks(Txn),

            InnerTxnBuilder.Begin(),
            InnerTxnBuilder.SetFields(
                {
                    TxnField.sender: Txn.accounts[1],
                    TxnField.type_enum: TxnType.AssetTransfer,
                    TxnField.xfer_asset: Btoi(Txn.application_args[1]),
                    TxnField.asset_amount: Int(0),
                    TxnField.asset_receiver: Txn.accounts[1],
                    TxnField.fee: Int(0),
                }
            ),
            InnerTxnBuilder.Submit(),

            Approve()
        ])

    # This is for attesting
    def attestToken():
        p = ScratchVar()
        zb = ScratchVar()
        d = ScratchVar()
        uname = ScratchVar()
        name = ScratchVar()
        aid = ScratchVar()

        return Seq([
            # Only the admin can attestToken
            MagicAssert(Txn.sender() == App.globalGet(Bytes("owner"))),

            mfee.store(getMessageFee()),

            checkFeePmt(Int(1)),

            aid.store(Btoi(Txn.application_args[1])),

            #  Log(Bytes("Non Wormhole wrapped")),
            MagicAssert(Txn.accounts[2] == get_sig_address(aid.load(), Bytes("native"))),

            zb.store(BytesZero(Int(32))),
            
            aid.store(Btoi(Txn.application_args[1])),

            If(aid.load() == Int(0),
                Seq([
                    d.store(Bytes("base16", "06")),
                    uname.store(Bytes("ALGO")),
                    name.store(Bytes("ALGO"))
                ]),
                Seq([
                    d.store(extract_decimal(aid.load())),
                    If(Btoi(d.load()) > Int(8), d.store(Bytes("base16", "08"))),
                    uname.store(extract_unit_name(aid.load())),
                    name.store(extract_name(aid.load())),
                ])
            ),

            p.store(
                Concat(
                    #PayloadID uint8 = 2
                    Bytes("base16", "02"),
                    #TokenAddress [32]uint8
                    Extract(zb.load(),Int(0), Int(24)),
                    Itob(aid.load()),
                    #TokenChain uint16
                    Bytes("base16", "0008"),
                    #Decimals uint8
                    d.load(),
                    #Symbol [32]uint8
                    uname.load(),
                    Extract(zb.load(), Int(0), Int(32) - Len(uname.load())),
                    #Name [32]uint8
                    name.load(),
                    Extract(zb.load(), Int(0), Int(32) - Len(name.load())),
                )
            ),

            MagicAssert(Len(p.load()) == Int(100)),

            # Mark this tokens as a native token from Algorand
            blob.zero(Int(2)),
            Pop(blob.write(Int(2), Int(116), Itob(aid.load()))),

            # Save Token Limit
            Pop(blob.write(Int(2), Int(124), Itob(Btoi(Txn.application_args[3])))), # max token
            Pop(blob.write(Int(2), Int(132), Itob(Btoi(Txn.application_args[2])))), # min token

            # Save the bridge fee
            Pop(blob.write(Int(2), Int(174), Itob(Btoi(Txn.application_args[4])))), # transfer fee
            Pop(blob.write(Int(2), Int(182), Itob(Btoi(Txn.application_args[5])))), # redeem fee

            # Save the escrow ID
            Pop(blob.write(Int(2), Int(190), Itob(Btoi(Txn.application_args[6])))),

            Pop(blob.write(Int(2), Int(198), Itob(Btoi(Txn.application_args[7])))), # Source Fee
            Pop(blob.write(Int(2), Int(199), Itob(Btoi(Txn.application_args[8])))), # Destination Fee

            InnerTxnBuilder.Begin(),
            sendMfee(),
            InnerTxnBuilder.SetFields(
                {
                    TxnField.type_enum: TxnType.ApplicationCall,
                    TxnField.application_id: App.globalGet(Bytes("coreid")),
                    TxnField.application_args: [Bytes("publishMessage"), p.load(), Itob(Int(0))],
                    TxnField.accounts: [Txn.accounts[1]],
                    TxnField.note: Bytes("publishMessage"),
                    TxnField.fee: Int(0),
                }
            ),
            InnerTxnBuilder.Submit(),

            Approve()
        ])

    @Subroutine(TealType.none)
    def checkForDuplicate():
        off = ScratchVar()
        emitter = ScratchVar()
        sequence = ScratchVar()
        b = ScratchVar()
        byte_offset = ScratchVar()

        return Seq(
            # VM only is version 1
            MagicAssert(Btoi(Extract(Txn.application_args[1], Int(0), Int(1))) == Int(1)),

            off.store(Btoi(Extract(Txn.application_args[1], Int(5), Int(1))) * Int(66) + Int(14)), # The offset of the emitter

            # emitter is chain/contract-address
            emitter.store(Extract(Txn.application_args[1], off.load(), Int(34))),
            sequence.store(Btoi(Extract(Txn.application_args[1], off.load() + Int(34), Int(8)))),

            # They passed us the correct account?  In this case, byte_offset points at the whole block
            byte_offset.store(sequence.load() / Int(max_bits)),
            MagicAssert(Txn.accounts[1] == get_sig_address(byte_offset.load(), emitter.load())),

            # Now, lets go grab the raw byte
            byte_offset.store((sequence.load() / Int(8)) % Int(max_bytes)),
            b.store(blob.get_byte(Int(1), byte_offset.load())),

            # I would hope we've never seen this packet before...   throw an exception if we have
            MagicAssert(GetBit(b.load(), sequence.load() % Int(8)) == Int(0)),

            # Lets mark this bit so that we never see it again
            blob.set_byte(Int(1), byte_offset.load(), SetBit(b.load(), sequence.load() % Int(8), Int(1)))
        )

    def nop():
        return Return (Txn.rekey_to() == Global.zero_address())

    def changeOwner():
        return Seq(
            MagicAssert(And(
                Txn.sender() == App.globalGet(Bytes("owner")),
                Global.group_size() == Int(1),
                Txn.accounts.length() == Int(1),
            )),
            assert_common_checks(Txn),

            App.globalPut(Bytes("owner"), Txn.accounts[1]),

            Approve()
        )

    def updateTreasury():
        return Seq([
            # Only current treasury address can update address
            MagicAssert(And(
                App.globalGet(Bytes("Treasury")) == Txn.sender(),
                Global.group_size() == Int(1),
                Txn.accounts.length() == Int(1),
                )),

            App.globalPut(Bytes("Treasury"), Txn.accounts[1]),

            Approve(),
        ])

    router = Cond(
        [METHOD == Bytes("nop"), nop()],
        [METHOD == Bytes("changeOwner"), changeOwner()],
        [METHOD == Bytes("receiveAttest"), receiveAttest()],
        [METHOD == Bytes("attestToken"), attestToken()],
        [METHOD == Bytes("completeTransfer"), completeTransfer()],
        [METHOD == Bytes("sendTransfer"), sendTransfer()],
        [METHOD == Bytes("optin"), do_optin()],
        [METHOD == Bytes("withdraw"), do_withdraw()],
        [METHOD == Bytes("deposit"), do_deposit()],
        [METHOD == Bytes("paused"), do_paused()],
        [METHOD == Bytes("updateTokenConfig"), updateTokenConfig()],
        [METHOD == Bytes("registerChain"), registerChain()],
        [METHOD == Bytes("updateEscrow"), updateEscrow()],
        [METHOD == Bytes("updateWhitelist"), updateWhitelist()],
        [METHOD == Bytes("updateTreasury"), updateTreasury()],
    )

    on_create = Seq( [
        App.globalPut(Bytes("coreid"), Btoi(Txn.application_args[0])),
        App.globalPut(Bytes("coreAddr"), Txn.application_args[1]),
        App.globalPut(Bytes("onPaused"), Int(0)),
        App.globalPut(Bytes("owner"), Global.creator_address()),
        App.globalPut(Bytes("Treasury"), Global.creator_address()),
        Return(Int(1))
    ])

    def getOnUpdate():
        return Seq([
            Return(Txn.sender() == App.globalGet(Bytes("owner"))),
        ])

    on_update = getOnUpdate()

    @Subroutine(TealType.uint64)
    def optin():
        # Alias for readability
        algo_seed = Gtxn[Txn.group_index() - Int(1)]
        optin = Txn

        well_formed_optin = And(
            # Check that we're paying it
            algo_seed.type_enum() == TxnType.Payment,
            algo_seed.amount() == Int(seed_amt),
            algo_seed.receiver() == optin.sender(),
            algo_seed.rekey_to() == Global.zero_address(),
            algo_seed.close_remainder_to() == Global.zero_address(),
            # Check that its an opt in to us
            optin.type_enum() == TxnType.ApplicationCall,
            optin.on_completion() == OnComplete.OptIn,
            optin.application_id() == Global.current_application_id(),
            optin.rekey_to() == Global.current_application_address(),
            optin.application_args.length() == Int(0)
        )

        return Seq(
            # Make sure its a valid optin
            MagicAssert(well_formed_optin),
            # Init by writing to the full space available for the sender (Int(0))
            blob.zero(Int(0)),
            # we gucci
            Int(1)
        )

    on_optin = Seq( [
        Return(optin())
    ])

    return Cond(
        [Txn.application_id() == Int(0), on_create],
        [Txn.on_completion() == OnComplete.UpdateApplication, on_update],
        [Txn.on_completion() == OnComplete.DeleteApplication, on_delete],
        [Txn.on_completion() == OnComplete.OptIn, on_optin],
        [Txn.on_completion() == OnComplete.NoOp, router]
    )

def get_token_bridge(genTeal, approve_name, clear_name, client: AlgodClient, seed_amt: int, tmpl_sig: TmplSig, devMode: bool) -> Tuple[bytes, bytes]:
    if not devMode:
        client = AlgodClient("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "https://testnet-api.algonode.cloud")
    APPROVAL_PROGRAM = fullyCompileContract(True, client, approve_token_bridge(seed_amt, tmpl_sig, devMode), approve_name, devMode)
    CLEAR_STATE_PROGRAM = fullyCompileContract(True, client, clear_token_bridge(), clear_name, devMode)

    return APPROVAL_PROGRAM, CLEAR_STATE_PROGRAM
