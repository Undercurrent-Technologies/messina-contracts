#!/usr/bin/python3
#python3 admin.py --algod_address=http://localhost:4001 --kmd_address=http://localhost:4002 --kmd_name=test2 --testnet --env=.env --mnemonic="avocado amazing design ritual art drive retire squirrel speak inhale pitch upper innocent thing alien craft venture language blanket upon neither flee what above assault" --genTeal --boot
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

def clear_escrow():
    return Int(1)

def approve_escrow():
    tidx = ScratchVar()
    aid = ScratchVar()

    @Subroutine(TealType.bytes)
    def getAppAddress(appid : Expr) -> Expr:
        maybe = AppParam.address(appid)
        return Seq(maybe, MagicAssert(maybe.hasValue()), maybe.value())

    def MagicAssert(a) -> Expr:
        return Assert(a)

    on_create = Seq( [
        aid.store(Btoi(Txn.application_args[0])),
        App.globalPut(Bytes("aid"), aid.load()), # ASA ID
        App.globalPut(Bytes("bid"), Btoi(Txn.application_args[1])), # Bridge ID
        App.globalPut(Bytes("ain"), Int(0)), # Track Amount In
        App.globalPut(Bytes("aout"), Int(0)), # Track Amount out
        App.globalPut(Bytes("w1"), Global.creator_address()),
        App.globalPut(Bytes("w2"), Global.creator_address()),
        Return(Int(1))
    ])

    on_delete = Seq([Reject()])

    def nop():
        return Seq([Approve()])

    def optin():
        aid = ScratchVar()

        return Seq([
            aid.store(App.globalGet(Bytes("aid"))),

            If(aid.load() != Int(0), Seq([
                InnerTxnBuilder.Begin(),
                InnerTxnBuilder.SetFields(
                    {
                        TxnField.sender: Global.current_application_address(),
                        TxnField.asset_receiver: Global.current_application_address(),
                        TxnField.type_enum: TxnType.AssetTransfer,
                        TxnField.xfer_asset: aid.load(),
                        TxnField.asset_amount: Int(0),
                        TxnField.fee: Int(0),
                    }
                ),
                InnerTxnBuilder.Submit(),
            ]),),

            Approve(),

        ])

    def withdraw():
        amt = ScratchVar()

        return Seq([
            # 1 transaction before should calling the correct bridge ID
            tidx.store(Txn.group_index() - Int(1)),
            MagicAssert(
                    And(
                        Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                        Gtxn[tidx.load()].sender() == Txn.sender(),
                        Or(Gtxn[tidx.load()].sender() ==  App.globalGet(Bytes("w1")), Gtxn[tidx.load()].sender() == App.globalGet(Bytes("w2"))),
                        Gtxn[tidx.load()].application_args[0] == Bytes("withdraw"),
                        Gtxn[tidx.load()].application_id() == App.globalGet(Bytes("bid")),
                        Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
                    )
                ),

            amt.store(Btoi(Txn.application_args[1])),

            # Transfer
            InnerTxnBuilder.Begin(),
            If(App.globalGet(Bytes("aid")) == Int(0), Seq([
                # Pay trf
                InnerTxnBuilder.SetFields(
                    {
                        TxnField.receiver: Txn.sender(),
                        TxnField.type_enum: TxnType.Payment,
                        TxnField.amount: amt.load(),
                        TxnField.fee: Int(0),
                    }
                ),
            ]), Seq([
                # ASA trf
                InnerTxnBuilder.SetFields(
                    {
                        TxnField.asset_receiver: Txn.sender(),
                        TxnField.type_enum: TxnType.AssetTransfer,
                        TxnField.xfer_asset: App.globalGet(Bytes("aid")),
                        TxnField.asset_amount: amt.load(),
                        TxnField.fee: Int(0),
                    }
                ),
            ])),
            InnerTxnBuilder.Submit(),

            Approve(),
        ])

    def transfer():
        badr = ScratchVar()
        aid = ScratchVar()

        return Seq([
            # The caller must be the token bridge app
            badr.store(getAppAddress(App.globalGet(Bytes("bid")))),
            aid.store(App.globalGet(Bytes("aid"))),

            MagicAssert(And(
                Txn.sender() == badr.load()
            )),

            InnerTxnBuilder.Begin(),
            If (aid.load() == Int(0),
            Seq([
                # ALGO Transfer
                InnerTxnBuilder.SetFields(
                    {
                        TxnField.sender: Global.current_application_address(),
                        TxnField.receiver: Txn.accounts[1],
                        TxnField.type_enum: TxnType.Payment,
                        TxnField.amount: Btoi(Txn.application_args[1]),
                        TxnField.fee: Int(0),
                    }
                ),
            ]), 
            Seq([
                # ASA Transfer
                InnerTxnBuilder.SetFields(
                    {
                        TxnField.sender: Global.current_application_address(),
                        TxnField.type_enum: TxnType.AssetTransfer,
                        TxnField.xfer_asset: aid.load(),
                        TxnField.asset_amount: Btoi(Txn.application_args[1]),
                        TxnField.asset_receiver: Txn.accounts[1],
                        TxnField.fee: Int(0),
                    }
                ),
            ])),
            InnerTxnBuilder.Submit(),

            Approve(),
        ])

    def updateBridge():
        badr = ScratchVar()

        return Seq([
            badr.store(getAppAddress(App.globalGet(Bytes("bid")))),

            # Sender should be the bridge
            MagicAssert(And(
                Txn.sender() == badr.load(),
                # The first foreign will be the new bridge id
                # The second foreign is the app reference
                Txn.applications.length() == Int(2),
            )),

            App.globalPut(Bytes("bid"), Txn.applications[1]), # Bridge ID

            Approve(),
        ])

    # Send Transfer Amount In
    def liquidity():
        badr = ScratchVar()
        ain = ScratchVar()
        aout = ScratchVar()

        return Seq([
            badr.store(getAppAddress(App.globalGet(Bytes("bid")))),

            # Sender should be the bridge
            MagicAssert(And(
                Txn.sender() == badr.load()
            )),

            ain.store(Btoi(Txn.application_args[1])),
            aout.store(Btoi(Txn.application_args[2])),

            App.globalPut(Bytes("ain"), App.globalGet(Bytes("ain")) + ain.load()),
            App.globalPut(Bytes("aout"), App.globalGet(Bytes("aout")) + aout.load()),

            Approve(),
        ])

    def deposit():
        amt = ScratchVar()

        return Seq([

            # 2 transactions before should pay/asa to current escrow address
            tidx.store(Txn.group_index() - Int(2)),
            If(App.globalGet(Bytes("aid")) == Int(0),
            Seq([
                MagicAssert(
                    And(
                        Gtxn[tidx.load()].type_enum() == TxnType.Payment,
                        Gtxn[tidx.load()].sender() == Txn.sender(),
                        Or(Txn.sender() ==  App.globalGet(Bytes("w1")), Txn.sender() == App.globalGet(Bytes("w2"))),
                        Gtxn[tidx.load()].receiver() == Global.current_application_address(),
                        Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
                        Gtxn[tidx.load()].close_remainder_to() == Global.zero_address(),
                    )
                ),
                amt.store(Gtxn[tidx.load()].amount())
            ]),
            Seq([
                MagicAssert(
                    And(
                        Gtxn[tidx.load()].type_enum() == TxnType.AssetTransfer,
                        Gtxn[tidx.load()].sender() == Txn.sender(),
                        Or(Txn.sender() ==  App.globalGet(Bytes("w1")), Txn.sender() == App.globalGet(Bytes("w2"))),
                        Gtxn[tidx.load()].asset_receiver() == Global.current_application_address(),
                        Gtxn[tidx.load()].xfer_asset() == App.globalGet(Bytes("aid")),
                        Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
                        Gtxn[tidx.load()].asset_close_to() == Global.zero_address(),
                    )
                ),
                amt.store(Gtxn[tidx.load()].asset_amount())
            ])),

            # 1 transaction before should call the bridge
            tidx.store(Txn.group_index() - Int(1)),
            MagicAssert(
                    And(
                        Gtxn[tidx.load()].type_enum() == TxnType.ApplicationCall,
                        Gtxn[tidx.load()].sender() == Txn.sender(),
                        Gtxn[tidx.load()].application_args[0] == Bytes("deposit"),
                        Gtxn[tidx.load()].application_id() == App.globalGet(Bytes("bid")),
                        Gtxn[tidx.load()].rekey_to() == Global.zero_address(),
                    )
                ),

            Approve(),
        ])

    def updateWhitelist():
        return Seq([
            # Sender should be the bridge
            MagicAssert(And(
                Txn.sender() == getAppAddress(App.globalGet(Bytes("bid"))),
                Txn.application_args.length() == Int(2),
                Txn.accounts.length() == Int(1),
                Or(Txn.application_args[1] == Bytes("w1"), Txn.application_args[1] == Bytes("w2"))
            )),

            App.globalPut(Txn.application_args[1], Txn.accounts[1]),

            Approve(),
        ])

    METHOD = Txn.application_args[0]

    router = Cond(
        [METHOD == Bytes("nop"), nop()],
        [METHOD == Bytes("optin"), optin()],
        [METHOD == Bytes("deposit"), deposit()],
        [METHOD == Bytes("withdraw"), withdraw()],
        [METHOD == Bytes("transfer"), transfer()],
        [METHOD == Bytes("liquidity"), liquidity()],
        [METHOD == Bytes("updateBridge"), updateBridge()],
        [METHOD == Bytes("updateWhitelist"), updateWhitelist()],
    )

    def getOnUpdate():
        return Seq([
            Reject()
        ])

    on_update = getOnUpdate()

    on_optin = Seq( [
        Approve()
    ])

    return Cond(
        [Txn.application_id() == Int(0), on_create],
        [Txn.on_completion() == OnComplete.UpdateApplication, on_update],
        [Txn.on_completion() == OnComplete.DeleteApplication, on_delete],
        [Txn.on_completion() == OnComplete.OptIn, on_optin],
        [Txn.on_completion() == OnComplete.NoOp, router]
    )

def getEscrow(genTeal, approve_name, clear_name, client: AlgodClient, devMode: bool) -> Tuple[bytes, bytes]:
    if not devMode:
        client = AlgodClient("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "https://testnet-api.algonode.cloud")
    APPROVAL_PROGRAM = fullyCompileContract(genTeal, client, approve_escrow(), approve_name, devMode)
    CLEAR_STATE_PROGRAM = fullyCompileContract(genTeal, client, clear_escrow(), clear_name, devMode)

    return APPROVAL_PROGRAM, CLEAR_STATE_PROGRAM
