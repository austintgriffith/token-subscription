pragma solidity ^0.4.24;

/*
   Token Subscriptions on the Blockchain

   WIP POC simplified version of  EIP-1337 / ERC-948

   BYOC - Subscriber 'Brings Your Own Contract'

   Subscriber deploys their own contract that can be used for a number of
   different subscriptions. This is a little more complex than the
   'publisher deploys' model but it is more powerful and flexible too

   //this model of BYOC subscriptions will try to adhere to the ERC948 standards
   //https://gist.github.com/androolloyd/0a62ef48887be00a5eff5c17f2be849a
   //big thanks to my dude Andrew Redden @androolloyd

   Austin Thomas Griffith - https://austingriffith.com

   https://github.com/austintgriffith/token-subscription

   Building on previous works:
    https://media.consensys.net/subscription-services-on-the-blockchain-erc-948-6ef64b083a36
    https://medium.com/gitcoin/technical-deep-dive-architecture-choices-for-subscriptions-on-the-blockchain-erc948-5fae89cabc7a
    https://github.com/ethereum/EIPs/pull/1337
    https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1077.md
    https://github.com/gnosis/safe-contracts

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
    event FailedExecuteSubscription(
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

    // similar to a nonce that avoids replay attacks this allows a single execution
    // every x seconds for a given subscription
    // subscriptionHash  => next valid block number
    mapping(bytes32 => uint256) public nextValidTimestamp;

    // subscription status is tracked by subscription hash
    mapping(bytes32 => SubscriptionStatus) public status;


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
        return true;
    }

    // this is used by external smart contracts to verify on-chain that a
    // particular subscription is "paid" and "active"
    // there must be a small grace period added to allow the publisher
    // or desktop miner to execute
    function isSubscriptionActive(
        bytes32 subscriptionHash,
        uint256 gracePeriodSeconds
    )
        external
        view
        returns (bool)
    {
        return ( block.timestamp >= nextValidTimestamp[subscriptionHash].add(gracePeriodSeconds) &&
                  //I'm not sure if we want this or not.. what if the subscriber wants to
                  // stop paying so they switch the subscription over to paused
                  // but other smart contracts trigger off of this... we want them
                  // to continue to be subscribed until the end of the period
                  // or do we?
                  status[subscriptionHash] == SubscriptionStatus.ACTIVE
        );
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
        ));
    }

    //ecrecover the signer from hash and the signature
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

    //check if a subscription is signed correctly and the timestamp is ready for
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
        return ( validSignerTimestampAndStatus(from, signer, subscriptionHash) );
    }

    //check if a subscription is signed correctly and the timestamp is ready for
    // the next execution to happen
    function validSignerTimestampAndStatus(
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
            ( from==owner || whitelist[from] ) && //only authenticated accounts can exec
            block.timestamp >= nextValidTimestamp[subscriptionHash] &&
            status[subscriptionHash] == SubscriptionStatus.ACTIVE
        );
    }


    // execute the operation
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
        returns (bool success)
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
          validSignerTimestampAndStatus(from,signer,subscriptionHash),
          "Signature, From Account, Timestamp, or status is invalid"
        );



        // increment the next valid period time
        // we must do this first to prevent reentrance, but if something fails
        // we will want to roll this back so we need to remember it
        uint256 tempValidTimestamp = nextValidTimestamp[subscriptionHash];
        nextValidTimestamp[subscriptionHash] = block.timestamp.add(periodSeconds);

        // now, let's borrow a page out of the Gnosis Safe book and run the execute
        //  give it what ever gas we have minus what we'll need to finish the tx
        //  and pay the desktop miner
        bool result = execute(to, value, data, operation, gasleft() - 48000); // 48000 = TOTAL GUESS RIGHT NOW (TODO: FIGURE OUT HOW MUCH GAS IS USED AFTER THIS AND HARD CODE IT HERE)
        if (result) {
            emit ExecuteSubscription(
                from, to, value, data, operation, periodSeconds, gasToken, gasPrice, gasPayer
            );

            //we only want to reward the miner if the transaction was a success
            // if we reward either way, there is an attack vector where the
            // desktop miner can repeatedly execute the metatx and earn gas
            // without the timestamp incrementing or the tx executing successful

            // it is possible for the subscription execution to be run by a third party
            // incentivized in the terms of the subscription with a gasToken and gasPrice
            // pay that out now...
            if (gasPrice > 0) {
                if (gasToken == address(0)) {
                    // this is a case where the subscriber will pay for the tx using
                    // ethereum out of the subscription contract itself
                    // for this to work the publisher must send ethereum to the contract
                    require(msg.sender.call.value(gasPrice).gas(36000)(),//still unsure about how much gas to use here
                        "Subscription contract failed to pay ether to relayer"
                    );
                } else if (gasPayer == address(this) || gasPayer == address(0)) {
                    // in this case, this contract will pay a token to the relayer to
                    // incentivize them to pay the gas for the meta transaction
                    require(ERC20(gasToken).transfer(msg.sender, gasPrice),
                        "Failed to pay gas as contract"
                    );
                } else {
                    // if all else fails, we expect that some account (CAN BE ANY ACCOUNT)
                    // has approved this contract to move tokens on their behalf
                    // this is really cool because the subscriber, the publisher, OR any
                    // third party could reward the relayers with an approved token
                    require(
                        ERC20(gasToken).transferFrom(gasPayer, msg.sender, gasPrice),
                        "Failed to pay gas in tokens from approved gasPayer"
                    );
                }
            }

        } else {

            //if the transaction is not successful, we want to roll back the timestamp so
            // we can try again soon
            nextValidTimestamp[subscriptionHash] = tempValidTimestamp;

            emit FailedExecuteSubscription(
                from, to, value, data, operation, periodSeconds, gasToken, gasPrice, gasPayer
            );
        }

        return result;
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
