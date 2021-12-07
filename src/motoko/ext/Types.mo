
import Result "mo:base/Result";

import ExtCore "./Core";

module {
    public type MintByOwnerResponse = Result.Result<ExtCore.Balance, {
        #IsNotOwner
    }>
};