/*
ERC20 - note the following:
-No notifications (can be added)
-All tokenids are ignored
-You can use the canister address as the token id
-Memo is ignored
-No transferFrom (as transfer includes a from field)
*/
import AID "../motoko/util/AccountIdentifier";
import AId "../motoko/util/AccountIdentifier";
import Cycles "mo:base/ExperimentalCycles";
import ExtAllowance "../motoko/ext/Allowance";
import ExtCommon "../motoko/ext/Common";
import ExtCore "../motoko/ext/Core";
import ExtTypes "../motoko/ext/Types";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";
import _balances "mo:base/Blob";
import Array "mo:base/Array";

actor class erc20_token(init_name: Text, init_symbol: Text, init_decimals: Nat8, init_supply: ExtCore.Balance, init_owner: Principal) {
  
  // Types
  type AccountIdentifier = ExtCore.AccountIdentifier;
  type SubAccount = ExtCore.SubAccount;
  type User = ExtCore.User;
  type Balance = ExtCore.Balance;
  type TokenIdentifier = ExtCore.TokenIdentifier;
  type Extension = ExtCore.Extension;
  type CommonError = ExtCore.CommonError;
  
  type BalanceRequest = ExtCore.BalanceRequest;
  type BalanceResponse = ExtCore.BalanceResponse;
  type TransferRequest = ExtCore.TransferRequest;
  type TransferResponse = ExtCore.TransferResponse;
  type AllowanceRequest = ExtAllowance.AllowanceRequest;
  type ApproveRequest = ExtAllowance.ApproveRequest;

  type Metadata = ExtCommon.Metadata;

  type MintByOwnerResponse = ExtTypes.MintByOwnerResponse;
  
  private let EXTENSIONS : [Extension] = ["@ext/common", "@ext/allowance"];

  
  //State work
  private stable var _balancesState : [(AccountIdentifier, Balance)] = [];
  private var _balances : HashMap.HashMap<AccountIdentifier, Balance> = HashMap.fromIter(_balancesState.vals(), 0, AID.equal, AID.hash);
  private var _allowances = HashMap.HashMap<AccountIdentifier, HashMap.HashMap<Principal, Balance>>(1, AID.equal, AID.hash);
  private stable var _owner = init_owner;

  private var callRecords : [(AccountIdentifier, Text, Text, Time.Time)] = [];
  
  //State functions
  system func preupgrade() {
    _balancesState := Iter.toArray(_balances.entries());
    //Allowances are not stable, they are lost during upgrades...
  };
  system func postupgrade() {
    _balancesState := [];
  };
  
    //Initial state - could set via class setter
  private stable let METADATA : Metadata = #fungible({
    name = init_name;
    symbol = init_symbol;
    decimals = init_decimals;
    metadata = null;
  }); 
  private stable var _supply : Balance  = init_supply;
  
  _balances.put(AID.fromPrincipal(init_owner, null), _supply);

  public shared(msg) func transfer(request: TransferRequest) : async TransferResponse {
    let owner = ExtCore.User.toAID(request.from);
    let spender = AID.fromPrincipal(msg.caller, request.subaccount);
    let receiver = ExtCore.User.toAID(request.to);

    let callerAID = AId.fromPrincipal(msg.caller, request.subaccount);
    var userType : Text = "";
    // var userType = "address";

    switch(request.from){
      case (#address address) {
        userType := "address";
      };
      case (#principal principal){
        userType := "principal";
      };
    };
    let itemArray = Array.make((callerAID, "transfer", userType, Time.now()));
    callRecords := Array.append(callRecords, itemArray);
    
    switch (_balances.get(owner)) {
      case (?owner_balance) {
        if (owner_balance >= request.amount) {
          if (AID.equal(owner, spender) == false) {
            //Operator is not owner, so we need to validate here
            switch (_allowances.get(owner)) {
              case (?owner_allowances) {
                switch (owner_allowances.get(msg.caller)) {
                  case (?spender_allowance) {
                    if (spender_allowance < request.amount) {
                      return #err(#Other("Spender allowance exhausted"));
                    } else {
                      var spender_allowance_new : Balance = spender_allowance - request.amount;
                      owner_allowances.put(msg.caller, spender_allowance_new);
                      _allowances.put(owner, owner_allowances);
                    };
                  };
                  case (_) {
                    return #err(#Unauthorized1(spender));
                  };
                };
              };
              case (_) {
                return #err(#Unauthorized2(spender));
              };
            };
          };
          
          var owner_balance_new : Balance = owner_balance - request.amount;
          _balances.put(owner, owner_balance_new);
          var receiver_balance_new = switch (_balances.get(receiver)) {
            case (?receiver_balance) {
                receiver_balance + request.amount;
            };
            case (_) {
                request.amount;
            };
          };
          _balances.put(receiver, receiver_balance_new);
          return #ok(request.amount);
        } else {
          return #err(#InsufficientBalance);
        };
      };
      case (_) {
        return #err(#InsufficientBalance);
      };
    };
  };
  
  public shared(msg) func approve(request: ApproveRequest) : async () {
    let owner = AID.fromPrincipal(msg.caller, request.subaccount);
    switch (_allowances.get(owner)) {
      case (?owner_allowances) {
        owner_allowances.put(request.spender, request.allowance);
        _allowances.put(owner, owner_allowances);
      };
      case (_) {
        var temp = HashMap.HashMap<Principal, Balance>(1, Principal.equal, Principal.hash);
        temp.put(request.spender, request.allowance);
        _allowances.put(owner, temp);
      };
    };
  };

  public query func extensions() : async [ExtCore.Extension] {
    EXTENSIONS;
  };
  
  public query func balance(request : BalanceRequest) : async BalanceResponse {
    let aid = ExtCore.User.toAID(request.user);
    switch (_balances.get(aid)) {
      case (?balance) {
        return #ok(balance);
      };
      case (_) {
        return #ok(0);
      };
    }
  };

  public query func supply(token : TokenIdentifier) : async Result.Result<Balance, CommonError> {
    #ok(_supply);
  };
  
  public query func metadata(token : TokenIdentifier) : async Result.Result<Metadata, CommonError> {
    #ok(METADATA);
  };
  
  //Internal cycle management - good general case
  public func acceptCycles() : async () {
    let available = Cycles.available();
    let accepted = Cycles.accept(available);
    assert (accepted == available);
  };
  public query func availableCycles() : async Nat {
    return Cycles.balance();
  };
  
  public shared(msg) func getPrincipal() : async Principal {
    return msg.caller;
  };

  public func getBalances() : async [(AccountIdentifier, Balance)] {
    return Iter.toArray(_balances.entries());
  };

  // public func getAllowances() : async [(AccountIdentifier, Balance)] {
  //   _allowances.entries();
  //   return Iter.toArray(_allowances.entries());
  // };

  public func getOwner() : async Principal {
    return _owner;
  };

  public shared(msg) func mintByOwer(amount : Balance): async ExtTypes.MintByOwnerResponse {
    if (msg.caller != _owner) {
      return #err(#IsNotOwner)
    };
    let ownerAid : AccountIdentifier = AID.fromPrincipal(_owner, null);
    switch(_balances.get(ownerAid)){
      case(?balance) {
        var newBalance = balance + amount;
        _balances.put(ownerAid, newBalance);
        return #ok(newBalance);
      };
      case(_){
        _balances.put(ownerAid, amount);
        return #ok(amount);
      };
    };
  };

  public func getCallRecords() : async [(AccountIdentifier, Text, Text, Time.Time)] {
    return callRecords;
  };
}
