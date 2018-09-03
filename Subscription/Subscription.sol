pragma solidity ^0.4.24;

/*

   Delegated Execution Subscriptions for Ethereum

   WIP POC - EIP-1337 / ERC-948

   BYOC - Subscriber 'Brings Your Own Contract'

   Subscriber deploys their own contract that can be used for a number of
   different subscriptions. This is a little more complex than the
   'publisher deploys' model but it is more powerful and flexible too

   //this model of BYOC subscriptions will try to adhere to the ERC948 standards
   //https://gist.github.com/androolloyd/0a62ef48887be00a5eff5c17f2be849a
   //big thanks to my dude Andrew Redden @androolloyd

   Austin Thomas Griffith - https://austingriffith.com

   Branched from:
    https://github.com/austintgriffith/token-subscription

   Building on previous works:
    https://media.consensys.net/subscription-services-on-the-blockchain-erc-948-6ef64b083a36
    https://medium.com/gitcoin/technical-deep-dive-architecture-choices-for-subscriptions-on-the-blockchain-erc948-5fae89cabc7a
    https://github.com/ethereum/EIPs/pull/1337
    https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1077.md
    https://github.com/gnosis/safe-contracts
    https://github.com/ethereum/EIPs/issues/1228

  Earlier Meta Transaction Demo:
    https://github.com/austintgriffith/bouncer-proxy

  Huge thanks to, as always, to OpenZeppelin for the rad contracts:
 */

import "openzeppelin-solidity/contracts/ECRecovery.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";


contract Subscription is Ownable {
    using ECRecovery for bytes32;
    using SafeMath for uint256;

    enum SubscriptionStatus {
        ACTIVE,
        PAUSED,
        CANCELLED,
        EXPIRED
    }
    enum Operation {
        Call,
        DelegateCall,
        Create
    }

    //waste some gas and define our purpose on-chain :)
    string public purpose = "Delegated Execution Subscriptions (POC) [EIP1337/948]";
    string public author = "Austin Thomas Griffith - https://austingriffith.com";

    constructor() public { }

    // contract will need to hold funds to pay gas
    // copied from https://github.com/uport-project/uport-identity/blob/develop/contracts/Proxy.sol
    function () public payable {
        emit Received(msg.sender, msg.value);
    }

    event Received (address indexed sender, uint value);
    event ExecuteSubscription(
        address from, //the subscriber
        address to, //the publisher
        uint256 value, //amount in wei of ether sent from this contract to the to address
        bytes data, //the encoded transaction data (first four bytes of fn plus args, etc)
        Operation operation, //ENUM of operation
        uint256 periodSeconds, //the period in seconds between payments
        address gasToken, //the address of the token to pay relayer (0 for eth)
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        address gasPayer //the address that will pay the tokens to the relayer
    );
    event ContractCreation(address newContract);
    event UpdateWhitelist(address account, bool value);

    //this event is used just to prove that the delegatecall hits it back
    event Announce(bytes32 message,uint256 timestamp,address sender,address context);

    // similar to a nonce that avoids replay attacks this allows a single execution
    // every x seconds for a given subscription
    // subscriptionHash  => next valid block number
    mapping(bytes32 => uint256) public nextValidTimestamp;

    // subscription status is tracked by subscription hash
    mapping(bytes32 => SubscriptionStatus) public subscriptionStatus;

    // since owners can update the subscriptionStatus with a metaTx, we'll
    // need a nonce to avoid replay attacks
    mapping(bytes32 => uint256) public subscriptionStatusNonce;


    // allow for third party metatx account to make transactions through this
    // contract like an identity but make sure the owner has whitelisted the tx
    mapping(address => bool) public whitelist;
    // let the owner add and remove addresses from the whitelist
    function updateWhitelist(address _account, bool _value)
        public
        onlyOwner
        returns(bool)
    {
        whitelist[_account] = _value;
        emit UpdateWhitelist(_account,whitelist[_account]);
        return true;
    }

    // this is used by external smart contracts to verify on-chain that a
    // particular subscription is "paid" (has executed within the period)
    // there must be a small grace period added to allow the publisher
    // or desktop miner to execute
    function isSubscriptionPaid(
        bytes32 subscriptionHash,
        uint256 gracePeriodSeconds
    )
        external
        view
        returns (bool)
    {
        return ( block.timestamp >= nextValidTimestamp[subscriptionHash].add(gracePeriodSeconds) );
    }

    // this is used for checking what status the owner has switching it to
    // this is for checking if the owner has moved it to paused even if it
    // is already paid, this can signal that they no longer want to pay the
    // next pay period
    function getSubscriptionStatus(
        bytes32 subscriptionHash
    )
        public
        view
        returns  (uint256)
    {
        return uint256(subscriptionStatus[subscriptionHash]);
    }

    // given the subscription details, generate a hash and try to kind of follow
    // the eip-191 standard and eip-1077 standard from my dude @avsa
    function getSubscriptionHash(
        address from, //the subscriber
        address to, //the publisher
        uint256 value, //amount in wei of ether sent from this contract to the to address
        bytes data, //the encoded transaction data (first four bytes of fn plus args, etc)
        Operation operation, //ENUM of operation
        uint256 periodSeconds, //the period in seconds between payments
        address gasToken, //the address of the token to pay relayer (0 for eth)
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        address gasPayer //the address that will pay the tokens to the relayer
    )
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                byte(0x19),
                byte(0),
                address(this),
                from,
                to,
                value,
                data,
                operation,
                periodSeconds,
                gasToken,
                gasPrice,
                gasPayer
            )
        );
    }

    // ecrecover the signer from hash and the signature
    function getSubscriptionSigner(
        bytes32 subscriptionHash, //hash of subscription
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        pure
        returns (address)
    {
        return subscriptionHash.toEthSignedMessageHash().recover(signature);
    }

    // check if a subscription is signed correctly and the timestamp is ready for
    // the next execution to happen
    function isSubscriptionReady(
        address from, //the subscriber
        address to, //the publisher
        uint256 value, //amount in wei of ether sent from this contract to the to address
        bytes data, //the encoded transaction data (first four bytes of fn plus args, etc)
        Operation operation, //ENUM of operation
        uint256 periodSeconds, //the period in seconds between payments
        address gasToken, //the address of the token to pay relayer (0 for eth)
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        address gasPayer, //the address that will pay the tokens to the relayer
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        view
        returns (bool)
    {
        bytes32 subscriptionHash = getSubscriptionHash(
            from, to, value, data, operation, periodSeconds, gasToken, gasPrice, gasPayer
        );
        address signer = getSubscriptionSigner(subscriptionHash, signature);
        return ( isValidSignerTimestampAndStatus(from, signer, subscriptionHash) );
    }

    // check if a subscription is signed correctly and the timestamp is ready for
    // the next execution to happen
    function isValidSignerTimestampAndStatus(
        address from,
        address signer,
        bytes32 subscriptionHash
    )
        public
        view
        returns (bool)
    {
        return (
            signer == from &&
            ( signer == owner || whitelist[signer] ) && //only authenticated accounts can exec
            block.timestamp >= nextValidTimestamp[subscriptionHash] &&
            subscriptionStatus[subscriptionHash] == SubscriptionStatus.ACTIVE
        );
    }

    // to modify the status, an owner or whitelisted account needs to sign
    // the hash of the change to send it as a meta tx
    function getModifyStatusHash(
        bytes32 subscriptionHash,
        SubscriptionStatus status
    )
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                byte(0x19),
                byte(0),
                address(this),
                subscriptionHash,
                status,
                subscriptionStatusNonce[subscriptionHash]
            )
        );
    }

    // check if a subscription is signed correctly and the timestamp is ready for
    // the next execution to happen
    function isValidModifyStatusSigner(
        bytes32 subscriptionHash,
        SubscriptionStatus status,
        bytes signature
    )
        public
        view
        returns (bool)
    {
        address signer = getModifyStatusHash(subscriptionHash, status).toEthSignedMessageHash().recover(signature);
        return (
            ( signer==owner || whitelist[signer] ) &&
            //once the status is expired or cancelled, it can no longer change
            ( subscriptionStatus[subscriptionHash] == SubscriptionStatus.ACTIVE || subscriptionStatus[subscriptionHash] == SubscriptionStatus.PAUSED )
        );
    }

    // the owner or any of the whitelisted accounts can sign the meta tx to
    // modify the transaction
    function modifyStatus(
        bytes32 subscriptionHash,
        SubscriptionStatus status,
        bytes signature
    )
        public
        returns (bool)
    {
        require(
            isValidModifyStatusSigner(subscriptionHash, status, signature),
            "Invalid modify status signature"
        );
        subscriptionStatusNonce[subscriptionHash]++;
        // if this subscription is getting unpaused (PAUSED -> ACTIVE) we need to check
        // to see if more time than the periodSeconds has elapsed ... this means that
        // without any changes, multiple executions could happen and we need to fast
        // forward the nextValidTimestamp to now ...
        // ex: they pause for 3 months and then make it active again... you don't want
        //   it to be able to submit 3 transactions right away, just one
        if( subscriptionStatus[subscriptionHash] == SubscriptionStatus.PAUSED &&
          status == SubscriptionStatus.ACTIVE &&
          block.timestamp > nextValidTimestamp[subscriptionHash] )
        {
          nextValidTimestamp[subscriptionHash] = block.timestamp;
        }
        subscriptionStatus[subscriptionHash] = status;
        return true;
    }

    // execute the operation through delegated execution and reward the miner
    // this function will also increment the timestamp nonce to the next value
    // in which it will be valid
    // we tried to make our execution just like Gnosis Safe so the metatx
    // networks can be similar or even the same
    function executeSubscription(
        address from, //the subscriber
        address to, //the publisher
        uint256 value, //amount in wei of ether sent from this contract to the to address
        bytes data, //the encoded transaction data (first four bytes of fn plus args, etc)
        Operation operation, //ENUM of operation
        uint256 periodSeconds, //the period in seconds between payments
        address gasToken, //the address of the token to pay relayer (0 for eth)
        uint256 gasPrice, //the amount of tokens or eth to pay relayer (0 for free)
        address gasPayer, //the address that will pay the tokens to the relayer
        bytes signature //proof the subscriber signed the meta trasaction
    )
        public
        returns (bool)
    {
        // make sure the subscription is valid and ready
        // pulled this out so I have the hash, should be exact code as "isSubscriptionReady"
        bytes32 subscriptionHash = getSubscriptionHash(
            from, to, value, data, operation, periodSeconds, gasToken, gasPrice, gasPayer
        );
        address signer = getSubscriptionSigner(subscriptionHash, signature);

        //the signature must be valid
        // had to put this in one function because the stack was too deep
        require(
          isValidSignerTimestampAndStatus(from,signer,subscriptionHash),
          "Signature, From Account, Timestamp, or status is invalid"
        );

        // increment the next valid period time
        // we must do this first to prevent reentrance
        if(nextValidTimestamp[subscriptionHash]<=0){
          //if this is the very first, start from the current time
          nextValidTimestamp[subscriptionHash]=block.timestamp+periodSeconds;
        }else{
          nextValidTimestamp[subscriptionHash]=nextValidTimestamp[subscriptionHash]+periodSeconds;
        }

        // -- Reward Desktop Miner (Relayer/Operator)
        // it is possible for the subscription execution to be run by a third party
        // incentivized in the terms of the subscription with a gasToken and gasPrice
        // pay that out now...
        if (gasPrice > 0) {
            if (gasToken == address(0)) {
                // this is a case where the subscriber will pay for the tx using
                // ethereum out of the subscription contract itself
                // for this to work the subscriber must send ethereum to the contract
                require(tx.origin.call.value(gasPrice).gas(36000)(),//still unsure about how much gas to use here
                    "Subscription contract failed to pay ether to relayer"
                );
            } else if (gasPayer == address(this) || gasPayer == address(0)) {
                // in this case, this contract will pay a token to the relayer to
                // incentivize them to pay the gas for the meta transaction
                require(ERC20(gasToken).transfer(tx.origin, gasPrice),
                    "Failed to pay gas as contract"
                );
            } else {
                // if all else fails, we expect that some account (CAN BE ANY ACCOUNT)
                // has approved this contract to move tokens on their behalf
                // this is really cool because the subscriber, the publisher, OR any
                // third party could reward the relayers with an approved token
                require(
                    ERC20(gasToken).transferFrom(gasPayer, tx.origin, gasPrice),
                    "Failed to pay gas in tokens from approved gasPayer"
                );
            }
        }

        //Emit event
        emit ExecuteSubscription(
          from, to, value, data, operation, periodSeconds, gasToken, gasPrice, gasPayer
        );

        // now, let's borrow a page out of the Gnosis Safe book and run the execute
        //  give it what ever gas we have minus what we'll need to finish the tx
        //  and pay the desktop miner
        require(
          execute(to, value, data, operation, gasleft()),
          "Failed to execute subscription"
        );

        return true;
    }


    // Gnosis Safe is the dopest but it has a lot of functionality we dont need
    // let's borrow their executor for different operations here
    // all the love and props go to *** rmeissner ***
    // https://github.com/gnosis/safe-contracts/blob/development/contracts/base/Executor.sol
    function execute(address to, uint256 value, bytes data, Operation operation, uint256 txGas)
       internal
       returns (bool success)
    {
       if (operation == Operation.Call)
           success = executeCall(to, value, data, txGas);
       else if (operation == Operation.DelegateCall)
           success = executeDelegateCall(to, data, txGas);
       else {
           address newContract = executeCreate(data);
           success = newContract != 0;
           emit ContractCreation(newContract);
       }
    }

    function executeCall(address to, uint256 value, bytes data, uint256 txGas)
       internal
       returns (bool success)
    {
       // solium-disable-next-line security/no-inline-assembly
       assembly {
           success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
       }
    }

    function executeDelegateCall(address to, bytes data, uint256 txGas)
       internal
       returns (bool success)
    {
       // solium-disable-next-line security/no-inline-assembly
       assembly {
           success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
       }
    }

    function executeCreate(bytes data)
       internal
       returns (address newContract)
    {
       // solium-disable-next-line security/no-inline-assembly
       assembly {
           newContract := create(0, add(data, 0x20), mload(data))
       }
    }
}
